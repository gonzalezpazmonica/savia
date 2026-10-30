// SE-489 — runner de rutas: el único sitio que ejecuta una RetrievalRoute.
// 1. Plano de control: cúpulas objetivo y `authorize` por cúpula (el mismo de vault_rag).
// 2. Guard con las autorizadas; el contexto de la ruta solo lee a través de él.
// 3. Presupuesto: por defecto o declarado; AC-7, la ruta que lo exige no corre sin él.
// 4. Guard final: cada hit vuelve a pasar por el guard y lleva su evidencia; lo demás se descarta.
import { RagError, RAG_LIMITS, type DomeOutcome, type RagHit, type RagMode, type RagResponse } from '../rag/types.js';
import { applyCharBudget, fuseAcross } from '../rag/retriever.js';
import { isMarkdown } from '../storage/note-level.js';
import { FILES_PATH_PREFIX } from '../files/rag-source.js';
import type { RagService } from '../rag/service.js';
import { RetrievalGuard } from './guard.js';
import {
  AS_OF_UNSUPPORTED, BUDGET_EXHAUSTED, BudgetMeter, RouteError, estimateTokens, getRoute, resolveBudget,
  type Evidence, type RetrievalRequest, type RetrievalResult, type RouteContext, type RouteOutput, type TraceStep,
} from './route.js';
import './routes/index.js';

export interface RouteRunInput {
  route: string;
  query: string;
  /** Cúpulas pedidas; el plano de control decide cuáles quedan autorizadas. */
  domes?: string[] | '*';
  asOf?: string;
  /** Presupuesto declarado (parcial); ausente ⇒ el de por defecto. */
  budget?: unknown;
  seed?: unknown;
  k?: number;
  mode?: RagMode;
  pathPrefix?: string;
  includeStale?: boolean;
  maxChars?: number;
  /** Motivo de la elección de ruta para la traza (def. `explicit`). */
  reason?: string;
  /** Herramienta que se registra en la autorización (def. `vault_rag`). */
  tool?: string;
}

export interface RouteRunOutput {
  result: RetrievalResult;
  domes: DomeOutcome[];
  /** Fusión entre cúpulas de la última llamada a candidatos (como en RagResponse). */
  fusion?: 'cosine' | 'rank';
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}(T[\d:.]+(Z|[+-]\d{2}:\d{2})?)?$/;

function validAsOf(v: unknown): string | undefined {
  if (v === undefined) return undefined;
  if (typeof v !== 'string' || !ISO_DATE.test(v) || Number.isNaN(Date.parse(v))) {
    throw new RagError('INVALID_INPUT', 'asOf: fecha ISO (YYYY-MM-DD o fecha-hora)');
  }
  // Date.parse acepta 2026-02-30; se exige que la fecha sea la misma al volver a formatearla.
  if (new Date(Date.parse(v.slice(0, 10))).toISOString().slice(0, 10) !== v.slice(0, 10)) {
    throw new RagError('INVALID_INPUT', 'asOf: fecha inexistente');
  }
  return v;
}

function validSeed(v: unknown): number {
  if (v === undefined) return 0;
  if (typeof v !== 'number' || !Number.isSafeInteger(v)) throw new RagError('INVALID_INPUT', 'seed: entero');
  return v;
}

function validQuery(q: unknown): string {
  if (typeof q !== 'string' || !q.trim() || q.length > RAG_LIMITS.maxQueryChars) {
    throw new RagError('INVALID_INPUT', `consulta: 1-${RAG_LIMITS.maxQueryChars} caracteres`);
  }
  return q;
}

const WARNING_CODE = /^[A-Z][A-Z0-9_]{2,63}$/;

/**
 * Procedencia de un hit admitido. Si `chunkId` es un chunk del índice, el texto (sin el `…` del
 * recorte por presupuesto) debe estar en ESE chunk y el encabezado ser el suyo; estado,
 * `supersededBy` y `source` se toman de él, nunca de la ruta. Si no lo es (p. ej. una sección
 * sintética de M3), solo vale para notas: el texto y el último tramo del encabezado deben estar en
 * su contenido actual. Un texto vacío nunca acredita procedencia.
 */
