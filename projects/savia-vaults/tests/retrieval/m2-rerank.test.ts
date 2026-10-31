// SE-489 M2 — reranker cross-encoder local: reordena el top-N de M0, falla abierto en calidad
// (orden de M0 + aviso + traza) y nunca amplía lo que se lee. Batería de seguridad (AC-2).
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { getRoute, ROUTE_CONTRACT_VERSION } from '../../src/retrieval/route.js';
import { LOAD_RETRY_MS, MEASURE_CAP, RERANK_FALLBACK, keep, setRerankerForTests, takeRerankFallbacks, takeRerankTimings } from '../../src/retrieval/routes/m2-rerank.js';
import { RerankError, loadOnnxCrossEncoder, resolveRerankConfig, scoreInBatches, type RerankScorer } from '../../src/retrieval/rerank/cross-encoder.js';
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
    takeRerankFallbacks();
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

  // El runner también recorta a k, así que se ejerce la ruta sola con un contexto mínimo.
  describe('la ruta devuelve como mucho k hits (sin depender del runner)', () => {
    const mk = (i: number) => ({ dome: 'A', confidentiality: 'N1', path: `p${i}.md`, chunkId: `c${i}`, heading: `h${i}`, text: `t${i}`, score: 1 - i / 100, signals: {}, freshness: { modified: '', decay: 1 }, generation: 'g' }) as never;
    const pool = Array.from({ length: 12 }, (_, i) => mk(i));
    const ctxOf = (asked: number[]) => ({
      candidates: async (_q: string, o?: { k?: number }) => { asked.push(o?.k ?? -1); return pool.slice(0, o?.k ?? 12); },
      consume: () => true, timeLeftMs: () => 10_000, step: () => undefined,
    }) as never;
    const req = (k: number) => ({ route: 'M2', query: 'q', domes: ['A'], mode: 'bm25', k }) as never;
    const ids = (r: { hits: { chunkId: string }[] }) => r.hits.map(h => h.chunkId);

    it('con reranker (k < N): reordena N=10 y devuelve k=3', async () => {
      install(fake((_q, d) => (d === 'h9\nt9' ? 5 : 0)), 10); // el candidato 9 sube al primer puesto
      const asked: number[] = [];
      const r = await getRoute('M2')!.run(req(3), ctxOf(asked));
      expect(asked).toEqual([10]);
      expect(ids(r)).toEqual(['c9', 'c0', 'c1']);
    });

    it('en fallback devuelve exactamente k, igual que M0', async () => {
      install({ id: 'roto', digest: 'b'.repeat(64), score: async () => { throw new Error('boom'); } }, 10);
      const r = await getRoute('M2')!.run(req(3), ctxOf([]));
      expect(ids(r)).toEqual(['c0', 'c1', 'c2']);
      expect(r.warnings).toContain(RERANK_FALLBACK);
    });

    it('sin reranker configurado respeta k y pide solo k a M0', async () => {
      const prev = process.env.SAVIA_RERANK_MODEL_DIR;
      delete process.env.SAVIA_RERANK_MODEL_DIR;
      try {
        const asked: number[] = [];
        const r = await getRoute('M2')!.run(req(3), ctxOf(asked));
        expect(asked).toEqual([3]);
        expect(ids(r)).toEqual(['c0', 'c1', 'c2']);
      } finally { if (prev !== undefined) process.env.SAVIA_RERANK_MODEL_DIR = prev; }
    });
  });

  it('tras un fallo de carga no vuelve a leer el modelo hasta pasado LOAD_RETRY_MS', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'savia-m2-retry-'));
    const saved = { ...process.env };
    try {
      process.env.SAVIA_RERANK_MODEL_DIR = path.join(dir, 'm');
      process.env.SAVIA_RERANK_MODEL_SHA256 = 'a'.repeat(64);
      process.env.SAVIA_RERANK_TOKENIZER_SHA256 = 'b'.repeat(64);
      setRerankerForTests(undefined);
      const reason = async () => (await run()).result.trace.steps.find(s => s.step === 'm2:fallback')?.detail;
      expect(await reason()).toMatch(/ausentes/);
      // El modelo aparece (con digest erróneo): dentro de la ventana sigue el fallo cacheado.
      fs.mkdirSync(path.join(dir, 'm'));
      fs.writeFileSync(path.join(dir, 'm', 'model.onnx'), 'x');
      fs.writeFileSync(path.join(dir, 'm', 'tokenizer.json'), '{}');
      expect(await reason()).toMatch(/ausentes/);
      const real = Date.now;
      Date.now = () => real() + LOAD_RETRY_MS + 1;
      try { expect(await reason()).toMatch(/digest del modelo/); } finally { Date.now = real; }
    } finally {
      for (const k of ['SAVIA_RERANK_MODEL_DIR', 'SAVIA_RERANK_MODEL_SHA256', 'SAVIA_RERANK_TOKENIZER_SHA256']) {
        if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k];
      }
      setRerankerForTests(undefined);
      fs.rmSync(dir, { recursive: true, force: true });
    }
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
      const prev = process.env.SAVIA_RERANK_MODEL_DIR;
      delete process.env.SAVIA_RERANK_MODEL_DIR;
      try { await expectM0Order(/sin-reranker/); } finally { if (prev !== undefined) process.env.SAVIA_RERANK_MODEL_DIR = prev; }
    });

    it('el modelo lanza', async () => {
      install({ id: 'roto', digest: 'b'.repeat(64), score: async () => { throw new Error('boom'); } });
      await expectM0Order(/^error: fallo al puntuar$/);
      expect(takeRerankFallbacks()).toContain('error');
      expect(takeRerankTimings()[0]).toMatchObject({ ok: false });
    });

    it('la traza no filtra rutas ni detalle de la librería; los motivos propios sí salen', async () => {
      install({ id: 'ruta', digest: 'b'.repeat(64), score: async () => { throw new Error('Load model from /home/usuario/m.onnx failed'); } });
      const out = (await run()).result;
      expect(JSON.stringify(out.trace)).not.toContain('/home/usuario');
      install({ id: 'propio', digest: 'b'.repeat(64), score: async () => { throw new RerankError('tiempo del reranker agotado'); } });
      await expectM0Order(/tiempo del reranker agotado/);
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
      expect(takeRerankFallbacks()).toEqual(['presupuesto']);
      // Con una llamada de sobra, sí.
      await run({ mode: 'hybrid', budget: { maxModelCalls: 2 } });
      expect(called).toBe(1);
    });

    it('sin presupuesto de tokens de entrada: cae a M0 y lo cuenta; con presupuesto suficiente puntúa', async () => {
      install(fake((_q, d) => d.length));
      const pocos = (await run({ budget: { maxInputTokens: 5 } })).result;
      expect(pocos.warnings).toContain(RERANK_FALLBACK);
      expect(takeRerankFallbacks()).toEqual(['presupuesto']);
      const bastan = (await run({ budget: { maxInputTokens: 50_000 } })).result;
      expect(bastan.warnings ?? []).not.toContain(RERANK_FALLBACK);
      expect(takeRerankFallbacks()).toEqual([]);
    });

    it('pasa de la latencia del reranker: cae a M0', async () => {
      setRerankerForTests({
        topN: 20, maxMs: 30,
        scorer: { id: 'lento', digest: 'f'.repeat(64), score: async (_q, d, deadline) => { await new Promise(r => setTimeout(r, 60)); if (Date.now() > deadline) throw new RerankError('tiempo del reranker agotado'); return d.map(() => 0); } },
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

describe('SE-489 M2 plazo y registros acotados', () => {
  it('el plazo se comprueba también tras el último lote', async () => {
    const lento = async (d: string[]) => { await new Promise(r => setTimeout(r, 40)); return d.map(() => 1); };
    // Un solo lote que termina fuera de plazo: antes se aceptaba, ahora lanza.
    await expect(scoreInBatches(lento, ['a', 'b'], Date.now() + 10, 8)).rejects.toThrow(/tiempo del reranker/);
    // Dentro de plazo puntúa todos, por lotes.
    await expect(scoreInBatches(async d => d.map(() => 1), ['a', 'b', 'c'], Date.now() + 5000, 2)).resolves.toEqual([1, 1, 1]);
    // Plazo ya vencido: ni empieza.
    let calls = 0;
    await expect(scoreInBatches(async d => { calls++; return d.map(() => 1); }, ['a'], Date.now() - 1)).rejects.toThrow(/tiempo/);
    expect(calls).toBe(0);
  });

  it('los registros de medición tienen tope', () => {
    const log: number[] = [];
    for (let i = 0; i < MEASURE_CAP + 50; i++) keep(log, i);
    expect(log).toHaveLength(MEASURE_CAP);
    expect(log[0]).toBe(50);
    expect(log[log.length - 1]).toBe(MEASURE_CAP + 49);
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
