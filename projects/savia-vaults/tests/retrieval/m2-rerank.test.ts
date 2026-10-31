// SE-489 M2 — reranker cross-encoder local: reordena el top-N de M0, falla abierto en calidad
// (orden de M0 + aviso + traza) y nunca amplía lo que se lee. Batería de seguridad (AC-2).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { getRoute, ROUTE_CONTRACT_VERSION } from '../../src/retrieval/route.js';
import { RERANK_FALLBACK, setRerankerForTests, takeRerankTimings } from '../../src/retrieval/routes/m2-rerank.js';
import { loadOnnxCrossEncoder, resolveRerankConfig, type RerankScorer } from '../../src/retrieval/rerank/cross-encoder.js';
import { describeSecurityBattery } from './security-battery.js';
import { fixture, long, note, writeDocs, type Fixture } from './helpers.js';

/** Puntúa por una función del texto: determinista y sin modelo. */
const fake = (f: (q: string, d: string) => number, id = 'fake'): RerankScorer => ({
  id, digest: 'a'.repeat(64), score: async (q, docs) => docs.map(d => f(q, d)),
});
const install = (scorer: RerankScorer, topN = 20) => setRerankerForTests({ scorer, topN, maxMs: 4000 });

describe('SE-489 M2 reranker', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A', 'B']);
    writeDocs(f.dir('A'), {
      'reglas/seguridad.md': note('Seguridad', long('los agentes nocturnos nunca fusionan en main sin permiso')),
      'reglas/ramas.md': note('Ramas', long('los agentes nocturnos trabajan en ramas propias')),
      'reglas/honestidad.md': note('Honestidad', long('los agentes dan malas noticias sin adornos')),
    });
    writeDocs(f.dir('B'), { 'otra.md': note('Otra', long('los agentes de la otra cúpula nocturnos')) });
    await f.service().sync('A');
    await f.service().sync('B');
    takeRerankTimings();
  });
  afterEach(() => { f.cleanup(); setRerankerForTests(undefined); });

  const run = (extra: Record<string, unknown> = {}) =>
    runRoute(f.service(), { route: 'M2', query: 'agentes nocturnos', domes: ['A'], mode: 'bm25', k: 10, ...extra });
  const m0 = () => runRoute(f.service(), { route: 'M0', query: 'agentes nocturnos', domes: ['A'], mode: 'bm25', k: 10 });

  it('declara su contrato', () => {
    expect(getRoute('M2')).toMatchObject({ id: 'M2', contractVersion: ROUTE_CONTRACT_VERSION, requiresDeclaredBudget: false });
  });

  it('reordena según el scorer y conserva el mismo conjunto de hits', async () => {
    const base = (await m0()).result.hits;
    expect(base.length).toBeGreaterThan(2);
    const weight = (d: string) => (d.includes('malas noticias') ? 3 : d.includes('fusionan') ? 2 : d.includes('ramas propias') ? 1 : 0);
    install(fake((_q, d) => weight(d)));
    const out = (await run()).result;
    const want = ['reglas/honestidad.md#0', 'reglas/seguridad.md#0', 'reglas/ramas.md#0'];
    // La prueba solo vale si M0 no devolvía ya ese orden.
    expect(base.map(h => h.chunkId).slice(0, 3)).not.toEqual(want);
    expect(out.hits.map(h => h.chunkId).slice(0, 3)).toEqual(want);
    expect(new Set(out.hits.map(h => h.chunkId))).toEqual(new Set(base.map(h => h.chunkId)));
    expect(out.trace.steps.map(s => s.step)).toContain('m2:rerank');
    expect(out.warnings ?? []).not.toContain(RERANK_FALLBACK);
    expect(out.consumed.modelCalls).toBe(1);
    const t = takeRerankTimings();
    expect(t).toHaveLength(1);
    expect(t[0]).toMatchObject({ ok: true, pairs: base.length });
  });

  it('la traza no lleva tiempos: dos ejecuciones dan la misma traza', async () => {
    install({ id: 'var', digest: 'a'.repeat(64), score: async (_q, d) => { await new Promise(r => setTimeout(r, Math.random() * 20)); return d.map(x => x.length); } });
    const a = (await run()).result.trace;
    const b = (await run()).result.trace;
    expect(a).toEqual(b);
  });

  it('empates conservan el orden de M0', async () => {
    install(fake(() => 1));
    expect((await run()).result.hits.map(h => h.chunkId)).toEqual((await m0()).result.hits.map(h => h.chunkId));
  });

  it('solo reordena el top-N y deja el resto en su sitio', async () => {
    const base = (await m0()).result.hits;
    install(fake((_q, d) => -d.length), 2); // N = 2
    const out = (await run()).result.hits.map(h => h.chunkId);
    expect(out.slice(2)).toEqual(base.slice(2).map(h => h.chunkId));
    expect(new Set(out.slice(0, 2))).toEqual(new Set(base.slice(0, 2).map(h => h.chunkId)));
  });

  describe('fail-open en calidad', () => {
    const expectM0Order = async (why: RegExp) => {
      const out = (await run()).result;
      expect(out.hits.map(h => h.chunkId)).toEqual((await m0()).result.hits.map(h => h.chunkId));
      expect(out.warnings).toContain(RERANK_FALLBACK);
      const step = out.trace.steps.find(s => s.step === 'm2:fallback');
      expect(step?.detail).toMatch(why);
    };

    it('sin reranker configurado', async () => {
      const env = { ...process.env };
      delete process.env.SAVIA_RERANK_MODEL_DIR;
      try { await expectM0Order(/sin-reranker/); } finally { process.env = env; }
    });

    it('el modelo lanza', async () => {
      install({ id: 'roto', digest: 'b'.repeat(64), score: async () => { throw new Error('boom'); } });
      await expectM0Order(/error: boom/);
      expect(takeRerankTimings()[0]).toMatchObject({ ok: false });
    });

    it('puntuaciones inválidas (NaN o longitud errónea)', async () => {
      install({ id: 'nan', digest: 'c'.repeat(64), score: async (_q, docs) => docs.map(() => NaN) });
      await expectM0Order(/no válidas/);
      install({ id: 'corto', digest: 'd'.repeat(64), score: async () => [1] });
      await expectM0Order(/no válidas/);
    });

    it('sin presupuesto de llamadas a modelo: no llama al reranker', async () => {
      let called = 0;
      install({ id: 'cuenta', digest: 'e'.repeat(64), score: async (_q, d) => { called++; return d.map(() => 0); } });
      // En híbrido, los candidatos ya gastan la única llamada.
      const out = (await run({ mode: 'hybrid', budget: { maxModelCalls: 1 } })).result;
      expect(called).toBe(0);
      expect(out.warnings).toContain(RERANK_FALLBACK);
      expect(out.trace.steps.find(s => s.step === 'm2:fallback')?.detail).toBe('presupuesto');
      // Con una llamada de sobra, sí.
      await run({ mode: 'hybrid', budget: { maxModelCalls: 2 } });
      expect(called).toBe(1);
    });

    it('pasa de la latencia del reranker: cae a M0', async () => {
      setRerankerForTests({
        topN: 20, maxMs: 30,
        scorer: { id: 'lento', digest: 'f'.repeat(64), score: async (_q, d, deadline) => { await new Promise(r => setTimeout(r, 60)); if (Date.now() > deadline) throw new Error('tiempo del reranker agotado'); return d.map(() => 0); } },
      });
      await expectM0Order(/tiempo/);
    });
  });

  it('no abre nada que M0 no abriera: cúpula denegada sigue sin aparecer', async () => {
    f.denied.add('B');
    install(fake(() => 1));
    const out = await run({ domes: ['A', 'B'] });
    expect(out.result.hits.every(h => h.dome === 'A')).toBe(true);
    expect(out.domes.find(d => d.name === 'B')?.status).toBe('denied');
  });
});