function provenance(
  h: RagHit, ev: Evidence,
  chunks: () => ReturnType<RagService['activeDocumentChunks']>, noteText: () => string | undefined,
): RagHit | undefined {
  if (typeof h.text !== 'string' || typeof h.heading !== 'string' || typeof h.chunkId !== 'string') return undefined;
  if (!h.chunkId.startsWith(`${ev.document}#`)) return undefined;
  const core = h.text.endsWith('…') ? h.text.slice(0, -1) : h.text;
  if (!core.trim()) return undefined;
  const chunk = chunks().find(c => c.id === h.chunkId);
  if (chunk) {
    if (!chunk.text.includes(core) || (h.heading && h.heading !== chunk.heading)) return undefined;
    const { status, supersededBy, ...fresh } = h.freshness ?? { modified: chunk.meta.modified, decay: 1 };
    void status; void supersededBy;
    const { source, ...rest } = h;
    void source;
    return {
      ...rest, freshness: { ...fresh, ...(chunk.meta.status ? { status: chunk.meta.status } : {}), ...(chunk.meta.supersededBy ? { supersededBy: chunk.meta.supersededBy } : {}) },
      ...(chunk.source ? { source: chunk.source } : {}),
    };
  }
  if (h.source || ev.document.startsWith(FILES_PATH_PREFIX) && !isMarkdown(ev.document)) return undefined;
  const text = noteText();
  if (!text || !text.includes(core) || (h.heading && !text.includes(h.heading.split(' › ').pop()!))) return undefined;
  const { status, supersededBy, ...fresh } = h.freshness ?? { modified: '', decay: 1 };
  void status; void supersededBy;
  return { ...h, freshness: fresh };
}

const rank: Record<DomeOutcome['status'], number> = { ok: 0, stale: 1, degraded: 2, not_indexed: 3, timeout: 4, error: 5, denied: 6 };

