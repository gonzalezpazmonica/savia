// SE-489 M2 — reranker cross-encoder local sobre el top-N de M0. Solo reordena hits que el
// contexto ya admitió: no abre nodos nuevos, así que no puede ampliar lo que se lee. Cualquier
// fallo (sin modelo, digest distinto, presupuesto, tiempo, error) devuelve el orden de M0 con un
// aviso y un paso de traza: fail-open en calidad, nunca en autorización (el guard final del runner
// revisa igualmente cada hit). La latencia del reranker se mide aparte (`takeRerankTimings`).
import { ROUTE_CONTRACT_VERSION, estimateTokens, registerRoute, type RetrievalRoute } from '../route.js';
import { RERANK_MAX_TOKENS, RerankError, loadOnnxCrossEncoder, resolveRerankConfig, type RerankConfig, type RerankScorer } from '../rerank/cross-encoder.js';
import type { RagHit } from '../../rag/types.js';

export const RERANK_FALLBACK = 'RERANK_FALLBACK';

export interface RerankTiming { scoreMs: number; pairs: number; ok: boolean }
/** Tope de los registros de medición: en un servidor largo no pueden crecer sin límite. */
export const MEASURE_CAP = 1000;
const timings: RerankTiming[] = [];
export const keep = <T>(log: T[], v: T): void => { log.push(v); if (log.length > MEASURE_CAP) log.splice(0, log.length - MEASURE_CAP); };
/** Latencias del reranker desde la última llamada (para medirlas aparte de la ruta entera). */
export const takeRerankTimings = (): RerankTiming[] => timings.splice(0);

const fallbackLog: string[] = [];
/** Motivos de fallback (sin-reranker, presupuesto, error, puntuaciones no válidas) desde la última llamada. */
export const takeRerankFallbacks = (): string[] => fallbackLog.splice(0);

interface Setup { scorer: RerankScorer; topN: number; maxMs: number }
let override: Setup | undefined;
let cached: { key: string; setup: Promise<Setup>; failedAt?: number } | undefined;
/** Tras un fallo de carga no se vuelve a hashear el modelo (hasta 570 MB) en cada consulta. */
export const LOAD_RETRY_MS = 60_000;

/** Solo tests y medición: fija el reranker sin pasar por el disco. `undefined` lo retira. */
export function setRerankerForTests(s: Setup | undefined): void {
  override = s;
  cached = undefined;
}

async function resolveSetup(): Promise<Setup> {
  if (override) return override;
  const r = resolveRerankConfig();
  if (!r.ok) throw new Error(r.reason);
  const cfg: RerankConfig = r.config;
  const key = JSON.stringify(cfg);
  if (cached?.key !== key || (cached.failedAt !== undefined && Date.now() - cached.failedAt >= LOAD_RETRY_MS)) {
    const setup = loadOnnxCrossEncoder(cfg).then(scorer => ({ scorer, topN: cfg.topN, maxMs: cfg.maxMs }));
    const entry: NonNullable<typeof cached> = { key, setup };
    setup.catch(() => { entry.failedAt = Date.now(); });
    cached = entry;
  }
  return cached.setup;
}

/** Motivo para la traza: solo mensajes propios (sin rutas del host ni detalle de ORT). */
const safeReason = (e: unknown, generic: string): string => (e instanceof RerankError ? e.message : generic);

const docText = (h: RagHit): string => `${h.heading}\n${h.text}`.slice(0, RERANK_MAX_TOKENS * 4);

export const M2_RERANK: RetrievalRoute = {
  id: 'M2',
  description: 'Reranker cross-encoder local sobre el top-N de M0 (fail-open al orden de M0)',
  contractVersion: ROUTE_CONTRACT_VERSION,
  supportsAsOf: false,
  requiresDeclaredBudget: false,
  async run(req, ctx) {
    let setup: Setup | undefined;
    let loadError: string | undefined;
    try { setup = await resolveSetup(); } catch (e) { loadError = safeReason(e, 'carga fallida'); }
    // Sin reranker se piden exactamente los k de M0; con él, N candidatos y se devuelven k.
    const n = Math.max(req.k, setup?.topN ?? req.k);
    const pulled = await ctx.candidates(req.query, { k: Math.min(50, n), mode: req.mode });
    const hits = pulled.slice(0, setup ? Math.max(req.k, setup.topN) : req.k);
    ctx.step('m2:candidates', req.mode, hits.length);
    const fallback = (why: string): { hits: RagHit[]; warnings: string[] } => {
      ctx.step('m2:fallback', why);
      keep(fallbackLog, why.split(':')[0]);
      return { hits: hits.slice(0, req.k), warnings: [RERANK_FALLBACK] };
    };
    if (!setup) return fallback(`sin-reranker: ${loadError}`);
    if (hits.length < 2) return { hits: hits.slice(0, req.k) };
    const pool = hits.slice(0, setup.topN);
    const docs = pool.map(docText);
    const tokens = estimateTokens(req.query) * pool.length + docs.reduce((s, d) => s + estimateTokens(d), 0);
    // Sin presupuesto no se llama al modelo: se conserva M0 y se dice.
    if (!ctx.consume('modelCalls', 1) || !ctx.consume('inputTokens', tokens)) return fallback('presupuesto');
    const budgetMs = Math.min(setup.maxMs, ctx.timeLeftMs());
    const t0 = Date.now();
    let scores: number[];
    try {
      scores = await setup.scorer.score(req.query, docs, t0 + budgetMs);
    } catch (e) {
      keep(timings, { scoreMs: Date.now() - t0, pairs: docs.length, ok: false });
      return fallback(`error: ${safeReason(e, 'fallo al puntuar')}`);
    }
    const scoreMs = Date.now() - t0;
    keep(timings, { scoreMs, pairs: docs.length, ok: true });
    if (scores.length !== pool.length || scores.some(s => !Number.isFinite(s))) return fallback('puntuaciones no válidas');
    // Estable: empates conservan el orden de M0.
    const order = pool.map((h, i) => ({ h, i, s: scores[i] })).sort((a, b) => b.s - a.s || a.i - b.i);
    ctx.step('m2:rerank', `${setup.scorer.id}@${setup.scorer.digest.slice(0, 12)} n=${pool.length}`, pool.length);
    return { hits: [...order.map(o => o.h), ...hits.slice(setup.topN)].slice(0, req.k) };
  },
};

registerRoute(M2_RERANK);
