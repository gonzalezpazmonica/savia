// SE-489 M5 — grafo de referencias: expansión por saltos con visited, profundidad y guard por salto;
// los ciclos terminan; una revisión superseded no se sirve como vigente con un asOf posterior.
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as path from 'node:path';
import { runRoute } from '../../src/retrieval/runner.js';
import { getRoute } from '../../src/retrieval/route.js';
import { currency, M5_MAX_DOCS, M5_MAX_ID_LOOKUPS } from '../../src/retrieval/routes/m5-graph.js';
import { describeSecurityBattery } from './security-battery.js';
import { fixture, long, note, rewrite, writeDocs, type Fixture } from './helpers.js';

const rev = (n: number, extra: string, months: number): string =>
  note(`NRM-0412 revisión ${n}`, `## Artículo 3. Plazo de conservación\n\n${long(`registros de servicio se conservan durante ${months} meses`)}`, extra);

function norma(f: Fixture): void {
  writeDocs(f.dir('A'), {
    'normas/rev-1.md': rev(1, 'effective_from: 2022-01-01\neffective_to: 2024-04-15\nsuperseded_by: normas/rev-2.md\nstatus: superseded\n', 12),
    'normas/rev-2.md': rev(2, 'effective_from: 2024-04-15\neffective_to: 2025-10-01\nsupersedes: normas/rev-1.md\nsuperseded_by: normas/rev-3.md\nstatus: superseded\n', 24),
    'normas/rev-3.md': rev(3, 'effective_from: 2025-10-01\nsupersedes: normas/rev-2.md\nstatus: active\n', 36),
  });
}

const paths = (o: Awaited<ReturnType<typeof runRoute>>): string[] => o.result.hits.map(h => h.path);

describe('SE-489 M5 — revisiones y asOf', () => {
  let f: Fixture;
  beforeEach(async () => { f = fixture(['A']); norma(f); await f.service().sync('A'); });
  afterEach(() => f.cleanup());
  const ask = (extra: Record<string, unknown>) => runRoute(f.service(), {
    route: 'M5', query: 'plazo de conservación de registros de servicio', domes: ['A'], mode: 'bm25', k: 8, ...extra,
  });

  it.each([
    ['2023-02-22', 'normas/rev-1.md'],
    ['2024-04-14', 'normas/rev-1.md'],
    ['2024-04-15', 'normas/rev-2.md'],
    ['2025-01-07', 'normas/rev-2.md'],
    ['2025-10-01', 'normas/rev-3.md'],
    ['2026-06-01', 'normas/rev-3.md'],
  ])('asOf %s sirve solo %s', async (asOf, expected) => {
    const out = await ask({ asOf, budget: { maxHops: 2 } });
    expect([...new Set(paths(out))]).toEqual([expected]);
    expect(out.result.warnings ?? []).not.toContain('AS_OF_UNSUPPORTED');
  });

  it('una revisión superseded no se sirve como vigente con un asOf posterior', async () => {
    const out = await ask({ asOf: '2026-06-01', budget: { maxHops: 2 }, includeStale: true });
    expect(paths(out)).not.toContain('normas/rev-1.md');
    expect(paths(out)).not.toContain('normas/rev-2.md');
    expect(out.result.evidence.every(e => e.document === 'normas/rev-3.md')).toBe(true);
  });

  it('asOf anterior a la primera revisión: se abstiene y no sirve nada', async () => {
    const out = await ask({ asOf: '2021-01-01', budget: { maxHops: 2 } });
    expect(out.result.hits).toEqual([]);
    expect(out.result.abstain).toBe(true);
  });

  it('el alcance de saltos limita la cadena: con 1 salto no llega a rev-1', async () => {
    const out = await ask({ asOf: '2023-02-22', budget: { maxHops: 1 } });
    expect(paths(out)).not.toContain('normas/rev-1.md');
    expect(out.result.consumed.hops).toBeLessThanOrEqual(1);
  });

  it('sin asOf no sirve revisiones superseded (como M0); con includeStale, sí', async () => {
    expect([...new Set(paths(await ask({ budget: { maxHops: 2 } })))]).toEqual(['normas/rev-3.md']);
    const all = new Set(paths(await ask({ budget: { maxHops: 2 }, includeStale: true })));
    expect(all.has('normas/rev-3.md')).toBe(true);
  });

  it('sin fechas que decidan, una superseded con asOf no se sirve (cierre seguro)', async () => {
    writeDocs(f.dir('A'), {
      'sin-fechas/viejo.md': note('Viejo', long('protocolo de guardia vigente'), 'status: superseded\nsuperseded_by: sin-fechas/nuevo.md\n'),
      'sin-fechas/nuevo.md': note('Nuevo', long('protocolo de guardia nuevo'), 'supersedes: sin-fechas/viejo.md\n'),
    });
    await f.service().sync('A');
    const out = await runRoute(f.service(), { route: 'M5', query: 'protocolo de guardia', domes: ['A'], mode: 'bm25', asOf: '2026-01-01', includeStale: true });
    expect(paths(out)).not.toContain('sin-fechas/viejo.md');
  });
});

