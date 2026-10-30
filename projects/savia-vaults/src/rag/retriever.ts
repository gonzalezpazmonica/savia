import MiniSearch from 'minisearch';
import { decayFactor, excludedReason } from './policy.js';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { writeAtomic, type FlatVectorStore } from './store.js';
import { RAG_LIMITS, type RagHit, type RagMode, type ResolvedRagConfig } from './types.js';

/** SE-410 — Recuperación híbrida por cúpula: BM25 sobre chunks + denso, RRF, frescura. */

/** Reciprocal Rank Fusion: score(id) = Σ 1/(k + rank), rank desde 1. */
export function rrf(lists: string[][], k: number = RAG_LIMITS.rrfK): Map<string, number> {
  const scores = new Map<string, number>();
  for (const list of lists) {
    list.forEach((id, i) => scores.set(id, (scores.get(id) ?? 0) + 1 / (k + i + 1)));
  }
  return scores;
}

interface Bm25Doc { id: number; heading: string; text: string }

// Stopwords es/en: sin ellas, términos como "de" o "que" dominan el OR de BM25
// y el prefijo los expande a medio vocabulario. SE-481 R5: las negaciones (no, not, ni,
// sin, nada) NO son stopwords: invierten el sentido y deben puntuar.
const STOPWORDS = new Set((
  'a al algo ante antes como con contra cual cuando de del desde donde durante e el ella ellas ellos en entre era es esa ese eso esta este esto estos fue ha han hasta hay la las le les lo los mas me mi mientras muy nos o os otra otro para pero poco por porque que quien se sea segun ser si sobre son su sus tambien te tiene todo tras tu un una uno unos y ya yo ' +
  'a an and are as at be but by for from has have if in into is it its of on or so that the their then there these this to was were will with'
).split(' '));

/** Normaliza un término: minúsculas, sin acentos; null si es stopword. */
export function processTerm(term: string): string | null {
  const t = term.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  return STOPWORDS.has(t) ? null : t;
}

/** Exportada para tests (SE-481 R5). */
export const BM25_STOPWORDS: ReadonlySet<string> = STOPWORDS;

// Separadores de MiniSearch (espacios y puntuación Unicode).
const SPLIT = /[\n\r\p{Z}\p{P}]+/u;
// Identificador compuesto: letras/dígitos unidos por - _ . / (CT-2026-047, E-1047, SE-481).
const COMPOUND = /^[\p{L}\p{N}]+(?:[-_./][\p{L}\p{N}]+)+$/u;

/**
 * SE-481 R5: tokeniza como MiniSearch y además conserva cada identificador compuesto con
 * dígitos como término completo; así `E-1047` casa exacto y sus partes siguen indexadas.
 */
export function tokenize(text: string): string[] {
  const out = text.split(SPLIT).filter(Boolean);
  for (const raw of text.split(/\s+/)) {
    const w = raw.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, '');
    if (COMPOUND.test(w) && /\p{N}/u.test(w)) out.push(w);
  }
  return out;
}

const bm25Cache = new WeakMap<FlatVectorStore, MiniSearch<Bm25Doc>>();

/** Subir si cambian tokenización u opciones: invalida los índices BM25 persistidos. */
const BM25_VERSION = 'v2'; // SE-481: negaciones indexadas e identificadores compuestos

const BM25_OPTIONS = {
  fields: ['heading', 'text'],
  idField: 'id',
  processTerm,
  tokenize,
  searchOptions: {
    tokenize,
    boost: { heading: 1.5 },
    prefix: (term: string) => term.length >= 4,
    fuzzy: (term: string) => (term.length >= 5 ? 0.1 : 0),
  },
};

/**
 * Índice BM25 por store. SE-411 G5: se persiste por `seq` en el directorio de la
 * generación para que un proceso nuevo (CLI) no retokenice todos los chunks.
 */
function bm25Index(store: FlatVectorStore): MiniSearch<Bm25Doc> {
  let ms = bm25Cache.get(store);
  if (ms) return ms;
  const file = path.join(store.dir, `bm25-${store.manifest.seq}-${BM25_VERSION}.json`);
  // SE-417: en cúpulas cifradas el BM25 persistido también va sellado (contiene el vocabulario).
  const part = `bm25-${store.manifest.seq}`;
  try {
    const raw = fs.readFileSync(file);
    ms = MiniSearch.loadJSON<Bm25Doc>((store.cipher ? store.cipher.open(raw, part) : raw).toString('utf-8'), BM25_OPTIONS);
  } catch {
    ms = new MiniSearch<Bm25Doc>(BM25_OPTIONS);
    ms.addAll(store.chunks.map((c, i) => ({ id: i, heading: c.heading, text: c.text })));
    const json = Buffer.from(JSON.stringify(ms));
    try { writeAtomic(file, store.cipher ? store.cipher.seal(json, part) : json); } catch { /* caché opcional: sin permisos de escritura se reconstruye */ }
  }
  bm25Cache.set(store, ms);
  return ms;
}

/** Carga (o construye) el índice BM25 de un store por adelantado (SE-411 G5). */
export function warmBm25(store: FlatVectorStore): void {
  bm25Index(store);
}

