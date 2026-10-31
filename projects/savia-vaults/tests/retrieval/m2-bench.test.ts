// SE-489 M2 — resumen de latencia del reranker del script de medición (aparte de la ruta entera).
import { describe, expect, it } from 'vitest';
import { latencySummary, stratify } from '../../eval/evidence-bench/m2-bench.js';

describe('latencySummary', () => {
  it('percentiles y coste por par solo con las llamadas correctas', () => {
    const s = latencySummary([
      { scoreMs: 100, pairs: 10, ok: true }, { scoreMs: 300, pairs: 10, ok: true },
      { scoreMs: 200, pairs: 10, ok: true }, { scoreMs: 900, pairs: 10, ok: true },
      { scoreMs: 5, pairs: 10, ok: false },
    ]);
    expect(s).toEqual({ calls: 5, failed: 1, p50Ms: 200, p95Ms: 900, meanMsPerPair: 37.5 });
  });
  it('sin llamadas correctas no inventa cifras', () => {
    expect(latencySummary([])).toEqual({ calls: 0, failed: 0, p50Ms: null, p95Ms: null, meanMsPerPair: null });
    expect(latencySummary([{ scoreMs: 1, pairs: 3, ok: false }])).toMatchObject({ calls: 1, failed: 1, p50Ms: null, meanMsPerPair: null });
  });
});

describe('stratify', () => {
  const cs = ['A', 'A', 'A', 'B', 'A', 'B', 'C'].map((category, i) => ({ category, i }));
  it('toma los N primeros de cada categoría conservando el orden', () => {
    expect(stratify(cs, 2).map(c => c.i)).toEqual([0, 1, 3, 5, 6]);
  });
  it('N mayor que la categoría devuelve todo; N = 0 no devuelve nada', () => {
    expect(stratify(cs, 99)).toHaveLength(cs.length);
    expect(stratify(cs, 0)).toEqual([]);
  });
});
