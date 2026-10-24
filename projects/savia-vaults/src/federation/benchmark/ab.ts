// SE-395 R04 — A/B aislado baseline vs challenger estático sobre el MISMO snapshot (sin red) y decisión de fase.
import { selectDestinations } from '../adaptive/select.js';
import type { Guidance } from '../adaptive/guidance.js';
import { runBaseline, type RouteView } from './baseline.js';
import { prng } from './generate.js';
import { mean, percentile, ratio } from './metrics.js';
import { BENCH_PROFILE, GATE_THRESHOLDS, type BenchCorpus, type BenchDataset, type QueryMetrics, type Split } from './types.js';

// Reglas de decisión preregistradas en R04, antes de ejecutar el holdout. Separadas de GATE_THRESHOLDS (hash fijado en R01).
export const DECISION_RULES = { minPairs: 100, bootstrapResamples: 2000, bootstrapSeed: 395, confidence: 0.95 } as const;

export type Decision = 'GO' | 'NO_GO' | 'NEEDS_MORE_EVIDENCE';
export interface GateResult { name: string; value: number | null; threshold: number; pass: boolean | null; }
export interface AbReport {
  split: Split; pairs: number; decision: Decision; reasons: string[]; gates: GateResult[];
  recallDelta: { mean: number | null; ciLow: number | null; ciHigh: number | null };
}

// Guidance estático derivado SOLO del split train: vocabulario más frecuente de cada vault remoto.
export function trainGuidance(corpus: BenchCorpus, dataset: BenchDataset): Guidance {
  const trainTopics = new Set(dataset.queries.filter(q => q.split === 'train').map(q => q.family));
  const cues = corpus.vaults.filter(v => !v.local).map(v => {
    const freq = new Map<string, number>();
    for (const d of corpus.docs) if (d.vault === v.id && trainTopics.has(d.topic)) for (const t of d.text.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean)) freq.set(t, (freq.get(t) ?? 0) + 1);
    const top = [...freq.entries()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).slice(0, 8);
    return { vaultId: v.id, attracts: top.map(([term]) => ({ term, score: 0.25 })), repels: [], specialties: [] as string[] };
  });
  return { version: 1, cues };
}

export function makeRouter(corpus: BenchCorpus, guidance: Guidance): (q: RouteView) => string[] {
  return q => {
    const domes = corpus.vaults.filter(v => !v.local).map(v => ({ id: v.id, weight: v.weight, enabled: true, status: (q.unhealthyVaults.includes(v.id) ? 'unhealthy' : 'healthy') as 'healthy' | 'unhealthy' }));
    return selectDestinations({ query: q.query, allowedDomeIds: q.allowedVaults, domes, guidance, budget: { maxVaults: BENCH_PROFILE.maxVaults, maxRemoteCalls: BENCH_PROFILE.maxRemoteCalls }, flags: { adaptive: true } }).selected;
  };
}

export function pairedBootstrap(deltas: number[]): { mean: number | null; ciLow: number | null; ciHigh: number | null } {
  if (deltas.length === 0) return { mean: null, ciLow: null, ciHigh: null };
  const rand = prng(DECISION_RULES.bootstrapSeed);
  const means: number[] = [];
  for (let i = 0; i < DECISION_RULES.bootstrapResamples; i++) {
    let s = 0;
    for (let j = 0; j < deltas.length; j++) s += deltas[Math.floor(rand() * deltas.length)];
    means.push(s / deltas.length);
  }
  const a = (1 - DECISION_RULES.confidence) / 2;
  return { mean: deltas.reduce((x, y) => x + y, 0) / deltas.length, ciLow: percentile(means, a), ciHigh: percentile(means, 1 - a) };
}

const sum = (rows: QueryMetrics[], f: (m: QueryMetrics) => number): number => rows.reduce((s, m) => s + f(m), 0);
const fin = (v: number | null): number | null => (v !== null && Number.isFinite(v) ? v : null);
const reduction = (chal: number, base: number): number | null => { const r = ratio(chal, base); return r === null ? null : 1 - r; };

