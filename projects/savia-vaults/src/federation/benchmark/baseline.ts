import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FederatedSearchEngine } from '../search.js';
import { FederationRegistry } from '../registry.js';
import type { A2AClient } from '../a2a-client.js';
import type { FederatedDome, FederatedSearchContext, FederatedSearchResponse, FederatedSearchResult } from '../types.js';
import type { SearchEngine } from '../../search/index.js';
import { sha256, sha256Json } from './canon.js';
import { mean, ndcgAtK, percentile, precisionAtK, mrr, ratio, recallAtK, tokenCount } from './metrics.js';
import { BENCH_PROFILE, BENCH_SCHEMA_VERSION, STRATA, type Aggregate, type BaselineReport, type BenchCorpus, type BenchDataset, type BenchProfile, type BenchQuery, type QueryMetrics, type Split } from './types.js';

// Índice léxico mínimo (BM25) por vault. Sustituye al motor real para que el baseline sea
// reproducible y no abra red: el objeto bajo medida es el FederatedSearchEngine real.
class LexIndex {
  private docs: Array<{ id: string; text: string; terms: Map<string, number>; len: number }> = [];
  private df = new Map<string, number>(); private avg = 0;
  constructor(entries: Array<{ id: string; text: string }>) {
    for (const e of entries) {
      const terms = new Map<string, number>(); const toks = tokenize(e.text);
      for (const t of toks) terms.set(t, (terms.get(t) ?? 0) + 1);
      for (const t of terms.keys()) this.df.set(t, (this.df.get(t) ?? 0) + 1);
      this.docs.push({ id: e.id, text: e.text, terms, len: toks.length });
    }
    this.avg = this.docs.reduce((s, d) => s + d.len, 0) / Math.max(1, this.docs.length);
  }
  search(query: string, max: number): Array<{ path: string; score: number; snippet: string; tags: string[] }> {
    const q = tokenize(query); const n = this.docs.length;
    return this.docs.map(d => {
      let score = 0;
      for (const t of q) { const f = d.terms.get(t) ?? 0; if (!f) continue; const idf = Math.log(1 + (n - (this.df.get(t) ?? 0) + 0.5) / ((this.df.get(t) ?? 0) + 0.5)); score += idf * (f * 2.2) / (f + 1.2 * (0.25 + 0.75 * d.len / this.avg)); }
      return { path: d.id, score, snippet: d.text, tags: [] as string[] };
    }).filter(r => r.score > 0).sort((a, b) => b.score - a.score || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0)).slice(0, max);
  }
}
const tokenize = (s: string): string[] => s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
const contentHash = (s: string): string => sha256(s).slice(0, 8);

// Vista del router: sin relevant/useful/forbidden, para que el challenger no pueda ver etiquetas.
export type RouteView = Pick<BenchQuery, 'id' | 'query' | 'allowedVaults' | 'unhealthyVaults'>;

export interface BaselineOptions {
  profile?: BenchProfile;
  // Solo pruebas del propio benchmark: fuerzan fallos para demostrar que las métricas pueden fallar.
  cacheTtlMs?: number;
  tamperResult?: (r: FederatedSearchResult) => FederatedSearchResult;
  // Challenger A/B (R04): estrecha los destinos ANTES de ejecutar; solo recibe la consulta, no sus etiquetas.
  // Se ejecuta SIEMPRE route(q) ∩ allowedVaults: el gancho nunca amplía la policy. Cada id propuesto fuera de la
  // policy cuenta como exposición (salida cruda del router), aunque no llegue a consultarse.
  route?: (q: RouteView) => string[];
}

// Ejecuta cada consulta cold (motor nuevo) y warm (misma consulta, mismo motor -> cache).
export async function runBaseline(corpus: BenchCorpus, dataset: BenchDataset, opts: BaselineOptions = {}): Promise<{ report: BaselineReport; metrics: QueryMetrics[] }> {
  const profile = opts.profile ?? BENCH_PROFILE;
  if (sha256Json(corpus) !== dataset.corpusSha256) throw new Error('corpus no coincide con dataset.corpusSha256');
  const indexes = new Map(corpus.vaults.map(v => [v.id, new LexIndex(corpus.docs.filter(d => d.vault === v.id))]));
  const docById = new Map(corpus.docs.map(d => [d.id, d]));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'se395-bench-'));
  const metrics: QueryMetrics[] = [];
  try {
    for (const q of dataset.queries) {
      let calls = 0; let callLatencies: number[] = [];
      const client = {
        async search(dome: FederatedDome, query: string, max = 20) {
          calls++;
          const hits = indexes.get(dome.id)!.search(query, max);
          const latencyMs = 40 + parseInt(sha256(`${query}|${dome.id}`).slice(0, 4), 16) % 160;
          callLatencies.push(latencyMs);
          const results: FederatedSearchResult[] = hits.map(h => ({ path: h.path, score: h.score * dome.weight, snippet: h.snippet, tags: [], source: dome.id, contentHash: contentHash(h.snippet) })).map(r => opts.tamperResult?.(r) ?? r);
          return { results, status: 'ok' as const, latencyMs };
        },
        async healthCheck() { return { healthy: true, latencyMs: 1 }; },
      } as unknown as Pick<A2AClient, 'search' | 'healthCheck'>;
      const registry = new FederationRegistry(path.join(tmp, q.id));
      for (const v of corpus.vaults.filter(x => !x.local)) registry.add({ id: v.id, name: v.name, url: 'http://bench.invalid', timeout: 3000, enabled: true, weight: v.weight, tags: [], status: q.unhealthyVaults.includes(v.id) ? 'unhealthy' : 'healthy' });
      const local = { search: ({ query, maxResults }: { query: string; maxResults: number }) => indexes.get('local')!.search(query, maxResults) } as unknown as SearchEngine;
      const engine = new FederatedSearchEngine(local, registry, { client, maxTotalResults: 50, cacheTtlMs: opts.cacheTtlMs });
      const proposed = opts.route ? [...new Set(opts.route({ id: q.id, query: q.query, allowedVaults: [...q.allowedVaults], unhealthyVaults: [...q.unhealthyVaults] }))] : q.allowedVaults;
      const routeLeak = proposed.filter(id => !q.allowedVaults.includes(id)).length;
      const ctx: FederatedSearchContext = { principalId: 'bench-principal', policyRevision: 'p1', contentRevision: dataset.corpusSha256.slice(0, 12), allowedDomeIds: proposed.filter(id => q.allowedVaults.includes(id)) };
      for (const cache of ['cold', 'warm'] as const) {
        calls = 0; callLatencies = [];
        const res = await engine.search(q.query, ctx, profile.k);
        // Latencia medida: con llamadas remotas, la mayor de este run (paralelas); sin ellas (cache hit), lo que informa el motor.
        const latency = calls > 0 ? Math.max(...callLatencies) : res.totalMs;
        metrics.push(measure(q, res, cache, calls, latency, docById, profile, routeLeak));
      }
    }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  const datasetSha256 = sha256Json(dataset);
  return { report: buildReport(metrics, profile, dataset, datasetSha256), metrics };
}

