import { sha256Json } from './canon.js';
import { STRATA, type BenchCorpus, type BenchDataset } from './types.js';

export const MIN_QUERIES = 180;
export const MIN_PER_STRATUM = 20;

// Devuelve la lista de violaciones del contrato del dataset (vacía = válido).
export function validateDataset(corpus: BenchCorpus, dataset: BenchDataset): string[] {
  const errors: string[] = [];
  if (sha256Json(corpus) !== dataset.corpusSha256) errors.push('corpusSha256 no coincide con el corpus');
  const ids = new Set(dataset.queries.map(q => q.id));
  if (ids.size !== dataset.queries.length) errors.push('ids de consulta duplicados');
  if (dataset.queries.length < MIN_QUERIES) errors.push(`${dataset.queries.length} consultas < ${MIN_QUERIES}`);
  for (const s of STRATA) {
    const n = dataset.queries.filter(q => q.stratum === s).length;
    if (n < MIN_PER_STRATUM) errors.push(`estrato ${s}: ${n} < ${MIN_PER_STRATUM}`);
  }
  const docIds = new Set(corpus.docs.map(d => d.id));
  const vaultIds = new Set(corpus.vaults.map(v => v.id));
  const familySplit = new Map<string, string>();
  const staleDocs = new Set(corpus.docs.filter(d => d.stale).map(d => d.id));
  for (const [a, b] of [...corpus.conflictPairs, ...dataset.queries.flatMap(q => q.conflictPairs)]) {
    if (!docIds.has(a) || !docIds.has(b)) errors.push(`conflictPair con documento desconocido (${a}, ${b})`);
  }
  for (const s of STRATA) for (const sp of ['train', 'calibration', 'test']) {
    if (!dataset.queries.some(q => q.stratum === s && q.split === sp)) errors.push(`estrato ${s} sin consultas en ${sp}`);
  }
  for (const q of dataset.queries) {
    for (const d of [...q.relevant, ...q.useful, ...q.forbidden]) if (!docIds.has(d)) errors.push(`${q.id}: documento desconocido ${d}`);
    for (const v of [...q.allowedVaults, ...q.unhealthyVaults]) if (!vaultIds.has(v)) errors.push(`${q.id}: vault desconocido ${v}`);
    if (q.relevant.length === 0) errors.push(`${q.id}: relevant vacío (las métricas darían N/A)`);
    if (q.relevant.some(r => staleDocs.has(r))) errors.push(`${q.id}: documento obsoleto marcado como relevante`);
    if (q.useful.some(u => !q.relevant.includes(u))) errors.push(`${q.id}: useful no es subconjunto de relevant`);
    if (q.relevant.some(r => q.forbidden.includes(r))) errors.push(`${q.id}: relevante y prohibido a la vez`);
    const prev = familySplit.get(q.family);
    if (prev && prev !== q.split) errors.push(`familia ${q.family} en dos splits (${prev}, ${q.split})`);
    familySplit.set(q.family, q.split);
  }
  return errors;
}
