// SE-395 R04: A/B aislado, regla de decisión y suite adversarial (AC17, AC18, AC19, AC20).
import { describe, it, expect } from 'vitest';
import { generateDataset } from '../../../src/federation/benchmark/generate.js';
import { runBaseline } from '../../../src/federation/benchmark/baseline.js';
import { compare, makeRouter, pairedBootstrap, runAb, trainGuidance, DECISION_RULES } from '../../../src/federation/benchmark/ab.js';
import { selectDestinations } from '../../../src/federation/adaptive/select.js';
import { parseGuidance } from '../../../src/federation/adaptive/guidance.js';
import type { QueryMetrics } from '../../../src/federation/benchmark/types.js';

const row = (i: number, o: Partial<QueryMetrics> = {}): QueryMetrics => ({
  queryId: `q${String(i).padStart(3, '0')}`, stratum: 'monodomain', split: 'test', cache: 'cold', recallAtK: 1, precisionAtK: 0.5, mrr: 1, ndcgAtK: 1,
  attempts: 3, remoteCalls: 3, latencyMs: 100, retrievedTokens: 100, irrelevantTokens: 60, usefulTokens: 20, usefulDensity: 0.2, duplicates: 0, conflictsSurfaced: 0, provenanceOk: 1, exposed: 0, ...o,
});
const rows = (n: number, o: Partial<QueryMetrics> = {}) => Array.from({ length: n }, (_, i) => row(i, o));
const good: Partial<QueryMetrics> = { remoteCalls: 1, attempts: 1, irrelevantTokens: 30, retrievedTokens: 60, usefulTokens: 20 };

describe('regla de decisión', () => {
  it('GO solo con todos los gates y muestra suficiente', () => {
    const r = compare(rows(DECISION_RULES.minPairs), rows(DECISION_RULES.minPairs, good), 'test');
    expect(r.decision).toBe('GO');
  });
  it('mismos datos con muestra insuficiente: NEEDS_MORE_EVIDENCE, no GO', () => {
    expect(compare(rows(20), rows(20, good), 'test').decision).toBe('NEEDS_MORE_EVIDENCE');
  });
  it('NO_GO con muestra suficiente si falla la no-inferioridad de recall', () => {
    const r = compare(rows(120), rows(120, { ...good, recallAtK: 0.5 }), 'test');
    expect(r.decision).toBe('NO_GO');
    expect(r.gates.find(g => g.name === 'recallDeltaCiLow')!.pass).toBe(false);
  });
  it('exposición > 0 es NO_GO aunque la muestra sea mínima', () => {
    const r = compare(rows(5), rows(5, { ...good, exposed: 1 }), 'test');
    expect(r.decision).toBe('NO_GO');
  });
  it('denominador cero en recall se informa N/A y no mejora', () => {
    const r = compare(rows(120, { recallAtK: null }), rows(120, { ...good, recallAtK: null }), 'test');
    expect(r.recallDelta.mean).toBeNull();
    expect(r.decision).toBe('NEEDS_MORE_EVIDENCE');
  });
  it('conjuntos distintos (otro snapshot) lanzan error', () => {
    expect(() => compare(rows(10), rows(9), 'test')).toThrow(/snapshot/);
  });
  it('bootstrap determinista por semilla', () => {
    const d = [0, -0.1, 0.2, -0.3, 0];
    expect(pairedBootstrap(d)).toEqual(pairedBootstrap(d));
    expect(pairedBootstrap([])).toEqual({ mean: null, ciLow: null, ciHigh: null });
  });
});

