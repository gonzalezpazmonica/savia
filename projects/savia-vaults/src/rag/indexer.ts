import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { chunkMarkdown } from './chunker.js';
import type { Embedder } from './embedder.js';
import { FlatVectorStore, domeDir, ensureSafeHome, gcGeneration, generationId, readActive, writeActive } from './store.js';
import { RAG_LIMITS, RagError, type Chunk, type EmbeddingContract, type Manifest, type ResolvedRagConfig, type SyncReport, type VirtualSource, type IndexCipher } from './types.js';

/**
 * SE-410 — Indexer incremental (P2): hash por documento y por chunk; solo se
 * embeben chunks nuevos; los borrados se purgan en el mismo sync.
 */

const LOCK_FILE = 'sync.lock';
const LOCK_STALE_MS = 10 * 60 * 1000;
const SKIP_DIRS = new Set(['node_modules']);

export interface IndexableFile { path: string; mtimeMs: number; size: number }

export function listIndexable(vaultPath: string): IndexableFile[] {
  const out: IndexableFile[] = [];
  const walk = (rel: string) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(path.join(vaultPath, rel), { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const relPath = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) {
        if (!SKIP_DIRS.has(e.name)) walk(relPath);
      } else if (e.isFile() && e.name.toLowerCase().endsWith('.md')) {
        const st = fs.statSync(path.join(vaultPath, relPath));
        if (st.size <= RAG_LIMITS.maxFileBytes) out.push({ path: relPath, mtimeMs: st.mtimeMs, size: st.size });
      }
    }
  };
  walk('');
  return out.sort((a, b) => a.path.localeCompare(b.path));
}

/** Fingerprint barato (SE-310): count + max mtime; con fuentes virtuales, hash de sus hashes. */
export function fingerprintOf(files: IndexableFile[], virtual: VirtualSource[] = []): string {
  let newest = 0;
  for (const f of files) if (f.mtimeMs > newest) newest = f.mtimeMs;
  const base = `${files.length}:${Math.round(newest)}`;
  if (!virtual.length) return base;
  return `${base}:v${virtual.length}:${sha256(virtual.map(v => `${v.path}=${v.hash}`).join('\n')).slice(0, 16)}`;
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === 'EPERM';
  }
}

/** Lock O_EXCL con pid y timestamp; huérfano si el pid no existe o tiene > 10 min. */
export function acquireLock(dir: string, lockName = LOCK_FILE): boolean {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const file = path.join(dir, lockName);
  const payload = JSON.stringify({ pid: process.pid, ts: Date.now() });
  try {
    fs.writeFileSync(file, payload, { flag: 'wx', mode: 0o600 });
    return true;
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== 'EEXIST') throw e;
  }
  let holder: { pid?: number; ts?: number } = {};
  try { holder = JSON.parse(fs.readFileSync(file, 'utf-8')); } catch { /* ilegible = huérfano */ }
  const orphan = !holder.pid || !pidAlive(holder.pid) || !holder.ts || Date.now() - holder.ts > LOCK_STALE_MS;
  if (!orphan) return false;
  fs.rmSync(file, { force: true });
  try {
    fs.writeFileSync(file, payload, { flag: 'wx', mode: 0o600 });
    return true;
  } catch {
    return false;
  }
}

export function releaseLock(dir: string, lockName = LOCK_FILE): void {
  const file = path.join(dir, lockName);
  try {
    const holder = JSON.parse(fs.readFileSync(file, 'utf-8'));
    if (holder.pid === process.pid) fs.rmSync(file, { force: true });
  } catch { /* nada que liberar */ }
}

export function logEvent(home: string, event: Record<string, unknown>): void {
  try {
    const dir = path.join(home, 'logs');
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    fs.appendFileSync(path.join(dir, 'rag.jsonl'), JSON.stringify({ ts: new Date().toISOString(), ...event }) + '\n', { mode: 0o600 });
  } catch { /* el log nunca rompe un sync */ }
}

/** Prefijo de `skipped` para notas en cuarentena (SE-481); le sigue el código de diagnóstico. */
const QUARANTINE = 'quarantine:';

const sha256 = (data: string | Buffer) => createHash('sha256').update(data).digest('hex');

