// SE-489 M5 — grafo de referencias en la recuperación. Parte de los candidatos de M0 y expande
// por saltos sobre wikilinks, `supersedes`/`superseded_by` e IDs de spec (SE-nnn), reutilizando
// `extractWikiLinks` de vault-graph: no se construye ningún grafo nuevo, el recorrido descubre las
// notas al abrirlas. Cada nota se abre con `ctx.openNote`, es decir, a través del guard y del
// presupuesto: un salto hacia algo no autorizado, inexistente o fuera de presupuesto no deja rastro.
//   - `visited` por (cúpula, ruta): los ciclos terminan; un nivel de profundidad gasta 1 `hops`.
//   - Con `asOf`, una revisión solo se sirve como vigente si su ventana la contiene; si no se puede
//     decidir (sin fechas), no se sirve (cierre seguro). Sin `asOf`, una revisión superseded no se
//     sirve salvo `includeStale`.
//   - Lo leído es dato: solo se extraen vínculos y fechas del frontmatter, nunca se obedece.
import * as path from 'node:path';
import YAML from 'yaml';
import { extractWikiLinks } from '../../knowledge/wikilink-validator.js';
import { RAG_DEFAULTS, RAG_LIMITS, type Confidentiality, type RagHit } from '../../rag/types.js';
import { ROUTE_CONTRACT_VERSION, registerRoute, type RetrievalRoute, type RouteContext, type RetrievalRequest, type RouteOutput } from '../route.js';

/** Notas descubiertas por vínculos como máximo, además de las semillas y del presupuesto de nodos. */
export const M5_MAX_DOCS = 24;
/** Vínculos que se siguen por nota, en orden determinista. */
export const M5_MAX_FANOUT = 6;
/** Búsquedas BM25 para resolver IDs de spec, por consulta (cada una es una pasada por el índice). */
export const M5_MAX_ID_LOOKUPS = 4;
/** Reserva de pared: la expansión para antes de agotar `maxLatencyMs`, o el runner descarta todo. */
export const M5_RESERVE_MS = 1500;
const MAX_TARGET_CHARS = 256;
/** Factor de score por nivel: los vecinos quedan por debajo de todas las semillas. */
const HOP_DECAY = 0.9;
const SPEC_ID = /\b(?:SE|SPEC)-\d{1,4}\b/g;

type EdgeKind = 'supersedes' | 'superseded_by' | 'link' | 'id';

export interface Meta {
  status?: string;
  supersedes: string[];
  supersededBy: string[];
  from?: number;
  to?: number;
  /** Solo `valid_until` (la frescura de M0): vencida, la nota no es vigente sin `asOf`. */
  validUntil?: number;
}

interface DocNode {
  dome: string;
  path: string;
  depth: number;
  score: number;
  seedHits: RagHit[];
  generation: string;
  meta: Meta;
  body: string;
  /** Aristas resueltas a notas abiertas: [tipo, ruta destino]. */
  edges: [EdgeKind, string][];
  viaSupersede: boolean;
  /** La nota no se pudo abrir: sin frontmatter no se puede situar en el tiempo. */
  unopened: boolean;
}

const key = (dome: string, p: string): string => `${dome}\u0000${p}`;

function asDate(v: unknown): number | undefined {
  if (v === undefined || v === null) return undefined;
  const s = v instanceof Date ? v.toISOString() : String(v).trim();
  const t = Date.parse(s);
  return Number.isNaN(t) ? undefined : t;
}

function asStrings(v: unknown): string[] {
  const list = Array.isArray(v) ? v : [v];
  return list.filter((x): x is string => typeof x === 'string').map(s => s.trim()).filter(Boolean);
}

/** Frontmatter YAML y cuerpo de una nota; un frontmatter inválido se trata como ausente. */
function splitNote(text: string): { fm: Record<string, unknown>; body: string } {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!m) return { fm: {}, body: text };
  try {
    const parsed = YAML.parse(m[1]);
    return { fm: parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {}, body: m[2] };
  } catch {
    return { fm: {}, body: m[2] };
  }
}