describe('A/B sobre el benchmark congelado', () => {
  const { corpus, dataset } = generateDataset();
  it('el router solo ve consulta, policy y salud; la guidance sale solo de train', () => {
    const tok = (t: string): string[] => t.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
    const topicsOf = (split: string): Set<string> => new Set(dataset.queries.filter(q => q.split === split).map(q => q.family));
    const vocab = (topics: Set<string>): Set<string> => new Set(corpus.docs.filter(d => topics.has(d.topic)).flatMap(d => tok(d.text)));
    const trainVocab = vocab(topicsOf('train'));
    // Vocabulario exclusivo de test: aparece en docs de tópicos de test y nunca en los de train.
    const testOnly = new Set([...vocab(topicsOf('test'))].filter(t => !trainVocab.has(t)));
    const attracts = (g: ReturnType<typeof trainGuidance>): string[] => g.cues.flatMap(c => c.attracts.map(a => a.term));
    const g = trainGuidance(corpus, dataset);
    expect(testOnly.size).toBeGreaterThan(0);
    expect(attracts(g).length).toBeGreaterThan(0);
    expect(attracts(g).filter(t => testOnly.has(t))).toEqual([]);
    // La guidance es función solo de train: reentrenada sin las consultas de test, es idéntica.
    const trainOnly = { ...dataset, queries: dataset.queries.filter(q => q.split === 'train') };
    expect(trainGuidance(corpus, trainOnly)).toEqual(g);
    // Control negativo: si las consultas de test se etiquetan como train, la fuga SÍ se detecta.
    const leaked = { ...dataset, queries: dataset.queries.map(q => ({ ...q, split: 'train' as const })) };
    expect(attracts(trainGuidance(corpus, leaked)).filter(t => testOnly.has(t)).length).toBeGreaterThan(0);
  });
  it('makeRouter aborta si la guidance cae a fallback (no mide otra cosa en silencio)', () => {
    const q = dataset.queries[0];
    const ok = makeRouter(corpus, trainGuidance(corpus, dataset));
    expect(() => ok(q)).not.toThrow();
    const tooMany = { version: 1, cues: Array.from({ length: 33 }, (_, i) => ({ vaultId: `v${i}`, attracts: [], repels: [], specialties: [] })) };
    expect(() => makeRouter(corpus, tooMany)(q)).toThrow(/modo adaptive/);
  });
  it('nunca consulta fuera de la policy ni excede el presupuesto (exposición 0)', async () => {
    const base = await runBaseline(corpus, dataset);
    const chal = await runBaseline(corpus, dataset, { route: makeRouter(corpus, trainGuidance(corpus, dataset)) });
    expect(chal.metrics.reduce((s, m) => s + m.exposed, 0)).toBe(0);
    expect(Math.max(...chal.metrics.map(m => m.remoteCalls))).toBeLessThanOrEqual(3);
    const route = makeRouter(corpus, trainGuidance(corpus, dataset));
    for (const q of dataset.queries) {
      const picked = route(q);
      expect(picked.length).toBeLessThanOrEqual(3);
      expect(picked.every(id => q.allowedVaults.includes(id))).toBe(true);
    }
    expect(chal.metrics.reduce((s, m) => s + m.remoteCalls, 0)).toBeLessThan(base.metrics.reduce((s, m) => s + m.remoteCalls, 0));
  });
  it('control negativo: un router que ignora la policy SÍ es detectado como exposición', async () => {
    const leaky = await runBaseline(corpus, dataset, { route: () => ['local', 'beta', 'gamma', 'delta'] });
    expect(leaky.metrics.reduce((s, m) => s + m.exposed, 0)).toBeGreaterThan(0);
  });
  it('desactivar el router restaura exactamente el baseline', async () => {
    const base = await runBaseline(corpus, dataset);
    const remoteIds = [...new Set(dataset.queries.flatMap(q => q.allowedVaults))].filter(id => id !== 'local').sort();
    const off = await runBaseline(corpus, dataset, {
      route: q => selectDestinations({
        query: q.query, allowedDomeIds: q.allowedVaults, guidance: null, budget: { maxVaults: 99, maxRemoteCalls: 99 }, flags: {},
        domes: remoteIds.map(id => ({ id, weight: 1, status: q.unhealthyVaults.includes(id) ? 'unhealthy' as const : 'healthy' as const, enabled: true })),
      }).selected,
    });
    expect(off.report).toEqual(base.report);
    // Control negativo: un router que descarta destinos sí cambia el informe (el test puede fallar).
    const broken = await runBaseline(corpus, dataset, { route: q => q.allowedVaults.slice(0, 1) });
    expect(broken.report).not.toEqual(base.report);
  });
  it('resultado del holdout preregistrado: el challenger estático NO supera el gate', async () => {
    const r = await runAb(corpus, dataset, 'test');
    expect(r.decision).not.toBe('GO');
    expect(r.recallDelta.ciHigh!).toBeLessThan(-0.02);
  });
});

