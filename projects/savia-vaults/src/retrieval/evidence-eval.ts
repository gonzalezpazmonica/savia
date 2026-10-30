// SE-489 R2 — evaluación de rutas con verdad a nivel de evidencia. Amplía el runner de
// SE-410 (`rag eval`) y reutiliza las métricas de SE-331 (`search/eval.ts`): Recall@k, MRR,
// nDCG@10, EvidenceRecall, exact-identifier-hit, lecturas no autorizadas, revisiones prohibidas,
// abstención correcta, latencia p50/p95 y RSS pico; IC 95 % por bootstrap (pareado por pregunta).
// Formato del banco: docs/retrieval-routes.md § Banco de evidencia.
import * as fs from 'node:fs';
import * as path from 'node:path';
import { computeRecallAtK } from '../search/eval.js';
import { containsIdentifier, queryIdentifiers } from '../search/identifiers.js';
import { isMarkdown } from '../storage/note-level.js';
import { FILES_PATH_PREFIX } from '../files/rag-source.js';
import { RagError, type RagHit, type RagMode } from '../rag/types.js';
import type { EvalQueryInput, RagService } from '../rag/service.js';
import { RetrievalGuard } from './guard.js';
import { runRoute } from './runner.js';
import type { Evidence } from './route.js';

export const CATEGORIES = ['A', 'B', 'C', 'D', 'E', 'F'] as const;
export type Category = typeof CATEGORIES[number];

export interface EvidenceRef {
  document: string;
  dome?: string;
  revision?: string;
  /** `#<ordinal>`, localizador de Files (`page:3`) o el último tramo del encabezado («Anexo II»). */
  locator?: string;
}

export interface EvidenceCase {
  id: string;
  category: Category;
  split: 'dev' | 'test';
  query: string;
  /** Cúpulas pedidas (def. las de la CLI). */
  domes?: string[];
  /** Cúpulas que el plano de control deniega en este caso (categoría F). */
  denied_domes?: string[];
  as_of?: string;
  required_evidence: EvidenceRef[];
  forbidden_evidence: EvidenceRef[];
  must_abstain: boolean;
  max_unauthorized_reads: 0;
  note?: string;
  source?: string;
}

const KNOWN = new Set(['id', 'category', 'split', 'query', 'domes', 'denied_domes', 'as_of', 'required_evidence', 'forbidden_evidence', 'must_abstain', 'max_unauthorized_reads', 'note', 'source']);
const REF_KEYS = new Set(['document', 'dome', 'revision', 'locator']);

const strList = (v: unknown): boolean => Array.isArray(v) && v.every(x => typeof x === 'string' && x.length > 0);

function refErrors(v: unknown, field: string): string[] {
  if (!Array.isArray(v)) return [`${field}: lista`];
  const errs: string[] = [];
  v.forEach((r, i) => {
    if (!r || typeof r !== 'object' || Array.isArray(r)) { errs.push(`${field}[${i}]: objeto`); return; }
    const o = r as Record<string, unknown>;
    if (typeof o.document !== 'string' || !o.document) errs.push(`${field}[${i}].document: texto`);
    for (const k of ['dome', 'revision', 'locator']) if (o[k] !== undefined && (typeof o[k] !== 'string' || !o[k])) errs.push(`${field}[${i}].${k}: texto`);
    for (const k of Object.keys(o)) if (!REF_KEYS.has(k)) errs.push(`${field}[${i}]: campo desconocido ${k}`);
  });
  return errs;
}

