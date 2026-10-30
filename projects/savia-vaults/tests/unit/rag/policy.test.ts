// SE-410 S4 — política de frescura, promoción y SLO
import { describe, it, expect } from 'vitest';
import { excludedReason, decayFactor, promotionDecision, sloStatus, resolveRagConfig, LAG_HOURS_ALERT } from '../../../src/rag/policy.js';
import { RAG_DEFAULTS } from '../../../src/rag/types.js';

const now = new Date('2026-09-29T00:00:00Z');
const cfg = { ...RAG_DEFAULTS, enabled: true };

describe('excludedReason (P6, AC5)', () => {
  it('excluye status configurados', () => {
    expect(excludedReason({ title: 't', modified: '', status: 'deprecated' }, cfg, now)).toBe('status:deprecated');
    expect(excludedReason({ title: 't', modified: '', status: 'accepted' }, cfg, now)).toBeUndefined();
  });

  it('excluye valid_until vencido, no el futuro ni el inválido', () => {
    expect(excludedReason({ title: 't', modified: '', validUntil: '2026-01-01' }, cfg, now)).toBe('valid_until:2026-01-01');
    expect(excludedReason({ title: 't', modified: '', validUntil: '2027-01-01' }, cfg, now)).toBeUndefined();
    expect(excludedReason({ title: 't', modified: '', validUntil: 'pronto' }, cfg, now)).toBeUndefined();
  });
});

describe('decayFactor (P6)', () => {
  it('sin halfLife no decae', () => {
    expect(decayFactor('2020-01-01', 0, now)).toBe(1);
  });
  it('a una vida media vale 0.5', () => {
    expect(decayFactor('2026-03-03T00:00:00Z', 210, now)).toBeCloseTo(0.5, 2);
  });
  it('fecha inválida o futura no penaliza', () => {
    expect(decayFactor('x', 30, now)).toBe(1);
    expect(decayFactor('2030-01-01', 30, now)).toBe(1);
  });
});

describe('promotionDecision (P5, AC9)', () => {
  const active = { recallAt10: 0.8, mrr: 0.6 };
  it('primera generación se activa sola con cobertura completa', () => {
    expect(promotionDecision({ active: undefined, candidate: undefined, coverage: 1 }).promote).toBe(true);
    expect(promotionDecision({ active: undefined, candidate: undefined, coverage: 0.9 }).promote).toBe(false);
  });
  it('sustituta sin banco de eval solo con force', () => {
    expect(promotionDecision({ active, candidate: undefined, coverage: 1, hasActive: true }).promote).toBe(false);
    expect(promotionDecision({ active, candidate: undefined, coverage: 1, hasActive: true, force: true }).promote).toBe(true);
  });
  it('rechaza si empeora recall@10 o MRR más de 0.02', () => {
    expect(promotionDecision({ active, candidate: { recallAt10: 0.79, mrr: 0.7 }, coverage: 1, hasActive: true }).promote).toBe(false);
    expect(promotionDecision({ active, candidate: { recallAt10: 0.8, mrr: 0.57 }, coverage: 1, hasActive: true }).promote).toBe(false);
    expect(promotionDecision({ active, candidate: { recallAt10: 0.8, mrr: 0.585 }, coverage: 1, hasActive: true }).promote).toBe(true);
  });
});

describe('sloStatus (P7)', () => {
  it('alerta con staleRatio > 0.10, digest distinto o sin generación', () => {
    expect(sloStatus({ enabled: true, hasGeneration: true, totalDocs: 100, pendingDocs: 5, digestMatch: true }).ok).toBe(true);
    const s = sloStatus({ enabled: true, hasGeneration: true, totalDocs: 100, pendingDocs: 11, digestMatch: false });
    expect(s.ok).toBe(false);
    expect(s.staleRatio).toBeCloseTo(0.11);
    expect(s.alerts).toHaveLength(2);
    expect(sloStatus({ enabled: true, hasGeneration: false, totalDocs: 3, pendingDocs: 3, digestMatch: true }).alerts[0]).toMatch(/sin generación/);
    expect(sloStatus({ enabled: false, hasGeneration: false, totalDocs: 3, pendingDocs: 3, digestMatch: true }).ok).toBe(true);
  });
});

describe('resolveRagConfig', () => {
  it('precedencia argumento > dome > env > defaults', () => {
    const env = { SAVIA_RAG_MODEL: 'bge-m3' } as NodeJS.ProcessEnv;
    expect(resolveRagConfig(undefined, env).model).toBe('bge-m3');
    expect(resolveRagConfig({ enabled: true, model: 'granite-embedding:278m' }, env).model).toBe('granite-embedding:278m');
    expect(resolveRagConfig({ enabled: true }, env, { model: 'x' }).model).toBe('x');
    expect(resolveRagConfig(undefined, {}).enabled).toBe(false);
  });
  it('acota parámetros fuera de rango', () => {
    const r = resolveRagConfig({ chunkChars: 10, overlap: 0.9, inlineSyncBudget: -3 }, {});
    expect(r.chunkChars).toBe(200);
    expect(r.overlap).toBe(0.5);
    expect(r.inlineSyncBudget).toBe(0);
  });
});

describe('sloStatus L32 (incidente de cúpulas deshabilitadas)', () => {
  const base = { enabled: true, hasGeneration: true, totalDocs: 598, pendingDocs: 0, digestMatch: true };

  it('staleRatio 0,48 con cúpula deshabilitada pero indexada: ok=false con alerta', () => {
    const s = sloStatus({ ...base, enabled: false, indexed: true, pendingDocs: 288 });
    expect(s.ok).toBe(false);
    expect(s.alerts.join('\n')).toMatch(/rag\.enabled=false/);
    expect(s.alerts.join('\n')).toMatch(/staleRatio 0\.48/);
  });

  it('lagHours por encima del umbral: ok=false aunque staleRatio sea bajo', () => {
    const s = sloStatus({ ...base, pendingDocs: 1, lagHours: 535 });
    expect(s.ok).toBe(false);
    expect(s.alerts.join('\n')).toMatch(/lagHours 535\.0/);
  });

  it('límite: lagHours justo bajo el umbral pasa, en el umbral falla', () => {
    expect(sloStatus({ ...base, pendingDocs: 1, lagHours: LAG_HOURS_ALERT - 0.1 }).ok).toBe(true);
    expect(sloStatus({ ...base, pendingDocs: 1, lagHours: LAG_HOURS_ALERT }).ok).toBe(false);
  });

  it('cúpula deshabilitada y sin índice sigue siendo ok (negativo)', () => {
    expect(sloStatus({ ...base, enabled: false, hasGeneration: false, indexed: false, pendingDocs: 598 }).ok).toBe(true);
  });

  it('cúpula con índice sombra deshabilitada falla aunque no haya activa', () => {
    expect(sloStatus({ ...base, enabled: false, hasGeneration: false, indexed: true }).ok).toBe(false);
  });
});