describe('SE-489 M5 — currency (umbral de fechas)', () => {
  const m = (o: Partial<Parameters<typeof currency>[0]['meta']>) => ({ meta: { supersedes: [], supersededBy: [], hasTemporal: true, ...o } });
  it('la ventana es [from, to): el límite superior excluye', () => {
    const w = m({ from: Date.parse('2024-01-01'), to: Date.parse('2025-01-01') });
    expect(currency(w, [], Date.parse('2024-12-31'), false)).toBe('current');
    expect(currency(w, [], Date.parse('2025-01-01'), false)).toBe('ended');
    expect(currency(w, [], Date.parse('2023-12-31'), false)).toBe('future');
  });
  it('superseded_by sin sucesor leído: desconocido', () => {
    expect(currency(m({ supersededBy: ['x.md'] }), [], Date.parse('2026-01-01'), false)).toBe('unknown');
  });
  it('el sucesor fija el fin cuando no hay effective_to', () => {
    const succ = { supersedes: [], supersededBy: [], hasTemporal: true, from: Date.parse('2025-01-01') };
    expect(currency(m({ supersededBy: ['x.md'] }), [succ], Date.parse('2025-01-02'), false)).toBe('ended');
    expect(currency(m({ supersededBy: ['x.md'] }), [succ], Date.parse('2024-12-31'), false)).toBe('current');
  });
});