/** Errores de esquema de un caso ([] = válido). */
export function validateCase(c: unknown): string[] {
  if (!c || typeof c !== 'object' || Array.isArray(c)) return ['caso: objeto'];
  const o = c as Record<string, unknown>;
  const errs: string[] = [];
  if (typeof o.id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(o.id)) errs.push('id: [A-Za-z0-9._-], 1-64');
  if (!CATEGORIES.includes(o.category as Category)) errs.push('category: A..F');
  if (o.split !== 'dev' && o.split !== 'test') errs.push('split: dev|test');
  if (typeof o.query !== 'string' || !o.query.trim() || o.query.length > 1000) errs.push('query: 1-1000 caracteres');
  if (o.domes !== undefined && !strList(o.domes)) errs.push('domes: lista de nombres');
  if (o.denied_domes !== undefined && !strList(o.denied_domes)) errs.push('denied_domes: lista de nombres');
  if (o.as_of !== undefined && (typeof o.as_of !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(o.as_of) || Number.isNaN(Date.parse(o.as_of)))) errs.push('as_of: fecha ISO');
  errs.push(...refErrors(o.required_evidence, 'required_evidence'), ...refErrors(o.forbidden_evidence, 'forbidden_evidence'));
  if (typeof o.must_abstain !== 'boolean') errs.push('must_abstain: booleano');
  else if (!o.must_abstain && Array.isArray(o.required_evidence) && o.required_evidence.length === 0) errs.push('required_evidence: al menos una si must_abstain es false');
  if (o.max_unauthorized_reads !== 0) errs.push('max_unauthorized_reads: 0');
  for (const k of Object.keys(o)) if (!KNOWN.has(k)) errs.push(`campo desconocido: ${k}`);
  return errs;
}

/** Lee un banco: `*.json` (lista o `{cases}`) y `*.jsonl` del directorio, sin recursión. */
export function loadBench(dir: string, opts: { split?: 'dev' | 'test' } = {}): EvidenceCase[] {
  let files: string[];
  try { files = fs.readdirSync(dir).filter(f => /\.(json|jsonl)$/.test(f)).sort(); } catch { throw new RagError('INVALID_INPUT', `banco no encontrado: ${dir}`); }
  const cases: EvidenceCase[] = [];
  const ids = new Set<string>();
  const errors: string[] = [];
  for (const f of files) {
    const raw = fs.readFileSync(path.join(dir, f), 'utf-8');
    let items: unknown[];
    try {
      if (f.endsWith('.jsonl')) items = raw.split('\n').filter(l => l.trim()).map(l => JSON.parse(l));
      else { const j = JSON.parse(raw); items = Array.isArray(j) ? j : Array.isArray(j?.cases) ? j.cases : []; }
    } catch (e) { throw new RagError('INVALID_INPUT', `${f}: JSON no válido (${e instanceof Error ? e.message : e})`); }
    items.forEach((c, i) => {
      const errs = validateCase(c);
      if (errs.length) { errors.push(`${f}[${i}]: ${errs.join('; ')}`); return; }
      const ec = c as EvidenceCase;
      if (ids.has(ec.id)) { errors.push(`${f}[${i}]: id repetido ${ec.id}`); return; }
      ids.add(ec.id);
      cases.push(ec);
    });
  }
  if (errors.length) throw new RagError('INVALID_INPUT', `banco no válido: ${errors.slice(0, 5).join(' | ')}${errors.length > 5 ? ` (+${errors.length - 5})` : ''}`);
  if (!cases.length) throw new RagError('INVALID_INPUT', `banco vacío: ${dir}`);
  return opts.split ? cases.filter(c => c.split === opts.split) : cases;
}

const LEGACY_CATEGORY: Record<string, Category> = { lexical: 'A', paraphrase: 'B', mixed: 'B' };

/** El banco de regresión de SE-410 (36 consultas) como casos de evidencia a nivel de documento. */
export function legacyToCases(queries: EvalQueryInput[]): EvidenceCase[] {
  return queries.map((q, i) => ({
    id: `L-${String(i + 1).padStart(3, '0')}`, category: LEGACY_CATEGORY[q.kind ?? ''] ?? 'B', split: 'dev', query: q.query,
    required_evidence: q.relevantPaths.map(document => ({ document })), forbidden_evidence: [], must_abstain: false, max_unauthorized_reads: 0,
  }));
}