describe('suite adversarial', () => {
  const dome = (id: string, weight = 1, status: 'healthy' | 'unhealthy' = 'healthy') => ({ id, weight, status, enabled: true });
  const sel = (o: object) => selectDestinations({ query: 'cifrado claves', allowedDomeIds: ['local', 'a', 'b', 'c'], domes: [dome('a'), dome('b'), dome('c')], guidance: { version: 1, cues: [] }, budget: { maxVaults: 3, maxRemoteCalls: 3 }, flags: { adaptive: true }, ...o });
  it('specialty=everything no es comodín: solo cuenta si coincide un término de la consulta', () => {
    const r = sel({ guidance: { version: 1, cues: [{ vaultId: 'c', specialties: ['everything'] }] } });
    expect(r.mode).toBe('adaptive');
    expect(typeof r.scores.c).toBe('number');
    expect(r.scores.c).toBe(r.scores.a);
    // Control positivo: una especialidad presente en la consulta sí sube el score (la aserción anterior puede fallar).
    const hit = sel({ guidance: { version: 1, cues: [{ vaultId: 'c', specialties: ['cifrado'] }] } });
    expect(hit.mode).toBe('adaptive');
    expect(hit.scores.c).toBeGreaterThan(hit.scores.a);
  });
  it('trust/peso falso en metadata remota se rechaza (campo desconocido)', () => {
    expect(parseGuidance({ version: 1, cues: [{ vaultId: 'a', trust: 'high', weight: 99 }] }).ok).toBe(false);
  });
  it('atracción máxima no puede resucitar un destino denegado ni uno BLOCKED por policy', () => {
    const r = sel({ allowedDomeIds: ['local', 'a'], guidance: { version: 1, cues: [{ vaultId: 'b', attracts: [{ term: 'cifrado', score: 1 }], specialties: ['claves'] }] } });
    expect(r.selected).toEqual(['local', 'a']);
  });
  it('destino no sano dominante en cues no entra', () => {
    const r = sel({ domes: [dome('a'), dome('b', 1, 'unhealthy'), dome('c')], guidance: { version: 1, cues: [{ vaultId: 'b', attracts: [{ term: 'cifrado', score: 1 }] }] } });
    expect(r.selected).not.toContain('b');
  });
  it('un cue sobre un vault no registrado (ciclo/relay) no añade destinos: un salto, solo registrados', () => {
    const r = sel({ guidance: { version: 1, cues: [{ vaultId: 'fantasma', attracts: [{ term: 'cifrado', score: 1 }] }] } });
    expect(r.selected.every(id => ['local', 'a', 'b', 'c'].includes(id))).toBe(true);
  });
  it('explosión de ramas: nunca más destinos que el presupuesto, con muchos vaults', () => {
    const many = Array.from({ length: 50 }, (_, i) => dome(`v${String(i).padStart(2, '0')}`));
    const r = sel({ domes: many, allowedDomeIds: ['local', ...many.map(d => d.id)] });
    expect(r.selected.length).toBeLessThanOrEqual(3);
  });
  it('empate total: resultado estable entre ejecuciones', () => {
    expect(sel({})).toEqual(sel({}));
  });
});
