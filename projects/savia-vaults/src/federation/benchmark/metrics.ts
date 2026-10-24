// Métricas puras. Denominador cero -> null (N/A), nunca una mejora ficticia.
export function recallAtK(ranked: string[], relevant: string[], k: number): number | null {
  if (relevant.length === 0) return null;
  const top = new Set(ranked.slice(0, k));
  return relevant.filter(r => top.has(r)).length / relevant.length;
}

export function precisionAtK(ranked: string[], relevant: string[], k: number): number | null {
  const top = ranked.slice(0, k);
  if (top.length === 0) return null;
  const rel = new Set(relevant);
  return top.filter(r => rel.has(r)).length / top.length;
}

export function mrr(ranked: string[], relevant: string[]): number | null {
  if (relevant.length === 0) return null;
  const rel = new Set(relevant);
  const idx = ranked.findIndex(r => rel.has(r));
  return idx < 0 ? 0 : 1 / (idx + 1);
}

export function ndcgAtK(ranked: string[], relevant: string[], k: number): number | null {
  if (relevant.length === 0) return null;
  const rel = new Set(relevant);
  const dcg = ranked.slice(0, k).reduce((s, id, i) => s + (rel.has(id) ? 1 / Math.log2(i + 2) : 0), 0);
  let ideal = 0;
  for (let i = 0; i < Math.min(k, rel.size); i++) ideal += 1 / Math.log2(i + 2);
  return dcg / ideal;
}

export function ratio(num: number, den: number): number | null { return den === 0 ? null : num / den; }

export function mean(values: Array<number | null>): number | null {
  const v = values.filter((x): x is number => x !== null);
  return v.length === 0 ? null : v.reduce((a, b) => a + b, 0) / v.length;
}

// Percentil por rango más cercano (determinista, sin interpolación).
export function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1))];
}

export function tokenCount(text: string): number { return text.split(/\s+/).filter(Boolean).length; }