function locatorMatches(want: string, got: string): boolean {
  if (got === want || got.startsWith(`${want} `) || got.startsWith(`${want}..`)) return true;
  // Encabezado: último tramo de la ruta «Título › h2 › h3».
  const heading = got.replace(/^#\d+ ?/, '');
  return heading === want || heading.endsWith(` › ${want}`);
}

function refMatches(r: EvidenceRef, e: Evidence): boolean {
  return e.document === r.document && (!r.dome || r.dome === e.dome) && (!r.revision || r.revision === e.revision)
    && (!r.locator || locatorMatches(r.locator, e.locator));
}

export interface CaseMetrics {
  recallAt5?: number; recallAt10?: number; recallAt20?: number; mrr?: number; ndcgAt10?: number;
  evidenceRecall?: number;
  exactIdentifierHit?: number;
  unauthorizedReads: number;
  forbiddenUsed: number;
  correctAbstention: number;
  violation: boolean;
}

/** Métricas de un caso. `unauthorized` = evidencias que el recontrol del guard no admite. */
export function caseMetrics(c: EvidenceCase, r: { hits: RagHit[]; evidence: Evidence[]; abstain?: boolean }, unauthorized: number): CaseMetrics {
  const abstained = Boolean(r.abstain) || r.hits.length === 0;
  const forbiddenUsed = r.evidence.filter(e => c.forbidden_evidence.some(f => refMatches(f, e))).length;
  const m: CaseMetrics = {
    unauthorizedReads: unauthorized, forbiddenUsed,
    correctAbstention: abstained === c.must_abstain ? 1 : 0,
    violation: unauthorized > c.max_unauthorized_reads,
  };
  if (c.required_evidence.length) {
    const relevant = [...new Set(c.required_evidence.map(x => x.document))];
    const evByChunk = new Map(r.evidence.map(e => [`${e.dome}\u0000${e.chunkId}`, e]));
    const ranked = [...new Set(r.hits.map(h => evByChunk.get(`${h.dome}\u0000${h.chunkId}`)?.document ?? h.path))];
    m.recallAt5 = computeRecallAtK(ranked, relevant, 5);
    m.recallAt10 = computeRecallAtK(ranked, relevant, 10);
    m.recallAt20 = computeRecallAtK(ranked, relevant, 20);
    const first = ranked.findIndex(p => relevant.includes(p));
    m.mrr = first >= 0 ? 1 / (first + 1) : 0;
    const dcg = ranked.slice(0, 10).reduce((s, p, i) => s + (relevant.includes(p) ? 1 / Math.log2(i + 2) : 0), 0);
    const idcg = relevant.slice(0, 10).reduce((s, _p, i) => s + 1 / Math.log2(i + 2), 0);
    m.ndcgAt10 = idcg ? dcg / idcg : 0;
    m.evidenceRecall = c.required_evidence.filter(req => r.evidence.some(e => refMatches(req, e))).length / c.required_evidence.length;
    const ids = queryIdentifiers(c.query);
    if (ids.length) {
      const top = r.hits[0];
      const topDoc = top ? evByChunk.get(`${top.dome}\u0000${top.chunkId}`)?.document ?? top.path : undefined;
      m.exactIdentifierHit = top && ids.every(id => containsIdentifier(top.text, id)) && relevant.includes(topDoc!) ? 1 : 0;
    }
  }
  return m;
}

/** PRNG determinista (mulberry32). */
function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const quantile = (sorted: number[], q: number): number => sorted[Math.min(sorted.length - 1, Math.max(0, Math.floor(q * sorted.length)))];

export interface Interval { n: number; mean: number; lo: number; hi: number }
export interface BootstrapOptions { iterations: number; seed: number }

/** Media con IC 95 % por bootstrap percentil (remuestreo de preguntas). */
export function bootstrapMean(xs: number[], o: BootstrapOptions): Interval {
  if (!Number.isSafeInteger(o.iterations) || o.iterations < 1) throw new RagError('INVALID_INPUT', 'iterations: entero ≥ 1');
  if (!xs.length) return { n: 0, mean: 0, lo: 0, hi: 0 };
  const mean = xs.reduce((s, x) => s + x, 0) / xs.length;
  const rand = rng(o.seed);
  const means: number[] = [];
  for (let b = 0; b < o.iterations; b++) {
    let s = 0;
    for (let i = 0; i < xs.length; i++) s += xs[Math.floor(rand() * xs.length)];
    means.push(s / xs.length);
  }
  means.sort((a, b) => a - b);
  return { n: xs.length, mean, lo: quantile(means, 0.025), hi: quantile(means, 0.975) };
}

/** Diferencia media a − b, pareada por pregunta (solo ids presentes en ambos), con IC 95 %. */
export function pairedBootstrap(a: Map<string, number>, b: Map<string, number>, o: BootstrapOptions): { n: number; diff: number; lo: number; hi: number } {
  const diffs = [...a.keys()].filter(k => b.has(k)).sort().map(k => a.get(k)! - b.get(k)!);
  const r = bootstrapMean(diffs, o);
  return { n: r.n, diff: r.mean, lo: r.lo, hi: r.hi };
}

export const METRICS = ['recallAt5', 'recallAt10', 'recallAt20', 'mrr', 'ndcgAt10', 'evidenceRecall', 'exactIdentifierHit', 'unauthorizedReads', 'forbiddenUsed', 'correctAbstention'] as const;
export type MetricName = typeof METRICS[number];

export interface CaseRecord {
  id: string; category: Category; latencyMs: number;
  metrics: CaseMetrics;
  /** Nodos que el guard denegó durante la ruta (intentos, no lecturas): `trace.denied`. */
  deniedAttempts: number;
  consumed: { modelCalls: number; inputTokens: number; nodes: number; hops: number };
  error?: string;
}

export interface RouteReport {
  route: string;
  mode: RagMode;
  n: number;
  overall: Record<MetricName, Interval>;
  byCategory: Partial<Record<Category, Record<MetricName, Interval>>>;
  latency: { p50Ms: number; p95Ms: number };
  cost: { modelCalls: number; inputTokens: number };
  /** Pico de memoria residente del proceso (MB) durante la evaluación. */
  rssPeakMb: number;
  /**
   * Casos con más lecturas no autorizadas que su máximo (objetivo: 0). Con el guard final del
   * runner debe salir 0 salvo cambio de estado entre la ruta y el recontrol: no sustituye a la
   * batería de seguridad (AC-2), que es la que prueba las fugas de una ruta.
   */
  violations: number;
  /** Suma de `trace.denied`: cuántas veces la ruta intentó abrir algo que el guard denegó. */
  deniedAttempts: number;
  errors: number;
  cases: CaseRecord[];
}

export interface EvaluateOptions {
  route: string;
  mode?: RagMode;
  k?: number;
  seed?: number;
  budget?: unknown;
  iterations?: number;
  /** Cúpulas por defecto si el caso no las declara. */
  domes?: string[];
  /** Fija las cúpulas que el plano de control deniega antes de cada caso. */
  deny?: (names: string[]) => void;
}

function percentile(values: number[], p: number): number {
  if (!values.length) return 0;
  const s = [...values].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)];
}

