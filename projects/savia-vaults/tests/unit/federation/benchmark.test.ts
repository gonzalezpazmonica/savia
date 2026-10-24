// SE-395 R01: dataset congelado, métricas y baseline reproducible (sin red).
import { describe, it, expect, vi, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { generateDataset, DEFAULT_SEED } from '../../../src/federation/benchmark/generate.js';
import { validateDataset } from '../../../src/federation/benchmark/validate.js';
import { runBaseline } from '../../../src/federation/benchmark/baseline.js';
import { buildAll, syncFrozen } from '../../../src/federation/benchmark/freeze.js';
import { canonicalJson, sha256Json } from '../../../src/federation/benchmark/canon.js';
import { mean, mrr, ndcgAtK, percentile, precisionAtK, ratio, recallAtK, tokenCount } from '../../../src/federation/benchmark/metrics.js';
import { BENCH_PROFILE, GATE_THRESHOLDS, STRATA } from '../../../src/federation/benchmark/types.js';
import { FederatedSearchEngine } from '../../../src/federation/search.js';
import { FederationRegistry } from '../../../src/federation/registry.js';
import type { SearchEngine } from '../../../src/search/index.js';

const evalDir = path.resolve(import.meta.dirname, '../../../eval/adaptive');
const frozen = (name: string): unknown => JSON.parse(fs.readFileSync(path.join(evalDir, name), 'utf-8'));
const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));

afterEach(() => { vi.unstubAllGlobals(); });

describe('metrics', () => {
  it('denominador cero es N/A, no mejora ficticia', () => {
    expect(recallAtK(['a'], [], 5)).toBeNull();
    expect(precisionAtK([], ['a'], 5)).toBeNull();
    expect(mrr(['a'], [])).toBeNull();
    expect(ndcgAtK(['a'], [], 5)).toBeNull();
    expect(ratio(3, 0)).toBeNull();
    expect(mean([null, null])).toBeNull();
    expect(percentile([], 0.95)).toBeNull();
  });
  it('valores conocidos', () => {
    expect(recallAtK(['x', 'a', 'b'], ['a', 'b', 'c'], 3)).toBeCloseTo(2 / 3);
    expect(recallAtK(['x', 'a', 'b'], ['a', 'b', 'c'], 1)).toBe(0);
    expect(precisionAtK(['a', 'x'], ['a'], 2)).toBe(0.5);
    expect(mrr(['x', 'y', 'a'], ['a'])).toBeCloseTo(1 / 3);
    expect(mrr(['x'], ['a'])).toBe(0);
    expect(ndcgAtK(['a', 'b'], ['a', 'b'], 2)).toBeCloseTo(1);
    expect(ndcgAtK(['x', 'a'], ['a'], 2)).toBeCloseTo(1 / Math.log2(3));
    expect(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.95)).toBe(10);
    expect(percentile([1, 2, 3, 4], 0.5)).toBe(2);
  });
});

