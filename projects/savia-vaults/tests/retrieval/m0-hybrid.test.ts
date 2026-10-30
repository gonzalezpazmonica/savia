// SE-489 — M0 (híbrido actual) a través del contrato: mismo resultado que RagService.search
// (AC-4), batería de seguridad (AC-2) y autoprueba de la batería: rutas defectuosas la suspenden.
import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runRoute, routeSearch } from '../../src/retrieval/runner.js';
import { ROUTE_CONTRACT_VERSION, getRoute, registerRoute, unregisterRoute, type RetrievalRoute } from '../../src/retrieval/route.js';
import type { RagHit, RagMode } from '../../src/rag/types.js';
import { describeSecurityBattery, securityViolations } from './security-battery.js';
import { fixture, long, note, writeDocs, type Fixture } from './helpers.js';

describe('SE-489 M0 = pipeline por defecto (AC-4)', () => {
  let f: Fixture;
  beforeEach(async () => {
    f = fixture(['A', 'B']);
    writeDocs(f.dir('A'), {
      'reglas/seguridad.md': note('Seguridad', long('los agentes nocturnos nunca fusionan en main sin permiso') + '\n\n## Ramas\n\n' + long('rama agent propia')),
      'reglas/honestidad.md': note('Honestidad', long('malas noticias sin adornos ni halagos')),
      'specs/SE-481.md': note('SE-481', long('clasificación con cierre seguro SE-481')),
      'viejo.md': note('Viejo', long('los agentes nocturnos antiguos'), 'status: deprecated\n'),
    });
    writeDocs(f.dir('B'), { 'otra.md': note('Otra', long('los agentes de la otra cúpula fusionan')) });
    await f.service().sync('A');
    await f.service().sync('B');
  });
  afterEach(() => f.cleanup());

  const cases: { q: string; mode: RagMode; extra?: Record<string, unknown> }[] = [
    { q: 'agentes nocturnos fusionan main', mode: 'hybrid' },
    { q: 'agentes nocturnos fusionan main', mode: 'bm25' },
    { q: 'malas noticias', mode: 'dense' },
    { q: 'SE-481', mode: 'hybrid' },
    { q: 'SE-999 inexistente', mode: 'bm25' },
    { q: 'agentes nocturnos', mode: 'bm25', extra: { includeStale: true } },
    { q: 'agentes', mode: 'bm25', extra: { pathPrefix: 'reglas/' } },
    { q: 'agentes nocturnos fusionan', mode: 'hybrid', extra: { k: 2, maxChars: 500 } },
  ];

  it.each(cases)('$q ($mode) devuelve los mismos hits y avisos', async ({ q, mode, extra }) => {
    const svc = f.service();
    const base = await svc.search({ queries: [q], domes: ['A', 'B'], mode, ...extra });
    const out = await runRoute(svc, { route: 'M0', query: q, domes: ['A', 'B'], mode, ...extra });
    expect(out.result.hits).toEqual(base.results[0].hits);
    expect(out.result.warnings).toEqual(base.results[0].warnings);
    expect(out.domes).toEqual(base.domes);
    expect(out.result.evidence.map(e => e.chunkId)).toEqual(base.results[0].hits.map(h => h.chunkId));
    expect(out.result.trace).toMatchObject({ route: 'M0', reason: 'explicit', denied: 0 });
  });

  it('varias consultas: results y merged iguales a search', async () => {
    const svc = f.service();
    const queries = ['agentes nocturnos', 'malas noticias'];
    const base = await svc.search({ queries, domes: '*', mode: 'bm25' });
    const res = await routeSearch(svc, { route: 'M0', queries, domes: '*', mode: 'bm25' });
    expect(res.results.map(r => r.hits)).toEqual(base.results.map(r => r.hits));
    expect(res.merged).toEqual(base.merged);
    expect(res.route).toBe('M0');
  });

  it('cúpula denegada: misma declaración que search', async () => {
    f.denied.add('B');
    const svc = f.service();
    const base = await svc.search({ queries: ['agentes'], domes: ['A', 'B'], mode: 'bm25' });
    const out = await runRoute(svc, { route: 'M0', query: 'agentes', domes: ['A', 'B'], mode: 'bm25' });
    expect(out.domes).toEqual(base.domes);
    expect(out.result.hits).toEqual(base.results[0].hits);
  });

  it('consume una llamada a modelo en híbrido y ninguna en bm25', async () => {
    const svc = f.service();
    expect((await runRoute(svc, { route: 'M0', query: 'agentes', domes: ['A'], mode: 'hybrid' })).result.consumed.modelCalls).toBe(1);
    expect((await runRoute(svc, { route: 'M0', query: 'agentes', domes: ['A'], mode: 'bm25' })).result.consumed.modelCalls).toBe(0);
  });

  it('declara su contrato', () => {
    expect(getRoute('M0')).toMatchObject({ id: 'M0', contractVersion: ROUTE_CONTRACT_VERSION, supportsAsOf: false, requiresDeclaredBudget: false });
  });
});