function summarize(records: CaseRecord[], o: BootstrapOptions): Record<MetricName, Interval> {
  const out = {} as Record<MetricName, Interval>;
  for (const m of METRICS) {
    const xs = records.map(r => r.metrics[m]).filter((x): x is number => typeof x === 'number');
    out[m] = bootstrapMean(xs, o);
  }
  return out;
}

/** Recontrol independiente: evidencias que un guard nuevo, con el estado actual, no admite. */
async function unauthorizedCount(rag: RagService, domes: string[] | undefined, evidence: Evidence[]): Promise<number> {
  const { allowed, principals } = await rag.authorizeTargets(domes, 'rag_eval');
  const guard = new RetrievalGuard(allowed.map(d => ({ name: d.name, path: d.path, confidentiality: d.confidentiality, principal: principals.get(d.name), files: rag.filesStoreOf(d) })));
  return evidence.filter(e => {
    const isFile = e.document.startsWith(FILES_PATH_PREFIX) && !isMarkdown(e.document);
    return !guard.admit({ dome: e.dome, path: e.document, ...(isFile ? { documentId: e.document.slice(FILES_PATH_PREFIX.length) } : {}) }).ok;
  }).length;
}

/** Ejecuta una ruta sobre el banco. Un caso que falla cuenta como error y nunca como abstención correcta. */
export async function evaluateRoute(rag: RagService, cases: EvidenceCase[], o: EvaluateOptions): Promise<RouteReport> {
  const boot = { iterations: o.iterations ?? 2000, seed: o.seed ?? 0 };
  const mode = o.mode ?? 'hybrid';
  const records: CaseRecord[] = [];
  let rssPeak = process.memoryUsage().rss;
  for (const c of cases) {
    o.deny?.(c.denied_domes ?? []);
    const domes = c.domes ?? o.domes;
    const t = Date.now();
    try {
      const { result } = await runRoute(rag, {
        route: o.route, query: c.query, domes, k: o.k ?? 20, mode, seed: o.seed ?? 0, tool: 'rag_eval',
        ...(c.as_of ? { asOf: c.as_of } : {}), ...(o.budget !== undefined ? { budget: o.budget } : {}),
      });
      const latencyMs = Date.now() - t;
      const unauthorized = await unauthorizedCount(rag, domes, result.evidence);
      records.push({
        id: c.id, category: c.category, latencyMs, metrics: caseMetrics(c, result, unauthorized), deniedAttempts: result.trace.denied,
        consumed: { modelCalls: result.consumed.modelCalls, inputTokens: result.consumed.inputTokens, nodes: result.consumed.nodes, hops: result.consumed.hops },
      });
    } catch (e) {
      // Una ruta desconocida o un presupuesto inválido son errores de configuración: se propagan.
      if (e instanceof Error && /^(UNKNOWN_ROUTE|INVALID_BUDGET|BUDGET_REQUIRED):/.test(e.message)) throw e;
      records.push({
        id: c.id, category: c.category, latencyMs: Date.now() - t, deniedAttempts: 0, error: e instanceof Error ? e.message : String(e),
        metrics: { ...caseMetrics(c, { hits: [], evidence: [] }, 0), correctAbstention: 0 }, consumed: { modelCalls: 0, inputTokens: 0, nodes: 0, hops: 0 },
      });
    }
    rssPeak = Math.max(rssPeak, process.memoryUsage().rss);
  }
  o.deny?.([]);
  const byCategory: RouteReport['byCategory'] = {};
  for (const cat of CATEGORIES) {
    const rs = records.filter(r => r.category === cat);
    if (rs.length) byCategory[cat] = summarize(rs, boot);
  }
  const lat = records.map(r => r.latencyMs);
  return {
    route: o.route, mode, n: records.length,
    overall: summarize(records, boot), byCategory,
    latency: { p50Ms: percentile(lat, 50), p95Ms: percentile(lat, 95) },
    cost: { modelCalls: records.reduce((s, r) => s + r.consumed.modelCalls, 0), inputTokens: records.reduce((s, r) => s + r.consumed.inputTokens, 0) },
    rssPeakMb: Math.round((rssPeak / 1048576) * 10) / 10,
    violations: records.filter(r => r.metrics.violation).length,
    deniedAttempts: records.reduce((s, r) => s + r.deniedAttempts, 0),
    errors: records.filter(r => r.error).length,
    cases: records,
  };
}

export interface RouteComparison {
  route: string;
  baseline: string;
  overall: Partial<Record<MetricName, { n: number; diff: number; lo: number; hi: number }>>;
  byCategory: Partial<Record<Category, Partial<Record<MetricName, { n: number; diff: number; lo: number; hi: number }>>>>;
}

/** Ruta frente a línea base, pareado por pregunta, global y por categoría. */
export function compareReports(a: RouteReport, b: RouteReport, o: BootstrapOptions): RouteComparison {
  const pick = (r: RouteReport, m: MetricName, cat?: Category) =>
    new Map(r.cases.filter(c => !cat || c.category === cat).flatMap(c => (typeof c.metrics[m] === 'number' ? [[c.id, c.metrics[m] as number] as const] : [])));
  const block = (cat?: Category) => Object.fromEntries(METRICS.map(m => [m, pairedBootstrap(pick(a, m, cat), pick(b, m, cat), o)]).filter(([, v]) => (v as { n: number }).n > 0));
  const byCategory: RouteComparison['byCategory'] = {};
  for (const cat of CATEGORIES) if (a.byCategory[cat] && b.byCategory[cat]) byCategory[cat] = block(cat);
  return { route: a.route, baseline: b.route, overall: block(), byCategory };
}