describe('dataset', () => {
  it('cumple el contrato: >=180 consultas, >=20 por estrato, familias disjuntas entre splits', () => {
    const { corpus, dataset } = generateDataset();
    expect(validateDataset(corpus, dataset)).toEqual([]);
    expect(dataset.queries.length).toBeGreaterThanOrEqual(180);
    for (const s of STRATA) expect(dataset.queries.filter(q => q.stratum === s).length).toBeGreaterThanOrEqual(20);
  });
  it('cada estrato aparece en train, calibration y test', () => {
    const { dataset } = generateDataset();
    for (const s of STRATA) for (const split of ['train', 'calibration', 'test']) {
      expect(dataset.queries.some(q => q.stratum === s && q.split === split), `${s}/${split}`).toBe(true);
    }
  });
  it('es determinista por semilla', () => {
    expect(sha256Json(generateDataset(DEFAULT_SEED).dataset)).toBe(sha256Json(generateDataset(DEFAULT_SEED).dataset));
    expect(sha256Json(generateDataset(DEFAULT_SEED + 1).corpus)).not.toBe(sha256Json(generateDataset(DEFAULT_SEED).corpus));
  });
  it('incluye casos donde el baseline gana y estratos restringidos con documentos prohibidos', () => {
    const { dataset } = generateDataset();
    expect(dataset.queries.some(q => q.baselineAdvantage)).toBe(true);
    const restricted = dataset.queries.filter(q => q.stratum === 'restricted');
    expect(restricted.every(q => q.forbidden.length > 0 && q.allowedVaults.length < 4)).toBe(true);
  });
  it('rechaza violaciones del contrato (casos negativos)', () => {
    const { corpus, dataset } = generateDataset();
    const short = clone(dataset); short.queries = short.queries.filter(q => q.stratum !== 'stale' || q.id.endsWith('00'));
    expect(validateDataset(corpus, short).join('\n')).toMatch(/estrato stale/);
    const twoSplits = clone(dataset); const i = twoSplits.queries.findIndex(q => q.family === twoSplits.queries[0].family && q.id !== twoSplits.queries[0].id);
    twoSplits.queries[i].split = twoSplits.queries[i].split === 'test' ? 'train' : 'test';
    expect(validateDataset(corpus, twoSplits).join('\n')).toMatch(/dos splits/);
    const leak = clone(dataset); const r = leak.queries.find(q => q.stratum === 'restricted')!; r.relevant.push(r.forbidden[0]);
    expect(validateDataset(corpus, leak).join('\n')).toMatch(/relevante y prohibido/);
    const ghost = clone(dataset); ghost.queries[0].relevant.push('nope/none.md');
    expect(validateDataset(corpus, ghost).join('\n')).toMatch(/documento desconocido/);
    const empty = clone(dataset); empty.queries[0].relevant = []; empty.queries[0].useful = [];
    expect(validateDataset(corpus, empty).join('\n')).toMatch(/relevant vacío/);
    const staleDoc = corpus.docs.find(d => d.stale)!;
    const staleRel = clone(dataset); staleRel.queries[0].relevant.push(staleDoc.id);
    expect(validateDataset(corpus, staleRel).join('\n')).toMatch(/obsoleto marcado como relevante/);
    const badPair = clone(corpus); badPair.conflictPairs.push(['x/none.md', 'y/none.md']);
    const badPairDs = clone(dataset); badPairDs.corpusSha256 = sha256Json(badPair);
    expect(validateDataset(badPair, badPairDs).join('\n')).toMatch(/conflictPair con documento desconocido/);
    const noTest = clone(dataset); noTest.queries = noTest.queries.filter(q => !(q.stratum === 'new' && q.split === 'test'));
    expect(validateDataset(corpus, noTest).join('\n')).toMatch(/estrato new sin consultas en test/);
    const tampered = clone(corpus); tampered.docs[0].text += ' x';
    expect(validateDataset(tampered, dataset).join('\n')).toMatch(/corpusSha256/);
  });
});

describe('baseline offline', () => {
  it('no abre red y es reproducible', async () => {
    const fetchSpy = vi.fn(() => { throw new Error('red prohibida en el benchmark'); });
    vi.stubGlobal('fetch', fetchSpy);
    const { corpus, dataset } = generateDataset();
    const a = await runBaseline(corpus, dataset);
    const b = await runBaseline(corpus, dataset);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(canonicalJson(a.report)).toBe(canonicalJson(b.report));
  }, 60000);

  it('cero exposición, provenance íntegro y warm sin llamadas remotas', async () => {
    const { corpus, dataset } = generateDataset();
    const { report, metrics } = await runBaseline(corpus, dataset);
    for (const m of metrics) expect(m.exposed, m.queryId).toBe(0);
    expect(report.overall.cold.provenance).toBe(1);
    expect(report.overall.cold.remoteCalls).toBeGreaterThan(0);
    expect(report.overall.warm.remoteCalls).toBe(0);
    expect(report.overall.warm.recallAtK).toBe(report.overall.cold.recallAtK);
    expect(report.overall.warm.latencyP95).toBe(0);
    expect(report.overall.cold.latencyP95!).toBeGreaterThan(0);
  }, 60000);

  it('la latencia warm se mide: sin cache efectivo hay llamadas remotas y latencia > 0', async () => {
    const { corpus, dataset } = generateDataset();
    const { report } = await runBaseline(corpus, dataset, { cacheTtlMs: -1 });
    expect(report.overall.warm.remoteCalls).toBeGreaterThan(0);
    expect(report.overall.warm.latencyP95!).toBeGreaterThan(0);
  }, 60000);

  it('provenance se mide: una atribución falsa de source la baja y cuenta como exposición', async () => {
    const { corpus, dataset } = generateDataset();
    const { report } = await runBaseline(corpus, dataset, { tamperResult: r => ({ ...r, source: 'local' }) });
    expect(report.overall.cold.provenance!).toBeLessThan(1);
  }, 60000);

  it('ranking y tokens se evalúan sobre el mismo top-k', async () => {
    const { corpus, dataset } = generateDataset();
    const k = 3;
    const maxDocTokens = Math.max(...corpus.docs.map(d => tokenCount(d.text)));
    const { metrics } = await runBaseline(corpus, dataset, { profile: { ...BENCH_PROFILE, k } });
    for (const m of metrics) expect(m.retrievedTokens, m.queryId).toBeLessThanOrEqual(k * maxDocTokens);
  }, 60000);

  it('el baseline degrada donde debe: vault no sano baja el recall y restringido no filtra', async () => {
    const { corpus, dataset } = generateDataset();
    const { report } = await runBaseline(corpus, dataset);
    expect(report.byStratum.unhealthy.cold.recallAtK!).toBeLessThan(report.byStratum.monodomain.cold.recallAtK!);
    expect(report.byStratum.restricted.cold.exposed).toBe(0);
    expect(report.byStratum.ambiguous.cold.precisionAtK!).toBeLessThan(report.byStratum.repeated.cold.precisionAtK!);
  }, 60000);

  it('rechaza un corpus que no coincide con el dataset', async () => {
    const { corpus, dataset } = generateDataset();
    const tampered = clone(corpus); tampered.docs[0].text += ' x';
    await expect(runBaseline(tampered, dataset)).rejects.toThrow(/corpus no coincide/);
  });
});

