// SE-489 M1 — padre y vecinos del mismo documento: comportamiento, presupuestos, guard y batería.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { getRoute } from '../../src/retrieval/route.js';
import { describeSecurityBattery } from './security-battery.js';
import { fixture, long, note, rewrite, writeDocs, type Fixture } from './helpers.js';

const contrato = note('Contrato', [
  long('introduccion general del contrato marco'),
  '## Clausula Quinta', long('plazo de entrega zafiro en treinta dias'),
  '### Anexo Tercero', long('penalizacion por retraso del tres por ciento'),
  '### Anexo Cuarto', long('garantia adicional de dos anios'),
  '## Clausula Sexta', long('jurisdiccion de los tribunales'),
].join('\n\n'));

describe('SE-489 M1 — ampliación al padre y vecinos', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A']);
    writeDocs(f.dir('A'), {
      'contrato.md': contrato,
      'otro.md': note('Otro', long('retraso penalizacion tres por ciento en otro asunto')),
      'norma.md': note('Norma', [
        long('preambulo general de la norma'), '## Articulo Uno', long('definiciones generales'),
        '### Apartado A', long('texto del apartado alfa de la norma'), '### Apartado B', long('texto del apartado beta de la norma'), '### Apartado C', long('vigencia quincenal xilofono de la norma'),
      ].join('\n\n')),
    });
    await f.service().sync('A');
  });
  afterEach(() => f.cleanup());

  const q = 'penalizacion retraso tres por ciento';
  const ids = (hits: { chunkId: string }[]) => hits.map(h => h.chunkId);

  it('añade el padre del chunk encontrado, que M0 no devuelve', async () => {
    const svc = f.service();
    const m0 = await runRoute(svc, { route: 'M0', query: q, domes: ['A'], mode: 'bm25', k: 3 });
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 3 });
    // precondición: M0 encuentra el Anexo Tercero pero no su sección padre
    expect(ids(m0.result.hits)).toContain('contrato.md#2');
    expect(ids(m0.result.hits)).not.toContain('contrato.md#1');
    // M1 añade exactamente la Clausula Quinta, tras los hits de M0
    expect(ids(m1.result.hits)).toEqual([...ids(m0.result.hits), 'contrato.md#1']);
    expect(m1.result.hits[2].heading).toBe('Contrato › Clausula Quinta');
    expect(m1.result.evidence.map(e => e.chunkId).sort()).toEqual(ids(m1.result.hits).sort());
    expect(m1.result.trace.steps.some(s => s.step === 'm1:expand')).toBe(true);
  });

  it('el padre se elige antes que los vecinos aunque no sea contiguo', async () => {
    const svc = f.service();
    const m1 = await runRoute(svc, { route: 'M1-c4', query: 'vigencia quincenal xilofono', domes: ['A'], mode: 'bm25', k: 3 });
    const hit = m1.result.hits.find(h => h.heading.endsWith('Apartado C'))!;
    expect(hit).toBeDefined();
    // 1 hueco de ampliación (floor(3/3)): ocupa el padre (Articulo Uno), no el vecino Apartado B
    const added = m1.result.hits.filter(h => h.path === 'norma.md' && h.chunkId !== hit.chunkId);
    expect(added.map(h => h.heading)).toEqual(['Norma › Articulo Uno']);
  });

  it('no devuelve más de k hits aunque haya huecos de ampliación', async () => {
    const svc = f.service();
    for (const k of [1, 2, 3, 6, 12]) {
      const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k });
      expect(m1.result.hits.length).toBeLessThanOrEqual(k);
    }
  });

  it('conserva la posición de los ceil(k/2) primeros hits de M0 (k=4: los 2 primeros)', async () => {
    const svc = f.service();
    const m0 = await runRoute(svc, { route: 'M0', query: q, domes: ['A'], mode: 'bm25', k: 4 });
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 4 });
    expect(ids(m1.result.hits).slice(0, 2)).toEqual(ids(m0.result.hits).slice(0, 2));
  });

  it('perDoc: M1 (2 por documento) no pasa de 2; M1-c4 puede pasar', async () => {
    const svc = f.service();
    const per = (r: Awaited<ReturnType<typeof runRoute>>) => {
      const m = new Map<string, number>();
      for (const h of r.result.hits) m.set(h.path, (m.get(h.path) ?? 0) + 1);
      return Math.max(...m.values());
    };
    const c2 = await runRoute(svc, { route: 'M1', query: q, domes: ['A'], mode: 'bm25', k: 9 });
    const c4 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 9 });
    expect(per(c2)).toBeLessThanOrEqual(2);
    expect(per(c4)).toBeGreaterThan(2);
    expect(per(c4)).toBeLessThanOrEqual(4);
  });

  it('maxHops 0: sin ampliación, igual que M0', async () => {
    const svc = f.service();
    const m0 = await runRoute(svc, { route: 'M0', query: q, domes: ['A'], mode: 'bm25', k: 9 });
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 9, budget: { maxHops: 0 } });
    expect(ids(m1.result.hits)).toEqual(ids(m0.result.hits));
    expect(m1.result.consumed.hops).toBe(0);
  });

  it('maxHops 1 añade padre y vecino; maxHops 2 añade además el abuelo', async () => {
    const svc = f.service();
    const h1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 12, budget: { maxHops: 1 } });
    const h2 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 12, budget: { maxHops: 2 } });
    expect(ids(h1.result.hits)).toEqual(['contrato.md#2', 'otro.md#0', 'contrato.md#1', 'contrato.md#3']);
    expect(ids(h2.result.hits)).toEqual([...ids(h1.result.hits), 'contrato.md#0']);
    expect(h1.result.consumed.hops).toBe(1);
    expect(h2.result.consumed.hops).toBe(2);
  });

  it('maxNodes agotado: no abre documentos y sirve lo que ya tenía, con aviso', async () => {
    const svc = f.service();
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 9, budget: { maxNodes: 3 } });
    expect(m1.result.consumed.nodes).toBeLessThanOrEqual(3);
    expect(m1.result.warnings).toContain('BUDGET_EXHAUSTED');
  });

  it('no sirve un chunk añadido si la nota se borra tras el sync', async () => {
    const svc = f.service();
    fs.rmSync(path.join(f.dir('A'), 'contrato.md'));
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 9 });
    expect(m1.result.hits.every(h => h.path !== 'contrato.md')).toBe(true);
  });

  it('un chunk de una nota reclasificada a N4 no se amplía', async () => {
    const svc = f.service();
    rewrite(path.join(f.dir('A'), 'contrato.md'), contrato.replace('title: Contrato\n', 'title: Contrato\nconfidentiality: N4\n'));
    const m1 = await runRoute(svc, { route: 'M1-c4', query: q, domes: ['A'], mode: 'bm25', k: 9 });
    expect(m1.result.hits.every(h => h.path !== 'contrato.md')).toBe(true);
    expect(m1.result.evidence.every(e => e.document !== 'contrato.md')).toBe(true);
  });

  it('declara su contrato y variantes', () => {
    for (const id of ['M1', 'M1-c3', 'M1-c4']) {
      expect(getRoute(id)).toMatchObject({ id, supportsAsOf: false, requiresDeclaredBudget: false });
    }
  });
});

for (const route of ['M1', 'M1-c4']) describeSecurityBattery({ route });
