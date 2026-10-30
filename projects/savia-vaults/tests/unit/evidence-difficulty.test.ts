// SE-489 R1 — métricas de la validación de dificultad del banco de evidencia.
import { describe, it, expect } from 'vitest';
import { scoreCase, aggregate, rankedDocs, type BenchCase } from '../../eval/evidence-bench/evidence-difficulty.js';

const hit = (dome: string, path: string, text = '') => ({ dome, path, text });

const base: BenchCase = {
  id: 'C-001', category: 'C', split: 'dev', query: 'q',
  scope: { allowed_domes: ['bench-legal'], as_of: null },
  expected: {
    required_evidence: [
      { dome: 'bench-legal', document: 'c/contrato.md', locator: { section: null, quote: 'penalización del 1 %' } },
      { dome: 'bench-legal', document: 'c/anexo-I.md', locator: { section: null, quote: '| S1 | 2 h |' } },
    ],
    forbidden_evidence: [{ dome: 'bench-legal', document: 'd/anexo-I.md' }],
    must_abstain: false,
  },
};

describe('evidence-difficulty', () => {
  it('rankedDocs deduplica por cúpula y ruta conservando el orden', () => {
    expect(rankedDocs([hit('a', 'x'), hit('a', 'x'), hit('b', 'x'), hit('a', 'y')])).toEqual(['a:x', 'b:x', 'a:y']);
  });

  it('Recall@10 cuenta documentos requeridos en los 10 primeros', () => {
    const hits = [hit('bench-legal', 'c/contrato.md', 'una penalización del 1 % de'), ...Array.from({ length: 10 }, (_, i) => hit('bench-legal', `z${i}`)), hit('bench-legal', 'c/anexo-I.md', '| S1 | 2 h |')];
    const s = scoreCase(base, hits);
    expect(s.recall10).toBe(0.5); // el anexo está en la posición 12
    expect(s.evidenceRecall10).toBe(0.5);
    expect(s.forbiddenAt10).toBe(false);
  });

  it('EvidenceRecall exige la cita, no solo el documento', () => {
    const s = scoreCase(base, [hit('bench-legal', 'c/contrato.md', 'otra cláusula'), hit('bench-legal', 'c/anexo-I.md', '| S1  |  2 h |')]);
    expect(s.recall10).toBe(1);
    expect(s.evidenceRecall10).toBe(0.5); // espacios normalizados en el anexo; el contrato no trae la cita
  });

  it('detecta evidencia prohibida en el top-10', () => {
    expect(scoreCase(base, [hit('bench-legal', 'd/anexo-I.md')]).forbiddenAt10).toBe(true);
  });

  it('abstención: sin hits es abstenerse; con hits no', () => {
    const abst: BenchCase = { ...base, expected: { ...base.expected, required_evidence: [], must_abstain: true } };
    expect(scoreCase(abst, []).abstained).toBe(true);
    expect(scoreCase(abst, [hit('bench-legal', 'q')]).abstained).toBe(false);
    expect(scoreCase(abst, []).recall10).toBeNull();
  });

  it('aggregate promedia por categoría solo los casos con evidencia', () => {
    const abst: BenchCase = { ...base, id: 'C-002', expected: { ...base.expected, required_evidence: [], must_abstain: true } };
    const rows = [
      { c: base, s: scoreCase(base, [hit('bench-legal', 'c/contrato.md'), hit('bench-legal', 'c/anexo-I.md')]) },
      { c: { ...base, id: 'C-003' }, s: scoreCase(base, []) },
      { c: abst, s: scoreCase(abst, [hit('x', 'y')]) },
    ];
    const agg = aggregate(rows);
    expect(agg.C.n).toBe(3);
    expect(agg.C.nRecall).toBe(2);
    expect(agg.C.recall10).toBe(0.5);
    expect(agg.C.abstainCorrect).toBe(0);
    expect(agg.C.nAbstain).toBe(1);
  });
});