/** Ejecuta una ruta para una consulta. */
export async function runRoute(rag: RagService, input: RouteRunInput): Promise<RouteRunOutput> {
  const route = getRoute(input.route);
  const { budget, declared } = resolveBudget(input.budget);
  if (route.requiresDeclaredBudget && !declared) {
    throw new RouteError('BUDGET_REQUIRED', `la ruta ${route.id} exige un presupuesto declarado en la petición`);
  }
  const query = validQuery(input.query);
  const asOf = validAsOf(input.asOf);
  const seed = validSeed(input.seed);
  const k = input.k ?? RAG_LIMITS.defaultK;
  if (!Number.isInteger(k) || k < 1 || k > RAG_LIMITS.maxK) throw new RagError('INVALID_INPUT', `k: 1-${RAG_LIMITS.maxK}`);
  const mode: RagMode = input.mode ?? 'hybrid';

  const { targets, allowed, principals, outcomes } = await rag.authorizeTargets(input.domes, input.tool ?? 'vault_rag');
  const guard = new RetrievalGuard(allowed.map(d => ({
    name: d.name, path: d.path, confidentiality: d.confidentiality, principal: principals.get(d.name), files: rag.filesStoreOf(d),
  })));
  const meter = new BudgetMeter(budget);
  const steps: TraceStep[] = [];
  const warnings = new Set<string>();
  let closed = false;
  let fusion: RouteRunOutput['fusion'];

  const req: RetrievalRequest = Object.freeze({
    query, domes: Object.freeze(guard.authorizedDomes()), ...(asOf ? { asOf } : {}), budget: Object.freeze({ ...budget }),
    budgetDeclared: declared, seed, k, mode,
    ...(input.pathPrefix !== undefined ? { pathPrefix: input.pathPrefix } : {}),
    ...(input.includeStale !== undefined ? { includeStale: input.includeStale } : {}),
    ...(input.maxChars !== undefined ? { maxChars: input.maxChars } : {}),
  });

  const ctx: RouteContext = {
    candidates: async (q, opts = {}) => {
      if (closed) return [];
      const m = opts.mode ?? mode;
      if (m !== 'bm25' && !meter.consume('modelCalls', 1)) { steps.push({ step: 'budget', detail: 'maxModelCalls' }); return []; }
      if (m !== 'bm25' && !meter.consume('inputTokens', estimateTokens(q))) { steps.push({ step: 'budget', detail: 'maxInputTokens' }); return []; }
      const names = guard.authorizedDomes().map(d => d.name);
      const res = await rag.search({
        queries: [validQuery(q)], domes: names, k: opts.k ?? k, mode: m,
        pathPrefix: req.pathPrefix, includeStale: req.includeStale, maxChars: req.maxChars,
        timeoutMs: Math.max(50, Math.min(meter.timeLeftMs(), RAG_LIMITS.defaultTimeoutMs)),
      });
      for (const d of res.domes) {
        const prev = outcomes.get(d.name);
        if (!prev || rank[d.status] >= rank[prev.status]) outcomes.set(d.name, d);
      }
      for (const w of res.results[0]?.warnings ?? []) warnings.add(w);
      if (res.fusion) fusion = res.fusion;
      const out: RagHit[] = [];
      for (const h of res.results[0]?.hits ?? []) {
        if (closed || !meter.consume('nodes')) break;
        if (guard.admit({ dome: h.dome, path: h.path, ...(h.source ? { documentId: h.source.documentId } : {}) }).ok) out.push(h);
      }
      return out;
    },
    openNote: (ref) => {
      if (closed || !meter.consume('nodes')) return undefined;
      return guard.readNote(ref);
    },
    documentChunks: (ref) => {
      if (closed || !meter.consume('nodes')) return undefined;
      const a = guard.admit(ref);
      if (!a.ok) return undefined;
      return rag.activeDocumentChunks(a.dome, a.path).map(c => ({ chunkId: c.id, ordinal: c.ordinal, heading: c.heading, text: c.text }));
    },
    consume: (key, n) => !closed && meter.consume(key, n),
    timeLeftMs: () => (closed ? 0 : meter.timeLeftMs()),
    step: (step, detail, nodes) => { if (!closed) steps.push({ step, ...(detail !== undefined ? { detail } : {}), ...(nodes !== undefined ? { nodes } : {}) }); },
    evidenceOf: (hit) => guard.evidence(hit),
  };

  // Tope de pared: si la ruta no termina a tiempo, el contexto se cierra y no se sirve nada.
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<'timeout'>(resolve => { timer = setTimeout(() => resolve('timeout'), Math.max(0, meter.timeLeftMs())); });
  let output: RouteOutput | 'timeout';
  try {
    output = await Promise.race([route.run(req, ctx), timeout]);
  } finally {
    clearTimeout(timer);
  }
  if (output === 'timeout') {
    closed = true;
    warnings.add(BUDGET_EXHAUSTED);
    steps.push({ step: 'budget', detail: 'maxLatencyMs' });
    output = { hits: [] };
  }
  closed = true;

  // Guard final: solo se sirve lo que el guard admite AHORA, cada hit con su evidencia, y con
  // texto que procede del nodo admitido (una ruta no puede sustituirlo ni inventar metadatos).
  const hits: RagHit[] = [];
  const evidence: Evidence[] = [];
  const seen = new Set<string>();
  const chunksOf = new Map<string, ReturnType<RagService['activeDocumentChunks']>>();
  const levelOf = new Map(allowed.map(d => [d.name, d.confidentiality]));
  for (const h of Array.isArray(output.hits) ? output.hits.slice(0, k) : []) {
    const ev = guard.evidence(h);
    if (!ev || seen.has(`${ev.dome}\u0000${h.chunkId}`)) continue;
    const served = provenance(h, ev, () => {
      const key = `${ev.dome}\u0000${ev.document}`;
      if (!chunksOf.has(key)) chunksOf.set(key, rag.activeDocumentChunks(ev.dome, ev.document));
      return chunksOf.get(key)!;
    }, () => (h.source ? undefined : guard.readNote({ dome: ev.dome, path: ev.document })?.text));
    // La evidencia se calcula con el hit SERVIDO (fuente del índice), no con el propuesto por la ruta.
    const servedEv = served && guard.evidence(served);
    if (!served || !servedEv) continue;
    seen.add(`${ev.dome}\u0000${h.chunkId}`);
    hits.push({ ...served, confidentiality: levelOf.get(ev.dome)! });
    evidence.push(servedEv);
  }
  for (const e of output.evidence ?? []) {
    if (seen.has(`${e.dome}\u0000${e.chunkId}`)) continue;
    const isFile = e.document?.startsWith(FILES_PATH_PREFIX) && !isMarkdown(e.document);
    const a = guard.admit({ dome: e.dome, path: e.document, ...(isFile ? { documentId: e.document.slice(FILES_PATH_PREFIX.length) } : {}) });
    if (!a.ok) continue;
    seen.add(`${e.dome}\u0000${e.chunkId}`);
    evidence.push({ ...e, dome: a.dome, document: a.path });
  }
  const offered = Array.isArray(output.hits) ? Math.min(k, output.hits.length) : 0;
  if (hits.length < offered) steps.push({ step: 'guard:final', nodes: offered - hits.length });
  if (meter.exhausted) warnings.add(BUDGET_EXHAUSTED);
  if (asOf && !route.supportsAsOf) warnings.add(AS_OF_UNSUPPORTED);
  // Los avisos de la ruta son códigos, no texto libre (no pueden transportar contenido).
  for (const w of output.warnings ?? []) if (typeof w === 'string' && WARNING_CODE.test(w)) warnings.add(w);

  const result: RetrievalResult = {
    hits, evidence,
    trace: { route: route.id, reason: input.reason ?? 'explicit', seed, steps, denied: guard.denied },
    consumed: meter.snapshot(),
    ...(output.abstain ? { abstain: true } : {}),
    ...(warnings.size ? { warnings: [...warnings] } : {}),
  };
  return { result, domes: targets.map(d => outcomes.get(d.name)!), ...(fusion ? { fusion } : {}) };
}

