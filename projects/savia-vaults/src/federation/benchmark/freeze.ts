import * as fs from 'node:fs';
import * as path from 'node:path';
import { canonicalJson, sha256Json } from './canon.js';
import { runBaseline } from './baseline.js';
import { BENCH_PROFILE, BENCH_SCHEMA_VERSION, GATE_THRESHOLDS, type BaselineReport, type BenchCorpus, type BenchDataset } from './types.js';

export interface FreezeManifest {
  schemaVersion: number; seed: number; corpusSha256: string; datasetSha256: string; baselineSha256: string;
  profile: typeof BENCH_PROFILE; thresholds: typeof GATE_THRESHOLDS;
  labels: { queries: number; byStratum: Record<string, number>; bySplit: Record<string, number> };
}

export function buildFreeze(corpus: BenchCorpus, dataset: BenchDataset, report: BaselineReport): FreezeManifest {
  const count = (key: 'stratum' | 'split'): Record<string, number> => {
    const out: Record<string, number> = {};
    for (const q of dataset.queries) out[q[key]] = (out[q[key]] ?? 0) + 1;
    return out;
  };
  return {
    schemaVersion: BENCH_SCHEMA_VERSION, seed: dataset.seed, corpusSha256: sha256Json(corpus), datasetSha256: sha256Json(dataset), baselineSha256: sha256Json(report),
    profile: BENCH_PROFILE, thresholds: GATE_THRESHOLDS, labels: { queries: dataset.queries.length, byStratum: count('stratum'), bySplit: count('split') },
  };
}

export async function buildAll(corpus: BenchCorpus, dataset: BenchDataset): Promise<{ report: BaselineReport; freeze: FreezeManifest }> {
  const { report } = await runBaseline(corpus, dataset);
  return { report, freeze: buildFreeze(corpus, dataset, report) };
}

// Compara (o escribe) los artefactos congelados. Devuelve los nombres que difieren; con write=true escribe y devuelve [].
export function syncFrozen(dir: string, files: Record<string, unknown>, write: boolean): string[] {
  const drift: string[] = [];
  for (const [name, value] of Object.entries(files)) {
    const body = JSON.stringify(JSON.parse(canonicalJson(value)), null, 2) + '\n';
    const file = path.join(dir, name);
    if (write) { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(file, body); continue; }
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf-8') !== body) drift.push(name);
  }
  return drift;
}
