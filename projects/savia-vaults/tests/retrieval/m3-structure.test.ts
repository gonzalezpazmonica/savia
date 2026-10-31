// SE-489 M3 — navegación determinista sobre el StructureIndex: secciones citadas, sección del hit,
// anexos del mismo directorio; presupuesto de saltos, estado y guard. Batería de seguridad (AC-2).
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { MAX_SIBLINGS, ROUTE_CONTRACT_VERSION, getRoute, registerRoute, unregisterRoute, type RetrievalRequest, type RouteContext } from '../../src/retrieval/route.js';
import { M3_STRUCTURE, structuralCues } from '../../src/retrieval/routes/m3-structure.js';
import type { RagHit } from '../../src/rag/types.js';
import { describeSecurityBattery } from './security-battery.js';
import { fixture, long, note, writeDocs, type Fixture } from './helpers.js';

/** Ruta de prueba que solo ejecuta `body` con el contexto real del runner. */
let probes = 0;
function createProbe(body: (ctx: RouteContext) => Promise<void>): string {
  const id = `M3probe${probes++}`;
  registerRoute({
    id, description: 'sonda', contractVersion: ROUTE_CONTRACT_VERSION, supportsAsOf: false, requiresDeclaredBudget: false,
    async run(_req, ctx) { await body(ctx); return { hits: [] }; },
  });
  return id;
}

const CONTRATO = note('Contrato CT-1', [
  '## Cláusula 1. Objeto', long('servicio de custodia de copias'),
  '## Cláusula 3. Precio', long('el precio anual es el de la tabla de tarifas'),
  '## Cláusula 5. Penalizaciones', 'Cada hora de retraso sobre el tiempo de respuesta del Anexo I genera una penalización del 1,25 % de la cuota mensual.',
].join('\n\n'));
const ANEXO_I = note('Anexo I', '# Anexo I — Tiempos de respuesta\n\n| Severidad | Tiempo |\n|---|---|\n| S1 | 1 h |\n| S2 | 4 h |');
const ANEXO_II = note('Anexo II', '# Anexo II — Tarifas\n\n| Tramo | Precio |\n|---|---|\n| A | 1411 EUR |');

describe('structuralCues', () => {
  it('reconoce anexo, cláusula, artículo, sección y § con números romanos o arábigos', () => {
    expect(structuralCues('¿Qué dice la cláusula 5 y el Anexo II del contrato?')).toEqual(['anexo 2', 'clausula 5']);
    expect(structuralCues('artículo 3, § 4.2 y sección IV')).toEqual(['articulo 3', 'seccion 4', '§ 4.2']);
    expect(structuralCues('anexo i')).toEqual(['anexo 1']);
    expect(structuralCues('sin referencias estructurales')).toEqual([]);
    // «I» suelta o «anexos» sin número no son referencias.
    expect(structuralCues('yo y los anexos')).toEqual([]);
  });
});