describe('SE-489 M5 — expansión, ciclos y guard', () => {
  let f: Fixture;
  beforeEach(() => { f = fixture(['A']); });
  afterEach(() => f.cleanup());
  const ask = (query: string, extra: Record<string, unknown> = {}) => runRoute(f.service(), { route: 'M5', query, domes: ['A'], mode: 'bm25', k: 8, ...extra });

  it('sigue un wikilink hasta una nota que M0 no devolvió con k pequeño', async () => {
    writeDocs(f.dir('A'), {
      'inicio.md': note('Inicio', long('zorzal alirrojo invernada') + '\n\nDetalle en [[destino]].'),
      'destino.md': note('Destino', long('anexo técnico del zorzal en el comedero')),
      ...Object.fromEntries([1, 2, 3, 4].map(i => [`ruido-${i}.md`, note(`Ruido ${i}`, long('zorzal alirrojo invernada zorzal'))])),
    });
    await f.service().sync('A');
    const m0 = await runRoute(f.service(), { route: 'M0', query: 'zorzal alirrojo invernada', domes: ['A'], mode: 'bm25', k: 3 });
    const m5 = await ask('zorzal alirrojo invernada', { k: 8, budget: { maxHops: 1 } });
    expect(paths(m0)).not.toContain('destino.md');
    expect(paths(m5)).toContain('destino.md');
    expect(m5.result.consumed.hops).toBe(1);
  });

  it('maxHops 0 no expande: solo las semillas de M0', async () => {
    writeDocs(f.dir('A'), {
      'inicio.md': note('Inicio', long('zorzal alirrojo invernada') + '\n\n[[destino]]'),
      'destino.md': note('Destino', long('anexo técnico del zorzal')),
    });
    await f.service().sync('A');
    const out = await ask('zorzal alirrojo invernada', { k: 1, budget: { maxHops: 0 } });
    expect(paths(out)).toEqual(['inicio.md']);
  });

  it('un ciclo de wikilinks y supersedes termina sin repetir hits y sin pasar de maxHops', async () => {
    writeDocs(f.dir('A'), {
      'a.md': note('A', long('alcotán europeo') + '\n\n[[b]] [[a]]', 'supersedes: c.md\n'),
      'b.md': note('B', long('alcotán europeo segundo') + '\n\n[[c]]', 'superseded_by: a.md\n'),
      'c.md': note('C', long('alcotán europeo tercero') + '\n\n[[a]] [[b]]', 'superseded_by: b.md\n'),
    });
    await f.service().sync('A');
    const out = await ask('alcotán europeo', { includeStale: true, budget: { maxHops: 8, maxNodes: 50 } });
    const ids = out.result.hits.map(h => h.chunkId);
    expect(new Set(ids).size).toBe(ids.length);
    expect(out.result.trace.steps.some(s => s.step === 'budget' && s.detail === 'maxLatencyMs')).toBe(false);
    // 3 notas: tras agotar los vecinos nuevos el recorrido para, no gasta los 8 saltos.
    expect(out.result.consumed.hops).toBeLessThanOrEqual(3);
    expect(out.result.consumed.nodes).toBeLessThanOrEqual(3 + 3 + 3);
  });

  it('un autovínculo y un vínculo repetido no reabren la nota', async () => {
    writeDocs(f.dir('A'), { 'solo.md': note('Solo', long('gavilán común') + '\n\n[[solo]] [[solo]] [[solo.md]]') });
    await f.service().sync('A');
    const out = await ask('gavilán común', { budget: { maxHops: 4, maxNodes: 50 } });
    expect(out.result.consumed.nodes).toBeLessThanOrEqual(2 + 1);
  });

  it('resuelve un ID de spec a su nota', async () => {
    writeDocs(f.dir('A'), {
      'informe.md': note('Informe', long('verderón serrano migración') + '\n\nCumple lo de SE-777.'),
      'specs/SE-777-pasillo.md': note('SE-777 pasillo', long('pasillo ecológico de montaña')),
    });
    await f.service().sync('A');
    const out = await ask('verderón serrano', { k: 8, budget: { maxHops: 1 } });
    // El destino no comparte términos con la consulta: no es semilla; solo el ID lo alcanza.
    const m0 = await runRoute(f.service(), { route: 'M0', query: 'verderón serrano', domes: ['A'], mode: 'bm25', k: 8 });
    expect(paths(m0)).not.toContain('specs/SE-777-pasillo.md');
    expect(out.result.trace.steps.find(st => st.step === 'm5:graph')?.detail).toBe('docs=2');
  });

  it('un vínculo a una nota reclasificada o en cuarentena no la sirve ni deja rastro', async () => {
    writeDocs(f.dir('A'), {
      'puente.md': note('Puente', long('curruca capirotada') + '\n\n[[reservada]] [[rota]] [[../../etc/passwd]]'),
      'reservada.md': note('Reservada', long('curruca capirotada RESERVADA-Q9')),
      'rota.md': note('Rota', long('curruca capirotada ROTA-Q8')),
    });
    await f.service().sync('A');
    rewrite(path.join(f.dir('A'), 'reservada.md'), note('Reservada', long('curruca capirotada RESERVADA-Q9'), 'confidentiality: N4\n'));
    rewrite(path.join(f.dir('A'), 'rota.md'), note('Rota', long('curruca capirotada ROTA-Q8'), 'confidentiality: N9\n'));
    const out = await ask('curruca capirotada', { budget: { maxHops: 2 } });
    const s = JSON.stringify(out);
    expect(s).not.toContain('RESERVADA-Q9');
    expect(s).not.toContain('ROTA-Q8');
    expect(paths(out)).toEqual(['puente.md']);
    // Solo se abrieron (y se denegaron) las dos notas; el vínculo con `..` ni se intentó.
    expect(out.result.trace.denied).toBe(2);
  });

  it('un frontmatter inválido y vínculos enormes no rompen ni se siguen', async () => {
    writeDocs(f.dir('A'), {
      'raro.md': `---\ntitle: [roto\nsupersedes: {{\n---\n# Raro\n\n${long('chochín común')}\n\n[[${'x'.repeat(5000)}]]`,
    });
    await f.service().sync('A');
    const out = await ask('chochín común', { budget: { maxHops: 2 } });
    expect(paths(out)).toEqual(['raro.md']);
  });

  it('el número de notas descubiertas está acotado', async () => {
    const links = Array.from({ length: 60 }, (_, i) => `[[n${i}]]`).join(' ');
    const docs: Record<string, string> = { 'hub.md': note('Hub', long('agateador norteño') + `\n\n${links}`) };
    for (let i = 0; i < 60; i++) docs[`n${i}.md`] = note(`N${i}`, long('agateador norteño nodo'));
    writeDocs(f.dir('A'), docs);
    await f.service().sync('A');
    const out = await ask('agateador norteño', { k: 50, budget: { maxHops: 4, maxNodes: 1000 } });
    expect(new Set(paths(out)).size).toBeLessThanOrEqual(M5_MAX_DOCS);
  });

  it('con poco tiempo restante no expande y conserva las semillas (no devuelve vacío)', async () => {
    writeDocs(f.dir('A'), {
      'inicio.md': note('Inicio', long('collalba gris pedregal') + '\n\n[[destino]]'),
      'destino.md': note('Destino', long('apéndice sobre mediciones de campo')),
    });
    await f.service().sync('A');
    const out = await ask('collalba gris pedregal', { budget: { maxHops: 2, maxLatencyMs: 1000 } });
    expect(paths(out)).toEqual(['inicio.md']);
    expect(out.result.warnings).toContain('GRAPH_TRUNCATED');
  });

  it('las búsquedas para resolver IDs de spec están acotadas', async () => {
    const ids = Array.from({ length: M5_MAX_ID_LOOKUPS + 4 }, (_, i) => `SE-${700 + i}`);
    const docs: Record<string, string> = { 'ref.md': note('Ref', long('alondra ricotí secano') + `\n\nVer ${ids.join(', ')}.`) };
    for (const id of ids) docs[`specs/${id}-x.md`] = note(id, long(`prescripciones de ${id}`));
    writeDocs(f.dir('A'), docs);
    await f.service().sync('A');
    const out = await ask('alondra ricotí secano', { k: 20, budget: { maxHops: 1 } });
    // Los vecinos no comparten términos con la consulta (no salen como hits); se cuentan las notas abiertas.
    const opened = Number(out.result.trace.steps.find(st => st.step === 'm5:graph')?.detail?.replace('docs=', ''));
    expect(opened).toBeGreaterThan(1);
    expect(opened).toBeLessThanOrEqual(1 + M5_MAX_ID_LOOKUPS);
  });

  it('un vecino nunca desplaza a una semilla de M0 dentro de k', async () => {
    // Con RRF, 1/(60+rango): un vecino al 0,9 del primero supera al décimo. Debe quedar siempre por debajo.
    const docs: Record<string, string> = {
      'fuerte.md': note('Bisbita alpino roquedo', long('bisbita alpino roquedo').repeat(3) + '\n\n[[vecino]]'),
      'vecino.md': note('Vecino', 'bisbita ' + 'registro de campo sin relación. '.repeat(40)),
    };
    for (let i = 0; i < 12; i++) docs[`ruido-${i}.md`] = note(`Ruido ${i}`, long('bisbita alpino roquedo'));
    writeDocs(f.dir('A'), docs);
    await f.service().sync('A');
    const m0 = await runRoute(f.service(), { route: 'M0', query: 'bisbita alpino roquedo', domes: ['A'], mode: 'bm25', k: 10 });
    const out = await ask('bisbita alpino roquedo', { k: 10, budget: { maxHops: 1 } });
    expect(paths(m0)[0]).toBe('fuerte.md');
    expect(paths(m0)).not.toContain('vecino.md');
    expect(paths(out)).toEqual(paths(m0));
  });

  it('declara su contrato', () => {
    expect(getRoute('M5')).toMatchObject({ id: 'M5', supportsAsOf: true, requiresDeclaredBudget: false });
  });
});

describeSecurityBattery({ route: 'M5' });
describeSecurityBattery({ route: 'M5', budget: { maxHops: 4 } });