/** `vault_rag` con `route`: una ejecución por consulta, respuesta con la forma de RagResponse. */
export async function routeSearch(rag: RagService, input: Omit<RouteRunInput, 'query'> & { queries: string[] }): Promise<RagResponse> {
  const t0 = Date.now();
  if (!Array.isArray(input.queries) || input.queries.length < 1 || input.queries.length > RAG_LIMITS.maxQueries) {
    throw new RagError('INVALID_INPUT', `queries: entre 1 y ${RAG_LIMITS.maxQueries}`);
  }
  const results: RagResponse['results'] = [];
  const domes = new Map<string, DomeOutcome>();
  const order: string[] = [];
  let fusion: RouteRunOutput['fusion'];
  for (const query of input.queries) {
    const { result, domes: ds, fusion: f } = await runRoute(rag, { ...input, query });
    if (f) fusion = fusion === 'rank' ? 'rank' : f;
    results.push({
      query, hits: result.hits, evidence: result.evidence, trace: result.trace, consumed: result.consumed,
      ...(result.abstain ? { abstain: true } : {}), ...(result.warnings ? { warnings: result.warnings } : {}),
    });
    for (const d of ds) {
      if (!domes.has(d.name)) order.push(d.name);
      const prev = domes.get(d.name);
      if (!prev || rank[d.status] > rank[prev.status]) domes.set(d.name, d);
    }
  }
  const k = input.k ?? RAG_LIMITS.defaultK;
  const maxChars = input.maxChars ?? RAG_LIMITS.defaultMaxChars;
  const merged = results.length > 1 ? applyCharBudget(fuseAcross(results.map(r => r.hits), k), maxChars) : undefined;
  return {
    results, ...(merged ? { merged } : {}),
    domes: order.map(n => domes.get(n)!),
    timings: { totalMs: Date.now() - t0, embedMs: 0, syncMs: 0 },
    ...(fusion ? { fusion } : {}),
    route: input.route,
  };
}