describe('artefactos congelados', () => {
  it('umbrales preregistrados: el hash fijado en el test no cambia sin tocar este test', () => {
    expect(sha256Json(GATE_THRESHOLDS)).toBe('02d8eefe2c059bd03e7e1d4edfb6ee2aaebee792f87dc841d3a4f390e071a7b3');
  });
  it('syncFrozen detecta deriva, falta de fichero y no la da si coincide', () => {
    const dir = fs.mkdtempSync(path.join(fs.realpathSync(process.env.TMPDIR ?? '/tmp'), 'se395-freeze-'));
    try {
      expect(syncFrozen(dir, { 'a.json': { x: 1 } }, false)).toEqual(['a.json']);
      expect(syncFrozen(dir, { 'a.json': { x: 1 } }, true)).toEqual([]);
      expect(syncFrozen(dir, { 'a.json': { x: 1 } }, false)).toEqual([]);
      expect(syncFrozen(dir, { 'a.json': { x: 2 } }, false)).toEqual(['a.json']);
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  });
  it('eval/adaptive coincide con lo regenerado (corpus, dataset, baseline, freeze)', async () => {
    const { corpus, dataset } = generateDataset();
    const { report, freeze } = await buildAll(corpus, dataset);
    expect(frozen('corpus.json')).toEqual(JSON.parse(canonicalJson(corpus)));
    expect(frozen('dataset.json')).toEqual(JSON.parse(canonicalJson(dataset)));
    expect(frozen('baseline.json')).toEqual(JSON.parse(canonicalJson(report)));
    expect(frozen('freeze.json')).toEqual(JSON.parse(canonicalJson(freeze)));
  }, 60000);
  it('mutar una etiqueta cambia el hash del dataset', () => {
    const { dataset } = generateDataset();
    const mutated = clone(dataset); mutated.queries[0].relevant = [];
    expect(sha256Json(mutated)).not.toBe(sha256Json(dataset));
  });
});

describe('FederatedSearchEngine con cliente inyectado', () => {
  it('usa el cliente inyectado y nunca fetch', async () => {
    const fetchSpy = vi.fn(() => { throw new Error('fetch no debe llamarse'); });
    vi.stubGlobal('fetch', fetchSpy);
    const dir = fs.mkdtempSync(path.join(fs.realpathSync(process.env.TMPDIR ?? '/tmp'), 'se395-seam-'));
    try {
      const registry = new FederationRegistry(dir);
      registry.add({ id: 'r1', name: 'R1', url: 'http://x.invalid', timeout: 100, enabled: true, weight: 1, tags: [], status: 'healthy' });
      const search = vi.fn(async () => ({ results: [{ path: 'r1/a.md', score: 1, snippet: 's', tags: [], source: 'r1', contentHash: 'h1' }], status: 'ok' as const, latencyMs: 5 }));
      const local = { search: () => [] } as unknown as SearchEngine;
      const engine = new FederatedSearchEngine(local, registry, { client: { search, healthCheck: vi.fn() } as never });
      const res = await engine.search('q', { principalId: 'p', policyRevision: '1', contentRevision: '1', allowedDomeIds: ['r1'] });
      expect(search).toHaveBeenCalledTimes(1);
      expect(res.results.map(r => r.path)).toEqual(['r1/a.md']);
      expect(fetchSpy).not.toHaveBeenCalled();
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  });
});
