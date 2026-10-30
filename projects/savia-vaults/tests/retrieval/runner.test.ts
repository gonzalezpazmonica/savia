// SE-489 — runner de rutas: plano de control, guard final, presupuesto declarado (AC-7), as_of
// y forma de la respuesta.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { AS_OF_UNSUPPORTED, ROUTE_CONTRACT_VERSION, registerRoute, unregisterRoute, type RetrievalRoute } from '../../src/retrieval/route.js';
import type { RagHit } from '../../src/rag/types.js';
import { fixture, long, note, writeDocs, type Fixture } from './helpers.js';

const route = (id: string, run: RetrievalRoute['run'], extra: Partial<RetrievalRoute> = {}): RetrievalRoute => ({
  id, description: 'test', contractVersion: ROUTE_CONTRACT_VERSION, supportsAsOf: false, requiresDeclaredBudget: false, run, ...extra,
});

describe('SE-489 runRoute', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A', 'S']);
    writeDocs(f.dir('A'), { 'uno.md': note('Uno', long('gavilán colirrojo del norte')), 'dos.md': note('Dos', long('mirlo acuático')) });
    writeDocs(f.dir('S'), { 'secreto.md': note('Secreto', long('gavilán colirrojo reservado')) });
    await f.service().sync('A');
    await f.service().sync('S');
  });
  afterEach(() => {
    for (const id of ['Tleak', 'Tbudget', 'Tasof', 'Tforge', 'Tspin']) unregisterRoute(id);
    f.cleanup();
  });

  it('las cúpulas autorizadas las fija el plano de control; la denegada se declara sin contenido', async () => {
    f.denied.add('S');
    let seen: string[] = [];
    registerRoute(route('Tspin', async (req, ctx) => { seen = req.domes.map(d => d.name); return { hits: await ctx.candidates(req.query) }; }));
    const out = await runRoute(f.service(), { route: 'Tspin', query: 'gavilán colirrojo', domes: ['A', 'S'], mode: 'bm25' });
    expect(seen).toEqual(['A']);
    expect(out.domes.find(d => d.name === 'S')).toEqual({ name: 'S', status: 'denied', detail: 'acceso denegado' });
    expect(JSON.stringify(out.result)).not.toMatch(/secreto|reservado/);
    expect(out.result.hits.every(h => h.dome === 'A')).toBe(true);
  });

  it('el guard final descarta hits que una ruta fabrica fuera de lo autorizado', async () => {
    f.denied.add('S');
    // Ruta maliciosa: inventa hits de S y de una nota inexistente sin pasar por el contexto.
    registerRoute(route('Tforge', async () => ({
      hits: [
        { dome: 'S', path: 'secreto.md', chunkId: 'secreto.md#0', heading: 'Secreto', text: 'reservado' } as RagHit,
        { dome: 'A', path: 'fantasma.md', chunkId: 'fantasma.md#0', heading: 'x', text: 'x' } as RagHit,
      ],
      evidence: [{ chunkId: 'secreto.md#0', dome: 'S', document: 'secreto.md', revision: 'r', locator: '#0', contentHash: 'h' }],
    })));
    const out = await runRoute(f.service(), { route: 'Tforge', query: 'x', domes: ['A', 'S'], mode: 'bm25' });
    expect(out.result.hits).toEqual([]);
    expect(out.result.evidence).toEqual([]);
    expect(out.result.trace.denied).toBeGreaterThanOrEqual(2);
    expect(JSON.stringify(out)).not.toMatch(/secreto|reservado/);
  });

  it('el guard final descarta un hit autorizado con texto, encabezado o fuente sustituidos', async () => {
    f.denied.add('S');
    let original: RagHit[] = [];
    registerRoute(route('Tforge', async (req, ctx) => {
      original = await ctx.candidates(req.query);
      const h = original[0];
      return {
        hits: [
          { ...h, text: 'texto que no está en la nota' },
          { ...h, chunkId: `${h.path}#0`, heading: 'Encabezado inventado' },
          { ...h, source: { kind: 'file', documentId: 'x', revisionId: 'r', name: 'n', locator: { type: 'page', page: 1 } } },
          { ...h, freshness: { ...h.freshness, status: 'inventado', supersededBy: 'otra' } },
        ],
        warnings: ['texto libre con secreto', 'CODIGO_VALIDO'],
      };
    }));
    const out = await runRoute(f.service(), { route: 'Tforge', query: 'gavilán colirrojo', domes: ['A'], mode: 'bm25' });
    expect(out.result.hits).toHaveLength(1);
    expect(out.result.hits[0].freshness.status).toBeUndefined();
    expect(out.result.hits[0].freshness.supersededBy).toBeUndefined();
    expect(out.result.warnings).toEqual(['CODIGO_VALIDO']);
    expect(out.result.trace.steps).toContainEqual({ step: 'guard:final', nodes: 3 });
  });

  it('cada hit servido lleva su evidencia', async () => {
    registerRoute(route('Tspin', async (req, ctx) => ({ hits: await ctx.candidates(req.query) })));
    const out = await runRoute(f.service(), { route: 'Tspin', query: 'mirlo acuático', domes: ['A'], mode: 'bm25' });
    expect(out.result.hits.length).toBeGreaterThan(0);
    expect(out.result.evidence.map(e => e.chunkId)).toEqual(out.result.hits.map(h => h.chunkId));
    expect(out.result.evidence[0]).toMatchObject({ dome: 'A', document: 'dos.md' });
  });

  it('AC-7: una ruta que exige presupuesto declarado no corre sin él', async () => {
    let ran = false;
    registerRoute(route('Tbudget', async () => { ran = true; return { hits: [] }; }, { requiresDeclaredBudget: true }));
    await expect(runRoute(f.service(), { route: 'Tbudget', query: 'x', domes: ['A'] })).rejects.toThrow(/BUDGET_REQUIRED/);
    expect(ran).toBe(false);
    await runRoute(f.service(), { route: 'Tbudget', query: 'x', domes: ['A'], budget: { maxModelCalls: 2 } });
    expect(ran).toBe(true);
  });

  it('el presupuesto de nodos limita lo que la ruta puede abrir', async () => {
    let opened = 0;
    registerRoute(route('Tspin', async (_req, ctx) => {
      for (let i = 0; i < 10; i++) if (ctx.openNote({ dome: 'A', path: 'uno.md' })) opened++;
      return { hits: [] };
    }));
    const out = await runRoute(f.service(), { route: 'Tspin', query: 'x', domes: ['A'], budget: { maxNodes: 3 } });
    expect(opened).toBe(3);
    expect(out.result.consumed.nodes).toBe(3);
    expect(out.result.warnings).toContain('BUDGET_EXHAUSTED');
  });

  it('as_of en una ruta que no lo soporta ⇒ aviso, no silencio', async () => {
    registerRoute(route('Tasof', async () => ({ hits: [] })));
    const out = await runRoute(f.service(), { route: 'Tasof', query: 'x', domes: ['A'], asOf: '2026-01-01' });
    expect(out.result.warnings).toContain(AS_OF_UNSUPPORTED);
    const plain = await runRoute(f.service(), { route: 'Tasof', query: 'x', domes: ['A'] });
    expect(plain.result.warnings ?? []).not.toContain(AS_OF_UNSUPPORTED);
  });

  it.each([['2026-13-40'], ['ayer'], [42]])('as_of inválido %j ⇒ INVALID_INPUT', async (asOf) => {
    registerRoute(route('Tasof', async () => ({ hits: [] })));
    await expect(runRoute(f.service(), { route: 'Tasof', query: 'x', domes: ['A'], asOf: asOf as string })).rejects.toThrow(/INVALID_INPUT/);
  });

  it('semilla no entera ⇒ INVALID_INPUT; la semilla queda en la traza', async () => {
    registerRoute(route('Tspin', async () => ({ hits: [] })));
    await expect(runRoute(f.service(), { route: 'Tspin', query: 'x', domes: ['A'], seed: 1.5 })).rejects.toThrow(/INVALID_INPUT/);
    const out = await runRoute(f.service(), { route: 'Tspin', query: 'x', domes: ['A'], seed: 7 });
    expect(out.result.trace).toMatchObject({ route: 'Tspin', seed: 7, reason: 'explicit' });
  });

  it('ruta desconocida ⇒ UNKNOWN_ROUTE', async () => {
    await expect(runRoute(f.service(), { route: 'NoHay', query: 'x', domes: ['A'] })).rejects.toThrow(/UNKNOWN_ROUTE/);
  });

  it('una ruta que excede maxLatencyMs se corta y no sirve nada', async () => {
    registerRoute(route('Tleak', async (req, ctx) => {
      const hits = await ctx.candidates(req.query);
      await new Promise(r => setTimeout(r, 400));
      return { hits };
    }));
    const out = await runRoute(f.service(), { route: 'Tleak', query: 'gavilán', domes: ['A'], mode: 'bm25', budget: { maxLatencyMs: 150 } });
    expect(out.result.hits).toEqual([]);
    expect(out.result.warnings).toContain('BUDGET_EXHAUSTED');
  });

  it('documentChunks devuelve los chunks del índice del documento admitido; nada de lo denegado', async () => {
    f.denied.add('S');
    let mine: unknown, theirs: unknown;
    registerRoute(route('Tspin', async (_req, ctx) => {
      mine = ctx.documentChunks({ dome: 'A', path: 'uno.md' });
      theirs = ctx.documentChunks({ dome: 'S', path: 'secreto.md' });
      return { hits: [] };
    }));
    await runRoute(f.service(), { route: 'Tspin', query: 'x', domes: ['A', 'S'] });
    expect((mine as { text: string }[]).length).toBeGreaterThan(0);
    expect((mine as { text: string }[])[0].text).toContain('gavilán');
    expect(theirs).toBeUndefined();
  });

  it('documentChunks tras borrar la nota (sin sync) ⇒ nada', async () => {
    fs.rmSync(path.join(f.dir('A'), 'uno.md'));
    let got: unknown = 'sin llamar';
    registerRoute(route('Tspin', async (_req, ctx) => { got = ctx.documentChunks({ dome: 'A', path: 'uno.md' }); return { hits: [] }; }));
    await runRoute(f.service(), { route: 'Tspin', query: 'x', domes: ['A'] });
    expect(got).toBeUndefined();
  });
});
