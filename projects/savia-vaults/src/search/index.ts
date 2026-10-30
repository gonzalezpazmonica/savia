import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import MiniSearch from 'minisearch';
import { ensureSafeHome, writeAtomic } from '../rag/store.js';
import { KnowledgeGraph } from '../knowledge/graph.js';
import { PPRRanker } from '../knowledge/ppr.js';
import { ContextEnricher } from './enrichment.js';
import type { VaultConfig, SearchQuery, SearchResult } from '../types.js';
import { fileOutOfLevel } from '../storage/note-level.js';

interface IndexedDoc {
  id: string;
  path: string;
  title: string;
  content: string;
  tags: string[];
}

const MINI_OPTIONS = {
  fields: ['title', 'content', 'tags'],
  // SE-412: sin `content`: el snippet se lee del fichero solo para los hits devueltos
  // (el texto completo era el 62 % del índice serializado).
  storeFields: ['path', 'title', 'tags'],
  searchOptions: {
    boost: { title: 2 },
    prefix: true,
    fuzzy: 0.2,
  },
};

/** SE-412: solo markdown salvo que la cúpula declare `allowedExtensions`. */
const DEFAULT_EXTENSIONS = ['.md', '.markdown'];
const CACHE_VERSION = 4; // SE-420/SE-481: descarta cachés con notas fuera de nivel o en cuarentena

export function defaultSearchCacheDir(): string {
  return process.env.SAVIA_SEARCH_CACHE || path.join(os.homedir(), '.savia-vaults', 'search-cache');
}

export interface SearchEngineOptions {
  /** SE-412: caché persistente del índice (CLI). El servidor MCP no la necesita. */
  cacheDir?: string;
}

export class SearchEngine {
  private config: VaultConfig;
  private engine: MiniSearch<IndexedDoc>;
  private _built = false;
  private _fingerprint = '';
  private readonly cacheDir?: string;

  constructor(config: VaultConfig, opts: SearchEngineOptions = {}) {
    this.config = config;
    this.cacheDir = opts.cacheDir;
    this.engine = new MiniSearch<IndexedDoc>(MINI_OPTIONS);
  }

  private cacheFile(): string | undefined {
    if (!this.cacheDir) return undefined;
    const key = createHash('sha256').update(path.resolve(this.config.path)).digest('hex').slice(0, 12);
    return path.join(this.cacheDir, key, 'index.json');
  }

  /** Carga el índice serializado si su fingerprint coincide. */
  private loadCache(fingerprint: string): boolean {
    const file = this.cacheFile();
    if (!file) return false;
    try {
      const data = JSON.parse(fs.readFileSync(file, 'utf-8')) as { v: number; fingerprint: string; index: unknown };
      if (data.v !== CACHE_VERSION || data.fingerprint !== fingerprint) return false;
      this.engine = MiniSearch.loadJS<IndexedDoc>(data.index as never, MINI_OPTIONS);
      return true;
    } catch {
      return false;
    }
  }

  /** La caché copia texto de las notas: 0600, fuera de git; si no es posible, se omite. */
  private saveCache(fingerprint: string): void {
    const file = this.cacheFile();
    if (!file) return;
    try {
      ensureSafeHome(path.dirname(file));
      writeAtomic(file, JSON.stringify({ v: CACHE_VERSION, fingerprint, index: this.engine }));
    } catch {
      // caché opcional
    }
  }

  /**
   * Build (or refresh) the in-memory index.
   * SE-310: el indice se reconstruye SOLO si cambia (fingerprint por mtime+count),
   * no en cada request — evita el cuelgue con vaults grandes o node_modules.
   */
  buildIndex(force = false): void {
    const fingerprint = this.fingerprint();
    if (!force && this._built && fingerprint === this._fingerprint) return;
    this._fingerprint = fingerprint;
    this._built = true;
    if (this.loadCache(fingerprint)) return;
    this.engine.removeAll();
    const files = this.listFiles();
    for (const f of files) {
      const fullPath = path.join(this.config.path, f);
      try {
        const raw = fs.readFileSync(fullPath, 'utf-8');
        const { title, content, tags } = this.parseNote(raw);
        this.engine.add({
          id: f,
          path: f,
          title,
          content,
          tags,
        });
      } catch {
        // skip files that can't be read
      }
    }
    this.saveCache(fingerprint);
  }

  /** Fingerprint determinista del vault: max(mtime) + count de ficheros. */
  private fingerprint(): string {
    let newest = 0;
    let count = 0;
    const files = this.listFiles();
    for (const f of files) {
      count += 1;
      try {
        const st = fs.statSync(path.join(this.config.path, f));
        if (st.mtimeMs > newest) newest = st.mtimeMs;
      } catch { /* ignore */ }
    }
    // SE-420: el nivel de la cúpula forma parte de la huella: reclasificarla invalida la caché.
    return `${count}:${Math.round(newest)}:${this.config.confidentiality ?? ''}`;
  }