/** CRIT-001: una nota con nivel superior al de su cúpula no se embebe (regla común, SE-420). */
export { exceedsDomeLevel } from '../storage/note-level.js';
import { CLASSIFICATION_RULES, exceedsDomeLevel, parseClassification, verdictOf } from '../storage/note-level.js';

export interface IndexerOptions {
  dome: string;
  vaultPath: string;
  home: string;
  cfg: ResolvedRagConfig;
  embedder: Embedder;
  /** Nivel de la cúpula (def. N2). */
  domeLevel?: string;
  /** SE-413: fuentes no markdown (p. ej. Savia Files) que se indexan junto a las notas. */
  sources?: () => VirtualSource[];
  /** SE-417: la cúpula está cifrada; el índice se escribe sellado. */
  cipher?: IndexCipher;
}

export interface PendingInfo {
  totalDocs: number;
  pendingDocs: number;
  lagHours: number;
  fingerprint: string;
  generation?: string;
}

export class RagIndexer {
  constructor(private readonly o: IndexerOptions) {}

  get dir(): string { return domeDir(this.o.home, this.o.dome); }

  /** Documentos pendientes respecto a la generación activa (P3/P7). */
  async pending(files = listIndexable(this.o.vaultPath)): Promise<PendingInfo> {
    const active = readActive(this.o.home, this.o.dome).active;
    const manifest = active ? FlatVectorStore.readManifest(path.join(this.dir, active)) : undefined;
    const virtual = this.o.sources?.() ?? [];
    const fingerprint = fingerprintOf(files, virtual);
    const totalDocs = files.length + virtual.length;
    if (!manifest) {
      const oldest = [...files, ...virtual].reduce((m, f) => Math.min(m, f.mtimeMs), Date.now());
      return { totalDocs, pendingDocs: totalDocs, lagHours: totalDocs ? (Date.now() - oldest) / 3.6e6 : 0, fingerprint };
    }
    let pendingDocs = 0;
    let oldestPending = Infinity;
    const seen = new Set<string>();
    for (const f of files) {
      seen.add(f.path);
      const d = manifest.docs[f.path];
      if (!d || d.mtimeMs !== f.mtimeMs) {
        pendingDocs++;
        oldestPending = Math.min(oldestPending, f.mtimeMs);
      }
    }
    for (const v of virtual) {
      seen.add(v.path);
      const d = manifest.docs[v.path];
      if (!d || d.hash !== v.hash) {
        pendingDocs++;
        oldestPending = Math.min(oldestPending, v.mtimeMs);
      }
    }
    for (const p of Object.keys(manifest.docs)) {
      if (!seen.has(p)) {
        pendingDocs++;
        oldestPending = Math.min(oldestPending, Date.parse(manifest.updatedAt) || Date.now());
      }
    }
    const lagHours = pendingDocs ? Math.max(0, (Date.now() - oldestPending) / 3.6e6) : 0;
    return { totalDocs, pendingDocs, lagHours, fingerprint, generation: manifest.generation };
  }