describe('SE-489 M3 — navegación por estructura', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A']);
    writeDocs(f.dir('A'), {
      'contratos/CT-1/contrato.md': CONTRATO,
      'contratos/CT-1/anexo-I.md': ANEXO_I,
      'contratos/CT-1/anexo-II.md': ANEXO_II,
      // Otro contrato con su propio Anexo I: no es hermano del CT-1 y no se sigue.
      'contratos/CT-2/contrato.md': note('Contrato CT-2', long('otro contrato sin penalizaciones')),
      'contratos/CT-2/anexo-I.md': note('Anexo I', '# Anexo I — Tiempos de CT-2\n\n| S1 | 9 h |'),
    });
    await f.service().sync('A');
  });
  afterEach(() => f.cleanup());

  const run = (query: string, extra: Record<string, unknown> = {}) =>
    runRoute(f.service(), { route: 'M3', query, domes: ['A'], mode: 'bm25', k: 10, ...extra });

  it('está registrada, no exige presupuesto declarado y no admite asOf', () => {
    const r = getRoute('M3');
    expect(r).toBe(M3_STRUCTURE);
    expect(r.requiresDeclaredBudget).toBe(false);
    expect(r.supportsAsOf).toBe(false);
  });

  it('sigue la referencia «Anexo I» de la sección hallada al anexo del mismo contrato (M0 no lo recupera)', async () => {
    const q = 'penalización por hora de retraso cuota mensual';
    const m0 = await runRoute(f.service(), { route: 'M0', query: q, domes: ['A'], mode: 'bm25', k: 10 });
    expect(m0.result.hits.some(h => h.path === 'contratos/CT-1/anexo-I.md')).toBe(false);
    const out = await run(q);
    const paths = out.result.hits.map(h => h.path);
    expect(paths[0]).toBe('contratos/CT-1/contrato.md');
    expect(paths).toContain('contratos/CT-1/anexo-I.md');
    expect(paths).not.toContain('contratos/CT-2/anexo-I.md');
    // Solo el anexo citado: el II no aparece en la sección de penalizaciones.
    expect(paths).not.toContain('contratos/CT-1/anexo-II.md');
    const anexo = out.result.hits.find(h => h.path === 'contratos/CT-1/anexo-I.md')!;
    expect(anexo.text).toContain('| S1 | 1 h |');
    // Cada hit lleva su evidencia, y el salto cuenta en el presupuesto y en la traza.
    expect(out.result.evidence.map(e => e.chunkId)).toEqual(out.result.hits.map(h => h.chunkId));
    expect(out.result.consumed.hops).toBe(1);
    expect(out.result.trace.steps.map(s => s.step)).toContain('m3:annex');
  });

  it('una sección citada en la consulta trae sus unidades al documento', async () => {
    const out = await run('cláusula 3 del contrato CT-1 servicio de custodia');
    const c3 = out.result.hits.find(h => h.heading.endsWith('Cláusula 3. Precio'));
    expect(c3).toBeDefined();
    expect(out.result.trace.steps.map(s => s.step)).toContain('m3:section');
  });

  it('con maxHops 0 no salta a otros documentos', async () => {
    const out = await run('penalización por hora de retraso cuota mensual', { budget: { maxHops: 0 } });
    expect(out.result.hits.map(h => h.path)).not.toContain('contratos/CT-1/anexo-I.md');
    expect(out.result.consumed.hops).toBe(0);
  });

  it('un anexo excluido por estado no se sigue salvo includeStale', async () => {
    writeDocs(f.dir('A'), { 'contratos/CT-1/anexo-I.md': note('Anexo I', '# Anexo I — Tiempos\n\n| S1 | 1 h |', 'status: deprecated\n') });
    await f.service().sync('A');
    const q = 'penalización por hora de retraso cuota mensual';
    expect((await run(q)).result.hits.map(h => h.path)).not.toContain('contratos/CT-1/anexo-I.md');
    expect((await run(q, { includeStale: true })).result.hits.map(h => h.path)).toContain('contratos/CT-1/anexo-I.md');
  });

  it('un anexo reclasificado por encima de la cúpula (sin sync) no se abre ni se revela', async () => {
    fs.writeFileSync(path.join(f.dir('A'), 'contratos/CT-1/anexo-I.md'), note('Anexo I', '# Anexo I\n\n| S1 | 1 h |', 'confidentiality: N4\n'));
    const out = await run('penalización por hora de retraso cuota mensual');
    expect(JSON.stringify(out)).not.toContain('anexo-I');
    expect(JSON.stringify(out)).not.toContain('| S1 | 1 h |');
  });

  it('determinista: dos ejecuciones dan los mismos hits', async () => {
    const q = 'penalización por hora de retraso cuota mensual';
    const a = await run(q);
    const b = await run(q);
    expect(b.result.hits).toEqual(a.result.hits);
  });
});