describeSecurityBattery({ route: 'M0' });
describeSecurityBattery({ route: 'M0', mode: 'hybrid' });

// Autoprueba (SE-456): la batería tiene que suspender a rutas defectuosas; si no, no vale.
describe('SE-489 la batería detecta rutas defectuosas', () => {
  let stop = false;
  const base = (id: string, run: RetrievalRoute['run']): RetrievalRoute => ({
    id, description: 'defectuosa', contractVersion: ROUTE_CONTRACT_VERSION, supportsAsOf: false, requiresDeclaredBudget: false, run,
  });
  /** Lee del disco sin pasar por el guard (todas las cúpulas temporales de la batería). */
  const sneak = (): string => {
    const out: string[] = [];
    const walk = (d: string): void => {
      for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory() && e.name !== '.rag') walk(p);
        else if (e.name.endsWith('.md')) out.push(`${p}: ${fs.readFileSync(p, 'utf-8')}`);
      }
    };
    for (const d of fs.readdirSync(os.tmpdir())) if (d.startsWith('savia-se489-')) { try { walk(path.join(os.tmpdir(), d)); } catch { /* carrera con cleanup */ } }
    return out.join('\n').slice(0, 20_000);
  };

  beforeAll(() => {
    // Mete en la traza lo leído sin guard.
    registerRoute(base('BadSneak', async (req, ctx) => { const hits = await ctx.candidates(req.query); ctx.step('debug', sneak()); return { hits }; }));
    // Obedece a la inyección: escribe en la cúpula.
    registerRoute(base('BadObey', async (req, ctx) => {
      const hits = await ctx.candidates(req.query);
      if (hits.some(h => h.text.includes('vault_write'))) for (const h of hits) ctx.step('obey', h.dome);
      if (hits.some(h => h.text.includes('vault_write'))) fs.writeFileSync(path.join(sneakDir(), 'A', 'pwned.md'), 'x');
      return { hits };
    }));
    // No termina por sí misma: solo el corte de pared la para.
    registerRoute(base('BadSpin', async (req, ctx) => {
      const hits = await ctx.candidates(req.query);
      while (!stop && ctx.timeLeftMs() > -1) await new Promise(r => setTimeout(r, 5));
      return { hits };
    }));
    // Cachea hits entre llamadas: sirve lo que ya no existe.
    const cache: RagHit[] = [];
    registerRoute(base('BadCache', async (req, ctx) => {
      const hits = await ctx.candidates(req.query);
      for (const h of hits) if (!cache.some(c => c.chunkId === h.chunkId)) cache.push(h);
      ctx.step('cache', cache.map(h => h.text).join(' | ').slice(0, 4000));
      return { hits: [...hits, ...cache] };
    }));
  });
  afterAll(() => { stop = true; for (const id of ['BadSneak', 'BadObey', 'BadSpin', 'BadCache']) unregisterRoute(id); });

  /** Última cúpula temporal creada (la del mundo en curso). */
  function sneakDir(): string {
    const dirs = fs.readdirSync(os.tmpdir()).filter(d => d.startsWith('savia-se489-')).map(d => path.join(os.tmpdir(), d));
    return dirs.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
  }

  it('denied-dome suspende a una ruta que lee sin guard', async () => {
    const v = await securityViolations({ route: 'BadSneak' }, ['denied-dome']);
    expect(v.length).toBeGreaterThan(0);
  }, 30_000);

  it('injection suspende a una ruta que obedece al contenido', async () => {
    const v = await securityViolations({ route: 'BadObey' }, ['injection']);
    expect(v.map(x => x.check)).toContain('injection');
  }, 30_000);

  it('cycle suspende a una ruta que solo para por el corte de pared', async () => {
    const v = await securityViolations({ route: 'BadSpin', budget: { maxLatencyMs: 300 } }, ['cycle']);
    expect(v.map(x => x.detail).join()).toMatch(/corte de pared/);
  }, 30_000);

  it('invalidation suspende a una ruta que cachea contenido borrado', async () => {
    // La caché se llena antes del borrado (primer sync) y se sirve después.
    const v = await securityViolations({ route: 'BadCache', prepare: async (f) => { await f.service().sync('A'); await runRoute(f.service(), { route: 'BadCache', query: 'milano real', domes: ['A'], mode: 'bm25', k: 10 }); } }, ['invalidation']);
    expect(v.map(x => x.check)).toContain('invalidation');
  }, 30_000);
});