  async sync(opts: { rebuild?: boolean } = {}): Promise<SyncReport> {
    const started = Date.now();
    ensureSafeHome(this.o.home);
    const lockDir = this.dir;
    if (!acquireLock(lockDir)) throw new RagError('LOCKED', `sync de ${this.o.dome} en curso en otro proceso`);
    try {
      const contract: EmbeddingContract = await this.o.embedder.contract();
      const generation = generationId(contract);
      const genDir = path.join(this.dir, generation);
      const previous = opts.rebuild ? undefined : this.tryLoad(genDir, contract);
      const prevDocs = previous?.manifest.docs ?? {};
      const prevByHash = new Map<string, number>();
      previous?.chunks.forEach((c, i) => prevByHash.set(c.hash, i));

      const files = listIndexable(this.o.vaultPath);
      const virtual = this.o.sources?.() ?? [];
      const report: SyncReport = {
        dome: this.o.dome, generation, promoted: false, shadow: false,
        docs: { added: 0, updated: 0, deleted: 0, unchanged: 0, skipped: 0, quarantined: 0 },
        quarantine: {},
        chunks: { total: 0, embedded: 0, reused: 0 },
        durationMs: 0,
      };

      const docs: Manifest['docs'] = {};
      const finalChunks: Chunk[] = [];
      const finalVectors: (Float32Array | undefined)[] = [];
      const toEmbed: number[] = [];
      let mtimeOnly = false;
      /** Reutiliza el vector si el chunk (por hash) ya existía; si no, lo encola para embeber. */
      const addChunks = (chunks: Chunk[]) => {
        for (const c of chunks) {
          c.hash = sha256(`${generation}\n${c.embedText}`);
          const reuse = prevByHash.get(c.hash);
          finalChunks.push(c);
          if (reuse !== undefined && previous) {
            finalVectors.push(new Float32Array(previous.vector(reuse)));
          } else {
            finalVectors.push(undefined);
            toEmbed.push(finalChunks.length - 1);
          }
        }
      };

      // SE-481: si las reglas de clasificación cambiaron desde la generación previa, las notas
      // reutilizadas se vuelven a clasificar (una vez) en lugar de arrastrarse sin mirar.
      const recheck = !previous || previous.manifest.classificationRules !== CLASSIFICATION_RULES;
      const quarantined = (code: string) => {
        report.docs.quarantined++;
        report.quarantine[code] = (report.quarantine[code] ?? 0) + 1;
      };
      for (const f of files) {
        const prev = prevDocs[f.path];
        if (prev && prev.mtimeMs === f.mtimeMs && previous && !recheck) {
          this.carry(previous, prev.chunkIds, finalChunks, finalVectors);
          docs[f.path] = prev;
          if (prev.skipped?.startsWith(QUARANTINE)) quarantined(prev.skipped.slice(QUARANTINE.length));
          else if (prev.skipped) report.docs.skipped++;
          else report.docs.unchanged++;
          continue;
        }
        const buf = fs.readFileSync(path.join(this.o.vaultPath, f.path));
        const hash = sha256(buf);
        const raw = buf.toString('utf-8');
        // R2: clasificación explícita no interpretable ⇒ cuarentena (no se indexa en ninguna cúpula).
        const cls = parseClassification(f.path, raw);
        const verdict = verdictOf(cls, this.o.domeLevel ?? 'N2');
        if (verdict === 'quarantine') {
          docs[f.path] = { hash, mtimeMs: f.mtimeMs, chunkIds: [], skipped: `${QUARANTINE}${cls.diagnostic}` };
          quarantined(cls.diagnostic!);
          continue;
        }
        if (prev && prev.hash === hash && previous && !prev.skipped?.startsWith(QUARANTINE)) {
          this.carry(previous, prev.chunkIds, finalChunks, finalVectors);
          docs[f.path] = { ...prev, mtimeMs: f.mtimeMs };
          if (prev.skipped) report.docs.skipped++;
          else report.docs.unchanged++;
          if (prev.mtimeMs !== f.mtimeMs) mtimeOnly = true;
          continue;
        }
        if (verdict === 'out-of-level') {
          docs[f.path] = { hash, mtimeMs: f.mtimeMs, chunkIds: [], skipped: `confidentiality:${cls.level}` };
          report.docs.skipped++;
          continue;
        }
        prev && !prev.skipped ? report.docs.updated++ : report.docs.added++;
        const chunks = chunkMarkdown(f.path, raw, {
          chunkChars: contract.chunkChars, overlap: contract.overlap, mtime: new Date(f.mtimeMs),
        });
        addChunks(chunks);
        docs[f.path] = { hash, mtimeMs: f.mtimeMs, chunkIds: chunks.map(c => c.id) };
      }
      // SE-413: fuentes virtuales; el hash de la fuente (revisión + troceado) decide si se re-trocea.
      for (const v of virtual) {
        const prev = prevDocs[v.path];
        if (prev && prev.hash === v.hash && previous) {
          this.carry(previous, prev.chunkIds, finalChunks, finalVectors);
          docs[v.path] = prev;
          if (prev.skipped) report.docs.skipped++;
          else report.docs.unchanged++;
          continue;
        }
        if (exceedsDomeLevel(v.confidentiality, this.o.domeLevel ?? 'N2')) {
          docs[v.path] = { hash: v.hash, mtimeMs: v.mtimeMs, chunkIds: [], skipped: `confidentiality:${v.confidentiality}` };
          report.docs.skipped++;
          continue;
        }
        prev && !prev.skipped ? report.docs.updated++ : report.docs.added++;
        const chunks = v.chunks({ chunkChars: contract.chunkChars, overlap: contract.overlap });
        addChunks(chunks);
        docs[v.path] = { hash: v.hash, mtimeMs: v.mtimeMs, chunkIds: chunks.map(c => c.id) };
      }
      for (const p of Object.keys(prevDocs)) if (!(p in docs)) report.docs.deleted++;

      if (toEmbed.length) {
        const vectors = await this.o.embedder.embed(toEmbed.map(i => finalChunks[i].embedText), 'doc');
        toEmbed.forEach((idx, j) => { finalVectors[idx] = vectors[j]; });
      }
      report.chunks.embedded = toEmbed.length;
      report.chunks.reused = finalChunks.length - toEmbed.length;
      report.chunks.total = finalChunks.length;

      const changed = !previous || report.docs.added + report.docs.updated + report.docs.deleted > 0
        || (Boolean(this.o.cipher) && !previous.manifest.sealed) // SE-417: un índice en claro se re-escribe sellado
        || Object.keys(docs).some(p => (docs[p].skipped ?? '') !== (prevDocs[p]?.skipped ?? '')); // SE-481: también cambio de código
      const now = new Date().toISOString();
      const manifest: Manifest = {
        version: 1, dome: this.o.dome, generation, contract,
        seq: changed ? (previous?.manifest.seq ?? 0) + 1 : previous!.manifest.seq,
        createdAt: previous?.manifest.createdAt ?? now, updatedAt: now,
        docs, chunkCount: finalChunks.length, fingerprint: fingerprintOf(files, virtual),
        classificationRules: CLASSIFICATION_RULES,
      };
      if (changed) {
        FlatVectorStore.write(genDir, manifest, finalChunks, finalVectors as Float32Array[], this.o.cipher);
        // SE-417: en una cúpula cifrada no se esperan lectores de seq antiguos en claro: fuera ya.
        if (this.o.cipher) gcGeneration(genDir, 0);
      } else if (mtimeOnly || recheck || manifest.fingerprint !== previous!.manifest.fingerprint) {
        FlatVectorStore.updateManifest(genDir, manifest, this.o.cipher);
      }

      const pointer = readActive(this.o.home, this.o.dome);
      if (!pointer.active) {
        writeActive(this.o.home, this.o.dome, { active: generation, previous: undefined, shadow: undefined });
        report.promoted = true;
      } else if (pointer.active !== generation) {
        writeActive(this.o.home, this.o.dome, { active: pointer.active, previous: pointer.previous, shadow: generation });
        report.shadow = true;
      }
      report.durationMs = Date.now() - started;
      logEvent(this.o.home, { event: 'sync', ...report });
      return report;
    } finally {
      releaseLock(lockDir);
    }
  }

  private tryLoad(genDir: string, contract: EmbeddingContract): FlatVectorStore | undefined {
    try {
      return FlatVectorStore.load(genDir, contract, this.o.cipher);
    } catch (e) {
      if (e instanceof RagError && e.code === 'CORRUPT_INDEX') logEvent(this.o.home, { event: 'corrupt', dome: this.o.dome, detail: e.message });
      return undefined;
    }
  }

  private carry(prev: FlatVectorStore, ids: string[], chunks: Chunk[], vectors: (Float32Array | undefined)[]): void {
    const byId = this.indexById(prev);
    for (const id of ids) {
      const i = byId.get(id);
      if (i === undefined) continue;
      chunks.push(prev.chunks[i]);
      vectors.push(new Float32Array(prev.vector(i)));
    }
  }

  private byIdCache = new WeakMap<FlatVectorStore, Map<string, number>>();
  private indexById(store: FlatVectorStore): Map<string, number> {
    let m = this.byIdCache.get(store);
    if (!m) {
      m = new Map(store.chunks.map((c, i) => [c.id, i]));
      this.byIdCache.set(store, m);
    }
    return m;
  }
}