describe('SE-489 M3 — línea base y directorios grandes', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A']);
    const docs: Record<string, string> = {};
    for (let i = 0; i < 120; i++) {
      docs[`specs/SE-${100 + i}.md`] = note(`SE-${100 + i}`, `## Criterios\n\n${long(`criterio ${i} de la especificacion ${i % 7} sobre gobierno y despliegue`)}\n\n## Riesgos\n\n${long(`riesgo ${i} medio`)}`);
    }
    writeDocs(f.dir('A'), docs);
    await f.service().sync('A');
  });
  afterEach(() => f.cleanup());

  it('sin señales estructurales devuelve exactamente los hits de M0 (mismo k en la fusión híbrida)', async () => {
    for (const q of ['criterio de gobierno y despliegue', 'riesgo medio de la especificacion 3', 'criterio 42']) {
      const m0 = await runRoute(f.service(), { route: 'M0', query: q, domes: ['A'], mode: 'hybrid', k: 10 });
      const m3 = await runRoute(f.service(), { route: 'M3', query: q, domes: ['A'], mode: 'hybrid', k: 10 });
      expect(m3.result.hits.map(h => h.chunkId)).toEqual(m0.result.hits.map(h => h.chunkId));
    }
  });

  it('en un directorio de 120 documentos no lista hermanos si no hay referencias (no agota maxNodes)', async () => {
    const out = await runRoute(f.service(), { route: 'M3', query: 'criterio de gobierno y despliegue', domes: ['A'], mode: 'bm25', k: 10 });
    expect(out.result.warnings ?? []).not.toContain('BUDGET_EXHAUSTED');
    // 10 candidatos + 1 árbol y 1 lectura de chunks por documento navegado (5): muy por debajo de 120.
    expect(out.result.consumed.nodes).toBeLessThanOrEqual(10 + 2 * 5);
  });

  it('documentStructure solo lista hermanos si se piden, con tope y 1 nodo por hermano', async () => {
    let seen: { plain?: number; asked?: number; capped?: number } = {};
    const probe = createProbe(async (ctx) => {
      const ref = { dome: 'A', path: 'specs/SE-100.md' };
      seen = {
        plain: ctx.documentStructure!(ref)!.siblings.length,
        asked: ctx.documentStructure!(ref, { maxSiblings: 5 })!.siblings.length,
        capped: ctx.documentStructure!(ref, { maxSiblings: 10_000 })!.siblings.length,
      };
    });
    const out = await runRoute(f.service(), { route: probe, query: 'x', domes: ['A'], mode: 'bm25', k: 1 });
    expect(seen).toEqual({ plain: 0, asked: 5, capped: MAX_SIBLINGS });
    expect(out.result.consumed.nodes).toBe(3 + 5 + MAX_SIBLINGS);
    unregisterRoute(probe);
  });
});

describe('SE-489 M3 — degradación sin estructura', () => {
  const hit = (path: string, chunkId: string): RagHit => ({
    dome: 'A', confidentiality: 'N2', path, chunkId, heading: 'T', text: 't', score: 1, signals: {}, freshness: { modified: '', decay: 1 }, generation: 'g',
  });
  const req = { query: 'cláusula 5', domes: [{ name: 'A', confidentiality: 'N2' }], k: 5, mode: 'bm25', seed: 0, budget: { maxLatencyMs: 1000, maxModelCalls: 1, maxNodes: 50, maxHops: 2, maxInputTokens: 100 }, budgetDeclared: false } as RetrievalRequest;

  it('sin documentStructure en el contexto devuelve los candidatos tal cual y avisa', async () => {
    const cands = [hit('a.md', 'a.md#0'), hit('b.md', 'b.md#0')];
    const steps: string[] = [];
    const ctx: RouteContext = {
      candidates: async () => cands, openNote: () => undefined, documentChunks: () => undefined,
      consume: () => true, timeLeftMs: () => 1000, step: (s) => { steps.push(s); }, evidenceOf: () => undefined,
    };
    const out = await M3_STRUCTURE.run(req, ctx);
    expect(out.hits).toEqual(cands);
    expect(out.warnings).toEqual(['STRUCTURE_UNAVAILABLE']);
  });

  it('sin candidatos no abre nada', async () => {
    let opened = 0;
    const ctx: RouteContext = {
      candidates: async () => [], openNote: () => { opened++; return undefined; }, documentChunks: () => { opened++; return undefined; },
      documentStructure: () => { opened++; return undefined; },
      consume: () => true, timeLeftMs: () => 1000, step: () => {}, evidenceOf: () => undefined,
    };
    expect((await M3_STRUCTURE.run(req, ctx)).hits).toEqual([]);
    expect(opened).toBe(0);
  });
});

describeSecurityBattery({ route: 'M3' });