function metaOf(fm: Record<string, unknown>): Meta {
  const from = asDate(fm.effective_from ?? fm.valid_from);
  const validUntil = asDate(fm.valid_until);
  const to = asDate(fm.effective_to ?? fm.valid_until);
  const status = typeof fm.status === 'string' ? fm.status.toLowerCase() : undefined;
  return {
    ...(status ? { status } : {}), supersedes: asStrings(fm.supersedes), supersededBy: asStrings(fm.superseded_by),
    ...(from !== undefined ? { from } : {}), ...(to !== undefined ? { to } : {}), ...(validUntil !== undefined ? { validUntil } : {}),
  };
}

/** Quita los bloques de código (línea a línea: coste lineal aunque haya vallas sin cerrar). */
function stripFences(body: string): string {
  const out: string[] = [];
  let fence: string | undefined;
  for (const line of body.split('\n')) {
    const m = line.match(/^\s*(```|~~~)/);
    if (fence === undefined) { if (m) fence = m[1]; else out.push(line); } else if (m && m[1] === fence) fence = undefined;
  }
  return out.join('\n');
}

/** Rutas candidatas de una referencia, relativas a la cúpula; ninguna sale de ella. */
function pathsOf(target: string, fromPath: string): string[] {
  const t = target.split(/[#^]/)[0].trim();
  if (!t || t.length > MAX_TARGET_CHARS || /[\u0000-\u001F]/.test(t) || t.startsWith('/') || t.includes('\\') || /^[A-Za-z]:/.test(t)) return [];
  const withExt = /\.md$/i.test(t) ? t : `${t}.md`;
  const out: string[] = [];
  // Una referencia con `/` se resuelve primero desde la raíz de la cúpula; sin ella, junto a la nota.
  for (const base of t.includes('/') ? ['.', path.posix.dirname(fromPath)] : [path.posix.dirname(fromPath), '.']) {
    const p = path.posix.normalize(path.posix.join(base, withExt));
    if (p.startsWith('..') || p.split('/').includes('..') || out.includes(p)) continue;
    out.push(p);
  }
  return out;
}

const termsOf = (q: string): string[] => [...new Set(q.toLowerCase().split(/[^\p{L}\p{N}-]+/u).filter(t => t.length >= 3))];

const overlap = (terms: string[], text: string): number => {
  if (!terms.length) return 0;
  const low = text.toLowerCase();
  return terms.filter(t => low.includes(t)).length / terms.length;
};

export type Currency = 'current' | 'stale' | 'ended' | 'future' | 'unknown';

/**
 * ¿Se sirve esta revisión? `asOf` en ms. La ventana es [from, to). Sin `to`, el fin lo fija el
 * `from` del sucesor; si no se conoce, 'unknown' y no se sirve.
 */
export function currency(n: { meta: Meta }, successors: Meta[], asOf: number | undefined, includeStale: boolean): Currency {
  const m = n.meta;
  const excluded = (m.status !== undefined && RAG_DEFAULTS.excludeStatuses.includes(m.status)) || m.supersededBy.length > 0
    || (m.validUntil !== undefined && m.validUntil < Date.now());
  if (asOf === undefined) return excluded && !includeStale ? 'stale' : 'current';
  if (m.from !== undefined && asOf < m.from) return 'future';
  if (m.to !== undefined) return asOf >= m.to ? 'ended' : 'current';
  if (successors.length > 0 || m.supersededBy.length > 0) {
    const starts = successors.map(s => s.from).filter((x): x is number => x !== undefined);
    if (!starts.length || successors.length < m.supersededBy.length) return 'unknown';
    return asOf >= Math.min(...starts) ? 'ended' : 'current';
  }
  // Con `asOf`, una revisión retirada sin fin ni sucesor conocidos no se puede situar en el tiempo.
  if (excluded) return 'unknown';
  return 'current';
}

async function run(req: RetrievalRequest, ctx: RouteContext): Promise<RouteOutput> {
  const seeds = await ctx.candidates(req.query, { k: req.k, mode: req.mode });
  ctx.step('m5:seeds', req.mode, seeds.length);
  const asOf = req.asOf ? Date.parse(req.asOf) : undefined;
  // El runner ya valida `asOf`; aquí, cierre seguro por si la ruta se llama sin él.
  if (asOf !== undefined && Number.isNaN(asOf)) return { hits: [], abstain: true, warnings: ['INVALID_AS_OF'] };
  const includeStale = req.includeStale === true;
  const inScope = (p: string): boolean => !req.pathPrefix || p === req.pathPrefix || p.startsWith(req.pathPrefix.endsWith('/') ? req.pathPrefix : `${req.pathPrefix}/`);

  // La etiqueta de un vecino es el nivel de su cúpula (la más restrictiva si no se conoce).
  const LEVELS: readonly string[] = ['N1', 'N2', 'N3', 'N4', 'N4B'];
  const levels = new Map(req.domes.filter(d => LEVELS.includes(d.confidentiality)).map(d => [d.name, d.confidentiality as Confidentiality]));
  const nodes = new Map<string, DocNode>();
  const failed = new Set<string>();
  let seedCount = 0;
  let capHit = false;
  const order: DocNode[] = [];
  const warnings: string[] = [];

  /** Abre una nota por el contexto y la registra; undefined si no se puede abrir o ya estaba. */
  const discover = (dome: string, p: string, depth: number, score: number, generation: string, via: EdgeKind | 'seed'): DocNode | undefined => {
    const k = key(dome, p);
    // Las semillas de M0 nunca se pierden: ni el tope de notas ni un fallo al abrirlas las quita.
    if (nodes.has(k)) return undefined;
    if (via !== 'seed' && failed.has(k)) return undefined;
    if (via !== 'seed' && order.length - seedCount >= M5_MAX_DOCS) { capHit = true; return undefined; }
    const note = ctx.openNote({ dome, path: p });
    if (!note && via !== 'seed') { failed.add(k); return undefined; }
    const { fm, body } = splitNote(note ? note.text : '');
    const node: DocNode = {
      dome, path: p, depth, score, seedHits: [], generation, meta: metaOf(fm), body, edges: [],
      viaSupersede: via === 'supersedes' || via === 'superseded_by', unopened: !note,
    };
    nodes.set(k, node);
    order.push(node);
    return node;
  };

  // Semillas: un nodo por documento, con sus hits de M0.
  for (const h of seeds) {
    const existing = nodes.get(key(h.dome, h.path));
    if (existing) { existing.seedHits.push(h); continue; }
    const n = discover(h.dome, h.path, 0, h.score, h.generation, 'seed');
    if (n) n.seedHits.push(h);
  }

  /** Referencias de un nodo, en orden determinista. */
  const referencesOf = (n: DocNode): { kind: EdgeKind; target: string }[] => {
    const refs: { kind: EdgeKind; target: string }[] = [];
    for (const t of n.meta.supersedes) refs.push({ kind: 'supersedes', target: t });
    for (const t of n.meta.supersededBy) refs.push({ kind: 'superseded_by', target: t });
    const body = stripFences(n.body);
    for (const l of extractWikiLinks(body)) refs.push({ kind: 'link', target: l.target });
    const own = n.path.toUpperCase();
    for (const id of new Set(body.match(SPEC_ID) ?? [])) if (!own.includes(id)) refs.push({ kind: 'id', target: id });
    return refs;
  };

  /** Resuelve un ID de spec a una nota por BM25 (sin modelo): la que lo lleve en la ruta. */
  const idCache = new Map<string, string | undefined>();
  const resolveId = async (id: string): Promise<string | undefined> => {
    if (idCache.has(id)) return idCache.get(id);
    if (idCache.size >= M5_MAX_ID_LOOKUPS) return undefined;
    idCache.set(id, undefined);
    const hits = await ctx.candidates(id, { k: 3, mode: 'bm25' });
    const low = id.toLowerCase();
    const found = hits.find(h => h.path.toLowerCase().includes(low))?.path;
    idCache.set(id, found);
    return found;
  };

  // Un vecino nunca desplaza a una semilla de M0: su score parte del mínimo de las semillas.
  const floor = seeds.length ? Math.min(...seeds.map(h => h.score)) : 0;
  seedCount = order.length;
  let frontier = order.filter(n => n.depth === 0);
  for (let depth = 1; frontier.length > 0; depth++) {
    if (ctx.timeLeftMs() <= M5_RESERVE_MS || !ctx.consume('hops')) {
      // Solo es truncamiento si había algo que seguir.
      if (frontier.some(n => referencesOf(n).length > 0)) warnings.push('GRAPH_TRUNCATED');
      break;
    }
    const next: DocNode[] = [];
    for (const n of frontier) {
      let followed = 0;
      for (const ref of referencesOf(n)) {
        if (followed >= M5_MAX_FANOUT || ctx.timeLeftMs() <= M5_RESERVE_MS) break;
        const score = floor * HOP_DECAY ** depth;
        let target: DocNode | undefined;
        let resolved: string | undefined;
        const candidates = ref.kind === 'id' ? [await resolveId(ref.target)].filter((p): p is string => p !== undefined) : pathsOf(ref.target, n.path);
        for (const p of candidates) {
          if (!inScope(p)) continue;
          const known = nodes.get(key(n.dome, p));
          target = known ?? discover(n.dome, p, depth, score, n.generation, ref.kind);
          if (target) { resolved = p; break; }
        }
        if (resolved === undefined || !target) continue;
        n.edges.push([ref.kind, resolved]);
        followed++;
        if (target.depth === depth && !next.includes(target)) next.push(target);
      }
    }
    ctx.step('m5:hop', `${depth}`, next.length);
    frontier = next;
  }
  if (capHit && !warnings.includes('GRAPH_TRUNCATED')) warnings.push('GRAPH_TRUNCATED');

  // Sucesores: los que la nota declara (`superseded_by`) y los que la declaran a ella (`supersedes`).
  const successorsOf = (n: DocNode): Meta[] => {
    const out = new Map<string, Meta>();
    for (const [kind, p] of n.edges) {
      const t = nodes.get(key(n.dome, p));
      if (t && kind === 'superseded_by') out.set(key(t.dome, t.path), t.meta);
    }
    for (const o of order) {
      if (o.dome === n.dome && o.edges.some(([kind, p]) => kind === 'supersedes' && p === n.path)) out.set(key(o.dome, o.path), o.meta);
    }
    return [...out.values()];
  };

  const terms = termsOf(req.query);
  const hits: RagHit[] = [];
  const seen = new Set<string>();
  const push = (h: RagHit): void => { if (!seen.has(h.chunkId)) { seen.add(h.chunkId); hits.push(h); } };
  let excluded = 0;
  for (const n of order) {
    // Con `asOf`, una semilla que no se pudo abrir no se sirve: no se sabe si estaba vigente.
    if ((asOf !== undefined && n.unopened) || currency(n, successorsOf(n), asOf, includeStale) !== 'current') { excluded++; continue; }
    if (n.seedHits.length) { for (const h of n.seedHits) push(h); continue; }
    const chunks = ctx.documentChunks({ dome: n.dome, path: n.path });
    if (!chunks?.length) continue;
    const ranked = chunks.map(c => ({ c, o: overlap(terms, `${c.heading} ${c.text}`) }))
      .filter(x => x.o > 0 || n.viaSupersede)
      .sort((a, b) => b.o - a.o || a.c.ordinal - b.c.ordinal);
    for (const { c } of ranked.slice(0, RAG_LIMITS.maxChunksPerDoc)) {
      push({
        dome: n.dome, confidentiality: levels.get(n.dome) ?? 'N4B', path: n.path, chunkId: c.chunkId, heading: c.heading, text: c.text,
        score: n.score, signals: {}, generation: n.generation,
        freshness: { modified: '', decay: 1, ...(n.meta.status ? { status: n.meta.status } : {}) },
      });
    }
  }
  hits.sort((a, b) => b.score - a.score);
  ctx.step('m5:graph', `docs=${order.length}`, hits.length);
  if (excluded) ctx.step('m5:temporal', `excluidas=${excluded}`);
  const abstain = asOf !== undefined && seeds.length > 0 && hits.length === 0 && excluded > 0;
  return { hits, ...(abstain ? { abstain: true } : {}), ...(warnings.length ? { warnings } : {}) };
}

export const M5_GRAPH: RetrievalRoute = {
  id: 'M5',
  description: 'Grafo de referencias (wikilinks, supersedes, IDs de spec) con visited, profundidad y guard por salto',
  contractVersion: ROUTE_CONTRACT_VERSION,
  supportsAsOf: true,
  requiresDeclaredBudget: false,
  run,
};

registerRoute(M5_GRAPH);