export interface StoreSearchInput {
  store: FlatVectorStore;
  query: string;
  queryVec?: Float32Array;
  mode: RagMode;
  k: number;
  cfg: Pick<ResolvedRagConfig, 'excludeStatuses' | 'halfLifeDays'>;
  pathPrefix?: string;
  includeStale?: boolean;
  now?: Date;
}

/** Hits de una cúpula sin dome/confidencialidad (los añade el servicio). */
export type StoreHit = Omit<RagHit, 'dome' | 'confidentiality'>;

export function searchStore(input: StoreSearchInput): StoreHit[] {
  const { store, cfg } = input;
  const now = input.now ?? new Date();
  const depth = RAG_LIMITS.candidateDepth;
  const accept = (i: number) => {
    const c = store.chunks[i];
    if (input.pathPrefix && !c.path.startsWith(input.pathPrefix)) return false;
    return input.includeStale || !excludedReason(c.meta, cfg, now);
  };

  const lists: string[][] = [];
  const dense = new Map<number, { rank: number; score: number }>();
  const lexical = new Map<number, { rank: number; score: number }>();

  if (input.mode !== 'bm25' && input.queryVec) {
    store.topK(input.queryVec, depth, accept).forEach((h, r) => dense.set(h.index, { rank: r + 1, score: h.score }));
    lists.push([...dense.keys()].map(String));
  }
  if (input.mode !== 'dense') {
    bm25Index(store).search(input.query)
      .filter(r => accept(r.id as number))
      .slice(0, depth)
      .forEach((r, rank) => lexical.set(r.id as number, { rank: rank + 1, score: r.score }));
    lists.push([...lexical.keys()].map(String));
  }

  const fused = [...rrf(lists).entries()].map(([id, score]) => {
    const i = Number(id);
    const c = store.chunks[i];
    const decay = decayFactor(c.meta.modified, cfg.halfLifeDays, now);
    return { i, score: score * decay, decay };
  }).sort((a, b) => b.score - a.score);

  const perDoc = new Map<string, number>();
  const out: StoreHit[] = [];
  for (const f of fused) {
    const c = store.chunks[f.i];
    const n = perDoc.get(c.path) ?? 0;
    if (n >= RAG_LIMITS.maxChunksPerDoc) continue;
    perDoc.set(c.path, n + 1);
    const d = dense.get(f.i);
    const l = lexical.get(f.i);
    // SE-411 G1: coseno de todo hit con vector de consulta, para fusionar entre cúpulas.
    let cos = d?.score;
    if (cos === undefined && input.queryVec) {
      const v = store.vector(f.i);
      cos = 0;
      for (let j = 0; j < v.length; j++) cos += v[j] * input.queryVec[j];
    }
    out.push({
      path: c.path, chunkId: c.id, heading: c.heading, text: c.text, score: f.score,
      signals: { denseRank: d?.rank, dense: cos, bm25Rank: l?.rank, bm25: l?.score },
      freshness: { modified: c.meta.modified, status: c.meta.status, supersededBy: c.meta.supersededBy, decay: f.decay },
      generation: store.manifest.generation,
      ...(c.source ? { source: c.source } : {}),
    });
    if (out.length >= input.k) break;
  }
  return out;
}

/** Fusión entre cúpulas o consultas por rango (los scores no son comparables entre índices). */
export function fuseAcross(lists: RagHit[][], k: number): RagHit[] {
  const byKey = new Map<string, RagHit>();
  const keyed = lists.map(list => list.map((h) => {
    const key = `${h.dome}\u0000${h.chunkId}`;
    if (!byKey.has(key)) byKey.set(key, h);
    return key;
  }));
  // Desempate determinista (SE-411 G1): nunca por el orden de entrada.
  return [...rrf(keyed).entries()]
    .sort((a, b) => b[1] - a[1] || (byKey.get(b[0])!.signals.dense ?? -2) - (byKey.get(a[0])!.signals.dense ?? -2) || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .slice(0, k)
    .map(([key, score]) => ({ ...byKey.get(key)!, score }));
}

/**
 * SE-411 G1: fusión entre cúpulas con el mismo contrato por coseno global
 * (vectores del mismo espacio, comparables). Invariante al orden de entrada.
 */
export function fuseByCosine(lists: RagHit[][], k: number): RagHit[] {
  const key = (h: RagHit) => `${h.dome}\u0000${h.chunkId}`;
  const seen = new Map<string, RagHit>();
  for (const list of lists) for (const h of list) if (!seen.has(key(h))) seen.set(key(h), h);
  return [...seen.values()]
    .sort((a, b) => (b.signals.dense ?? -2) - (a.signals.dense ?? -2)
      || (a.signals.bm25Rank ?? Infinity) - (b.signals.bm25Rank ?? Infinity)
      || (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0))
    .slice(0, k)
    .map(h => ({ ...h, score: h.signals.dense ?? 0 }));
}

/** Recorta el texto de los hits para respetar maxChars; nunca omite hits. */
export function applyCharBudget(hits: RagHit[], maxChars: number): RagHit[] {
  const total = hits.reduce((s, h) => s + h.text.length, 0);
  if (total <= maxChars || hits.length === 0) return hits;
  const per = Math.max(200, Math.floor(maxChars / hits.length));
  return hits.map(h => (h.text.length > per ? { ...h, text: `${h.text.slice(0, per - 1)}…` } : h));
}
