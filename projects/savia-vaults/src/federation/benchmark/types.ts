// SE-395 R01 — contratos del benchmark de conectividad adaptativa (solo datos, sin red).
export const BENCH_SCHEMA_VERSION = 1;

export const STRATA = ['monodomain', 'cross_domain', 'ambiguous', 'conflicting', 'stale', 'restricted', 'unhealthy', 'repeated', 'new'] as const;
export type Stratum = typeof STRATA[number];
export type Split = 'train' | 'calibration' | 'test';

export interface BenchVault { id: string; name: string; weight: number; local: boolean; }
export interface BenchDoc { id: string; vault: string; topic: string; text: string; stale: boolean; useful: boolean; }
export interface BenchCorpus { schemaVersion: number; seed: number; vaults: BenchVault[]; docs: BenchDoc[]; conflictPairs: Array<[string, string]>; }

export interface BenchQuery {
  id: string; stratum: Stratum; family: string; split: Split; query: string;
  allowedVaults: string[]; unhealthyVaults: string[];
  relevant: string[]; useful: string[]; forbidden: string[];
  conflictPairs: Array<[string, string]>;
  baselineAdvantage: boolean;
}
export interface BenchDataset { schemaVersion: number; seed: number; corpusSha256: string; queries: BenchQuery[]; }

// Perfil preregistrado (SE-395 §Configuración): maxVaults=3, maxRemoteCalls=3, maxBranches=2, 3000 ms, 4096 tokens.
export interface BenchProfile { k: number; maxVaults: number; maxRemoteCalls: number; maxBranches: number; maxLatencyMs: number; maxContextTokens: number; tokenizer: 'whitespace-proxy'; }
export const BENCH_PROFILE: BenchProfile = { k: 10, maxVaults: 3, maxRemoteCalls: 3, maxBranches: 2, maxLatencyMs: 3000, maxContextTokens: 4096, tokenizer: 'whitespace-proxy' };

// Umbrales del gate preregistrados antes de consultar el holdout.
export const GATE_THRESHOLDS = {
  remoteCallReduction: 0.30, irrelevantContextReduction: 0.25, recallDeltaMin: -0.02,
  provenanceVsBaseline: 0, exposureMax: 0, p95VsBaseline: 0, usefulDensityRatio: 1.20,
} as const;

export interface QueryMetrics {
  queryId: string; stratum: Stratum; split: Split; cache: 'cold' | 'warm';
  recallAtK: number | null; precisionAtK: number | null; mrr: number | null; ndcgAtK: number | null;
  attempts: number; remoteCalls: number; latencyMs: number; retrievedTokens: number;
  irrelevantTokens: number; usefulTokens: number; usefulDensity: number | null;
  duplicates: number; conflictsSurfaced: number; provenanceOk: number | null; exposed: number;
}
export interface Aggregate {
  n: number; recallAtK: number | null; precisionAtK: number | null; mrr: number | null; ndcgAtK: number | null;
  remoteCalls: number; attempts: number; latencyP50: number | null; latencyP95: number | null;
  retrievedTokens: number; irrelevantTokens: number; usefulTokens: number; usefulDensity: number | null;
  duplicates: number; conflictsSurfaced: number; provenance: number | null; exposed: number;
}
export interface BaselineReport {
  schemaVersion: number; profile: BenchProfile; corpusSha256: string; datasetSha256: string;
  overall: Record<'cold' | 'warm', Aggregate>;
  bySplit: Record<Split, Record<'cold' | 'warm', Aggregate>>;
  byStratum: Record<Stratum, Record<'cold' | 'warm', Aggregate>>;
}