describe('SE-489 M2 configuración y carga por digest', () => {
  it('exige modelo, digests y N válido', () => {
    const sha = 'a'.repeat(64);
    expect(resolveRerankConfig({})).toMatchObject({ ok: false });
    expect(resolveRerankConfig({ SAVIA_RERANK_MODEL_DIR: '/m' })).toMatchObject({ ok: false });
    expect(resolveRerankConfig({ SAVIA_RERANK_MODEL_DIR: '/m', SAVIA_RERANK_MODEL_SHA256: sha, SAVIA_RERANK_TOKENIZER_SHA256: 'zz' })).toMatchObject({ ok: false });
    const base = { SAVIA_RERANK_MODEL_DIR: '/m', SAVIA_RERANK_MODEL_SHA256: sha, SAVIA_RERANK_TOKENIZER_SHA256: sha };
    expect(resolveRerankConfig({ ...base, SAVIA_RERANK_TOPN: '51' })).toMatchObject({ ok: false });
    expect(resolveRerankConfig({ ...base, SAVIA_RERANK_TOPN: '0' })).toMatchObject({ ok: false });
    expect(resolveRerankConfig({ ...base, SAVIA_RERANK_TOPN: '50' })).toMatchObject({ ok: true, config: { topN: 50 } });
    expect(resolveRerankConfig(base)).toMatchObject({ ok: true, config: { topN: 20, maxMs: 4000 } });
  });

  it('rechaza un modelo cuyo digest no coincide con el fijado', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m2-'));
    try {
      fs.writeFileSync(path.join(dir, 'model.onnx'), 'no soy un modelo');
      fs.writeFileSync(path.join(dir, 'tokenizer.json'), '{}');
      const h = (s: string) => crypto.createHash('sha256').update(s).digest('hex');
      const cfg = { modelDir: dir, topN: 20, maxMs: 1000, modelSha256: 'a'.repeat(64), tokenizerSha256: h('{}') };
      await expect(loadOnnxCrossEncoder(cfg)).rejects.toThrow(/digest del modelo/);
      // Con el digest correcto del modelo la comprobación pasa y falla después, al no ser ONNX válido.
      await expect(loadOnnxCrossEncoder({ ...cfg, modelSha256: h('no soy un modelo') })).rejects.not.toThrow(/digest/);
      await expect(loadOnnxCrossEncoder({ ...cfg, modelSha256: h('no soy un modelo'), tokenizerSha256: 'b'.repeat(64) })).rejects.toThrow(/digest del tokenizador/);
      await expect(loadOnnxCrossEncoder({ ...cfg, modelDir: path.join(dir, 'nada') })).rejects.toThrow(/ausentes/);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

// Modelo real (solo si está fijado en el entorno): puntúa mejor el pasaje relevante.
const realCfg = resolveRerankConfig();
describe.skipIf(!realCfg.ok)('SE-489 M2 modelo ONNX real', () => {
  it('ordena el pasaje relevante por encima del irrelevante', async () => {
    const s = await loadOnnxCrossEncoder((realCfg as { ok: true; config: Parameters<typeof loadOnnxCrossEncoder>[0] }).config);
    const [rel, irr] = await s.score('¿Cuál es la capital de Francia?', ['París es la capital de Francia.', 'El gato duerme en el sofá.'], Date.now() + 60_000);
    expect(rel).toBeGreaterThan(irr);
  }, 120_000);
});

describe('SE-489 M2 batería de seguridad', () => {
  beforeAll(() => install(fake((_q, d) => d.length)));
  afterAll(() => setRerankerForTests(undefined));
  describeSecurityBattery({ route: 'M2' });
  describeSecurityBattery({ route: 'M2', mode: 'hybrid' });
});