function measure(q: BenchQuery, res: FederatedSearchResponse, cache: 'cold' | 'warm', calls: number, latency: number, docs: Map<string, { vault: string; useful: boolean }>, profile: BenchProfile, routeLeak = 0): QueryMetrics {
  // Conjunto evaluado: lo que recibe el consumidor a k. Ranking y tokens miden el mismo top-k.
  const k = profile.k; const results = res.results.slice(0, k);
  const ranked = results.map(r => r.path); const rel = new Set(q.relevant); const useful = new Set(q.useful);
  // Exposición = destinos que el router propuso fuera de la policy + resultados prohibidos o de fuentes no autorizadas.
  let retrieved = 0, irrelevant = 0, usefulTok = 0, provOk = 0, exposed = routeLeak;
  for (const r of results) {
    const t = tokenCount(r.snippet); retrieved += t;
    if (!rel.has(r.path)) irrelevant += t;
    if (useful.has(r.path)) usefulTok += t;
    if (docs.get(r.path)?.vault === r.source) provOk++;
    if (q.forbidden.includes(r.path) || !q.allowedVaults.includes(r.source)) exposed++;
  }
    return {
    queryId: q.id, stratum: q.stratum, split: q.split, cache,
    recallAtK: recallAtK(ranked, q.relevant, k), precisionAtK: precisionAtK(ranked, q.relevant, k), mrr: mrr(ranked, q.relevant), ndcgAtK: ndcgAtK(ranked, q.relevant, k),
    attempts: calls, remoteCalls: calls,
    latencyMs: latency,
    retrievedTokens: retrieved, irrelevantTokens: irrelevant, usefulTokens: usefulTok, usefulDensity: ratio(usefulTok, retrieved),
    duplicates: 0, conflictsSurfaced: q.conflictPairs.filter(([a, b]) => ranked.includes(a) && ranked.includes(b)).length,
    provenanceOk: ratio(provOk, results.length), exposed,
  };
}

export function aggregate(rows: QueryMetrics[]): Aggregate {
  const sum = (f: (m: QueryMetrics) => number): number => rows.reduce((s, m) => s + f(m), 0);
  const lat = rows.map(m => m.latencyMs);
  const retrievedTokens = sum(m => m.retrievedTokens); const usefulTokens = sum(m => m.usefulTokens);
  return {
    n: rows.length, recallAtK: mean(rows.map(m => m.recallAtK)), precisionAtK: mean(rows.map(m => m.precisionAtK)), mrr: mean(rows.map(m => m.mrr)), ndcgAtK: mean(rows.map(m => m.ndcgAtK)),
    remoteCalls: sum(m => m.remoteCalls), attempts: sum(m => m.attempts), latencyP50: percentile(lat, 0.5), latencyP95: percentile(lat, 0.95),
    retrievedTokens, irrelevantTokens: sum(m => m.irrelevantTokens), usefulTokens, usefulDensity: ratio(usefulTokens, retrievedTokens),
    duplicates: sum(m => m.duplicates), conflictsSurfaced: sum(m => m.conflictsSurfaced), provenance: mean(rows.map(m => m.provenanceOk)), exposed: sum(m => m.exposed),
  };
}

function buildReport(metrics: QueryMetrics[], profile: BenchProfile, dataset: BenchDataset, datasetSha256: string): BaselineReport {
  const both = (f: (m: QueryMetrics) => boolean): Record<'cold' | 'warm', Aggregate> => ({
    cold: aggregate(metrics.filter(m => m.cache === 'cold' && f(m))), warm: aggregate(metrics.filter(m => m.cache === 'warm' && f(m))),
  });
  const splits: Split[] = ['train', 'calibration', 'test'];
  return {
    schemaVersion: BENCH_SCHEMA_VERSION, profile, corpusSha256: dataset.corpusSha256, datasetSha256,
    overall: both(() => true),
    bySplit: Object.fromEntries(splits.map(s => [s, both(m => m.split === s)])) as BaselineReport['bySplit'],
    byStratum: Object.fromEntries(STRATA.map(s => [s, both(m => m.stratum === s)])) as BaselineReport['byStratum'],
  };
}