export function compare(base: QueryMetrics[], chal: QueryMetrics[], split: Split): AbReport {
  const sel = (rows: QueryMetrics[]): QueryMetrics[] => rows.filter(m => m.cache === 'cold' && m.split === split).sort((x, y) => (x.queryId < y.queryId ? -1 : 1));
  const b = sel(base); const c = sel(chal);
  if (b.length !== c.length || b.some((m, i) => m.queryId !== c[i].queryId)) throw new Error('A/B: los conjuntos de consultas no coinciden (distinto snapshot)');
  const deltas: number[] = [];
  b.forEach((m, i) => { if (m.recallAtK !== null && c[i].recallAtK !== null) deltas.push(c[i].recallAtK! - m.recallAtK); });
  const rd = pairedBootstrap(deltas);
  const T = GATE_THRESHOLDS;
  const callRed = reduction(sum(c, m => m.remoteCalls), sum(b, m => m.remoteCalls));
  const irrRed = reduction(sum(c, m => m.irrelevantTokens), sum(b, m => m.irrelevantTokens));
  const densC = ratio(sum(c, m => m.usefulTokens), sum(c, m => m.retrievedTokens)); const densB = ratio(sum(b, m => m.usefulTokens), sum(b, m => m.retrievedTokens));
  const dens = densC === null || densB === null ? null : fin(ratio(densC, densB));
  const p95b = percentile(b.map(m => m.latencyMs), 0.95); const p95c = percentile(c.map(m => m.latencyMs), 0.95);
  const provB = mean(b.map(m => m.provenanceOk)); const provC = mean(c.map(m => m.provenanceOk));
  const exposed = sum(c, m => m.exposed);
  const gates: GateResult[] = [
    { name: 'remoteCallReduction', value: callRed, threshold: T.remoteCallReduction, pass: callRed === null ? null : callRed >= T.remoteCallReduction },
    { name: 'irrelevantContextReduction', value: irrRed, threshold: T.irrelevantContextReduction, pass: irrRed === null ? null : irrRed >= T.irrelevantContextReduction },
    { name: 'recallDeltaCiLow', value: rd.ciLow, threshold: T.recallDeltaMin, pass: rd.ciLow === null ? null : rd.ciLow >= T.recallDeltaMin },
    { name: 'provenanceVsBaseline', value: provB === null || provC === null ? null : provC - provB, threshold: T.provenanceVsBaseline, pass: provB === null || provC === null ? null : provC >= provB },
    { name: 'exposure', value: exposed, threshold: T.exposureMax, pass: exposed <= T.exposureMax },
    { name: 'p95VsBaseline', value: p95b === null || p95c === null ? null : p95c - p95b, threshold: T.p95VsBaseline, pass: p95b === null || p95c === null ? null : p95c <= p95b },
    { name: 'usefulDensityRatio', value: dens, threshold: T.usefulDensityRatio, pass: dens === null ? null : dens >= T.usefulDensityRatio },
  ];
  const failed = gates.filter(g => g.pass === false).map(g => g.name);
  const unknown = gates.filter(g => g.pass === null).map(g => g.name);
  const enough = deltas.length >= DECISION_RULES.minPairs;
  const reasons: string[] = [];
  let decision: Decision;
  // Exposición > 0 es NO_GO con cualquier muestra: es una violación de seguridad, no ruido estadístico.
  if (exposed > T.exposureMax) { decision = 'NO_GO'; reasons.push(`exposición ${exposed} > ${T.exposureMax}`); }
  else if (failed.length > 0 && enough) { decision = 'NO_GO'; reasons.push(`gates fallidos: ${failed.join(', ')}`); }
  else if (failed.length > 0 || unknown.length > 0 || !enough) {
    decision = 'NEEDS_MORE_EVIDENCE';
    if (failed.length) reasons.push(`gates fallidos con muestra insuficiente: ${failed.join(', ')}`);
    if (unknown.length) reasons.push(`gates sin dato (N/A): ${unknown.join(', ')}`);
    if (!enough) reasons.push(`pares ${deltas.length} < ${DECISION_RULES.minPairs}`);
  } else { decision = 'GO'; reasons.push('todos los gates pasan'); }
  return { split, pairs: deltas.length, decision, reasons, gates, recallDelta: rd };
}

export async function runAb(corpus: BenchCorpus, dataset: BenchDataset, split: Split, route?: (q: RouteView) => string[]): Promise<AbReport> {
  const base = await runBaseline(corpus, dataset);
  const chal = await runBaseline(corpus, dataset, { route: route ?? makeRouter(corpus, trainGuidance(corpus, dataset)) });
  return compare(base.metrics, chal.metrics, split);
}