  search(query: SearchQuery): SearchResult[] {
    const rawResults = this.engine.search(query.query, {});
    const maxResults = query.maxResults || 20;

    const filtered = rawResults
      .filter((r) => {
        const p = (r as unknown as { path: string }).path;
        if (query.pathPrefix) {
          return p.startsWith(query.pathPrefix);
        }
        return true;
      })
      .slice(0, maxResults)
      .map((r) => {
        const doc = r as unknown as { path: string; score: number; title: string; tags: string[] };
        return {
          path: doc.path,
          score: doc.score,
          snippet: this.makeSnippet(this.readContent(doc.path), query.query, 120),
          tags: doc.tags || [],
        };
      });

    return filtered;
  }

  /**
   * SE-330: búsqueda enriquecida con score del grafo (context enrichment).
   * Determinista; best-effort (si el grafo falla, devuelve los resultados BM25).
   */
  async searchEnrichedAsync(query: SearchQuery): Promise<SearchResult[] | import('./enrichment.js').EnrichedResult[]> {
    const base = this.search(query);
    if (!query.enrich || base.length === 0) return base;
    try {
      const graph = new KnowledgeGraph(this.config);
      await graph.build();
      const ppr = new PPRRanker();
      const enricher = new ContextEnricher();
      return enricher.enrich(base, graph.getSnapshot() ?? { nodes: new Map() }, ppr);
    } catch {
      return base;
    }
  }

  /** Cuerpo de la nota (sin frontmatter) para el snippet; '' si ya no se puede leer. */
  private readContent(relPath: string): string {
    try {
      return this.parseNote(fs.readFileSync(path.join(this.config.path, relPath), 'utf-8')).content;
    } catch {
      return '';
    }
  }

  getTags(): Map<string, number> {
    const tagCounts = new Map<string, number>();
    const files = this.listFiles();

    for (const f of files) {
      const fullPath = path.join(this.config.path, f);
      try {
        const raw = fs.readFileSync(fullPath, 'utf-8');
        const { tags } = this.parseNote(raw);
        for (const tag of tags) {
          tagCounts.set(tag, (tagCounts.get(tag) || 0) + 1);
        }
      } catch {}
    }

    return new Map([...tagCounts.entries()].sort((a, b) => b[1] - a[1]));
  }

  private listFiles(): string[] {
    const results: string[] = [];
    this.walk(this.config.path, '', results);
    return results;
  }

  private walk(base: string, relative: string, results: string[]): void {
    const full = path.join(base, relative);
    if (!fs.existsSync(full)) return;

    const exts = this.config.allowedExtensions?.length
      ? this.config.allowedExtensions.map(e => e.toLowerCase())
      : DEFAULT_EXTENSIONS;
    const entries = fs.readdirSync(full, { withFileTypes: true });
    for (const e of entries) {
      const relPath = relative ? `${relative}/${e.name}` : e.name;
      if (e.isDirectory()) {
        // SE-412: fuera directorios ocultos (.git, .trash, .savia-vault…) y node_modules.
        if (e.name.startsWith('.') || e.name === 'node_modules') continue;
        this.walk(base, relPath, results);
      } else if (e.isFile() && exts.includes(path.extname(e.name).toLowerCase())) {
        // SE-420: las notas fuera de nivel no se indexan ni cuentan para etiquetas.
        if (fileOutOfLevel(path.join(base, relPath), relPath, this.config.confidentiality)) continue;
        results.push(relPath);
      }
    }
  }

  private parseNote(raw: string): { title: string; content: string; tags: string[] } {
    const tags = new Set<string>();

    const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
    let title = '';
    let content = raw;

    if (match) {
      const frontmatterBlock = match[1];
      content = match[2].trim();

      const titleMatch = frontmatterBlock.match(/title:\s*(.+)/);
      if (titleMatch) title = titleMatch[1].trim();

      const tagsMatch = frontmatterBlock.match(/tags:\s*\[(.+?)\]/);
      if (tagsMatch) {
        for (const t of tagsMatch[1].split(',')) {
          tags.add(t.trim().toLowerCase());
        }
      }
    }

    if (!title) {
      const h1Match = content.match(/^#\s+(.+)/m);
      if (h1Match) title = h1Match[1];
    }

    // SE-412: un tag empieza por letra; `#648` (referencia a PR/issue) no es tag.
    const inlineTags = content.match(/#[A-Za-zÀ-ɏ][\w-]*/g);
    if (inlineTags) {
      for (const t of inlineTags) {
        tags.add(t.slice(1).toLowerCase());
      }
    }

    return { title, content, tags: [...tags] };
  }

  private makeSnippet(content: string, query: string, maxLen: number): string {
    const words = query.toLowerCase().split(/\s+/);
    let bestIdx = 0;

    for (const w of words) {
      const idx = content.toLowerCase().indexOf(w);
      if (idx >= 0) {
        bestIdx = Math.max(0, idx - 40);
        break;
      }
    }

    let snippet = content.slice(bestIdx, bestIdx + maxLen);
    if (bestIdx > 0) snippet = '...' + snippet;
    if (content.length > bestIdx + maxLen) snippet = snippet + '...';
    return snippet;
  }
}
