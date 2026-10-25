// SE-395 R02: guidance schema y selección determinista (AC02, AC03, AC04, AC05, AC06, AC13).
import { describe, it, expect } from 'vitest';
import { parseGuidance, GUIDANCE_LIMITS, DEFAULT_FLAGS } from '../../../src/federation/adaptive/guidance.js';
import { selectDestinations, type SelectionInput } from '../../../src/federation/adaptive/select.js';

const dome = (id: string, weight = 1, status: 'healthy' | 'unhealthy' = 'healthy') => ({ id, weight, status, enabled: true });
const g = (cues: unknown[]) => ({ version: 1, cues });
const base = (over: Partial<SelectionInput> = {}): SelectionInput => ({
  query: 'rotación claves cifrado', allowedDomeIds: ['local', 'a', 'b', 'c', 'd'],
  domes: [dome('a'), dome('b'), dome('c'), dome('d')], guidance: g([]),
  budget: { maxVaults: 3, maxRemoteCalls: 3 }, flags: { adaptive: true }, ...over,
});

describe('guidance schema', () => {
  it('acepta un documento válido y normaliza términos', () => {
    const r = parseGuidance(g([{ vaultId: 'a', attracts: [{ term: 'Cifrado', score: 0.5 }], repels: [], specialties: ['Claves'] }]));
    expect(r.ok).toBe(true);
    if (r.ok) { expect(r.guidance.cues[0].attracts[0].term).toBe('cifrado'); expect(r.guidance.cues[0].specialties).toEqual(['claves']); }
  });
  it('rechaza campos desconocidos en cualquier nivel', () => {
    expect(parseGuidance({ ...g([]), extra: 1 }).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', trust: 1 }])).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', attracts: [{ term: 'x', score: 0.1, deny: true }] }])).ok).toBe(false);
  });
  it('rechaza scores no finitos, fuera de rango y versión errónea', () => {
    for (const s of [NaN, Infinity, -0.1, 1.1, '0.5']) expect(parseGuidance(g([{ vaultId: 'a', attracts: [{ term: 'x', score: s }] }])).ok).toBe(false);
    expect(parseGuidance({ version: 2, cues: [] }).ok).toBe(false);
  });
  it('aplica límites de tamaño y duplicados', () => {
    const many = Array.from({ length: GUIDANCE_LIMITS.maxCues + 1 }, (_, i) => ({ vaultId: `v${i}` }));
    expect(parseGuidance(g(many)).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', specialties: Array(GUIDANCE_LIMITS.maxTermsPerList + 1).fill('x') }])).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', specialties: ['x'.repeat(GUIDANCE_LIMITS.maxTermLength + 1)] }])).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a' }, { vaultId: 'a' }])).ok).toBe(false);
  });
  it('no confía en entradas no objeto', () => {
    for (const bad of [null, 'x', 3, [], undefined]) expect(parseGuidance(bad).ok).toBe(false);
  });
  it('flags por defecto: todos false y congelados', () => {
    expect(Object.values(DEFAULT_FLAGS).every(v => v === false)).toBe(true);
    expect(Object.isFrozen(DEFAULT_FLAGS)).toBe(true);
  });
});

describe('selectDestinations', () => {
  it('flag apagado = baseline: todos los autorizados y sanos, sin tope', () => {
    const r = selectDestinations(base({ flags: {} }));
    expect(r.mode).toBe('baseline');
    expect(r.selected).toEqual(['local', 'a', 'b', 'c', 'd']);
  });
  it('policy antes de score: un destino denegado jamás se puntúa ni se nombra, por alto que sea su cue', () => {
    const guidance = g([{ vaultId: 'd', attracts: [{ term: 'cifrado', score: 1 }], specialties: ['claves'] }]);
    const r = selectDestinations(base({ allowedDomeIds: ['local', 'a', 'b'], guidance }));
    expect(r.selected).not.toContain('d');
    expect(Object.keys(r.scores)).not.toContain('d');
    expect(JSON.stringify(r)).not.toMatch(/"d"/);
    expect(r.deniedCount).toBe(2);
  });
  it('control positivo: el mismo cue sobre un destino autorizado sí lo prioriza', () => {
    const guidance = g([{ vaultId: 'd', attracts: [{ term: 'cifrado', score: 1 }] }]);
    const r = selectDestinations(base({ guidance }));
    expect(r.selected[1]).toBe('d');
  });
  it('repulsión baja prioridad pero no deniega: con presupuesto holgado sigue elegible', () => {
    const guidance = g([{ vaultId: 'a', repels: [{ term: 'cifrado', score: 1 }] }]);
    const tight = selectDestinations(base({ guidance }));
    expect(tight.selected).not.toContain('a');
    expect(tight.scores.a).toBe(0);
    const loose = selectDestinations(base({ guidance, budget: { maxVaults: 5, maxRemoteCalls: 4 } }));
    expect(loose.selected).toContain('a');
  });
  it('selección ⊆ autorizados ∩ sanos y respeta el presupuesto', () => {
    const r = selectDestinations(base({ domes: [dome('a'), dome('b', 1, 'unhealthy'), dome('c'), dome('d')] }));
    expect(r.selected).not.toContain('b');
    expect(r.skipped).toContainEqual({ id: 'b', reason: 'UNHEALTHY' });
    expect(r.selected.length).toBeLessThanOrEqual(3);
    expect(r.selected.filter(i => i !== 'local').length).toBeLessThanOrEqual(3);
  });
  it('local autorizado cuenta en maxVaults y no es desplazado', () => {
    const r = selectDestinations(base({ budget: { maxVaults: 2, maxRemoteCalls: 3 }, guidance: g([{ vaultId: 'c', attracts: [{ term: 'cifrado', score: 1 }] }]) }));
    expect(r.selected).toEqual(['local', 'c']);
  });
  it('desempate estable por id y orden de entrada irrelevante', () => {
    const a = selectDestinations(base());
    const b = selectDestinations(base({ domes: [dome('d'), dome('c'), dome('b'), dome('a')] }));
    expect(a.selected).toEqual(['local', 'a', 'b']);
    expect(b).toEqual(a);
  });
  it('guidance inválida cae a federación existente con presupuesto, no a broadcast', () => {
    const r = selectDestinations(base({ guidance: { version: 9 } }));
    expect(r.mode).toBe('fallback');
    expect(r.selected).toEqual(['local', 'a', 'b']);
    expect(r.skipped).toContainEqual({ id: 'c', reason: 'BUDGET' });
  });
  it('fallback sin presupuesto restante termina sin expansión', () => {
    const r = selectDestinations(base({ guidance: null, budget: { maxVaults: 1, maxRemoteCalls: 3 } }));
    expect(r.selected).toEqual(['local']);
    expect(r.termination).toBe('BUDGET_EXHAUSTED');
  });
  it('sin destinos autorizados: POLICY_BLOCK; sin sanos: NO_ROUTE', () => {
    expect(selectDestinations(base({ allowedDomeIds: [] })).termination).toBe('POLICY_BLOCK');
    const none = selectDestinations(base({ allowedDomeIds: ['a'], domes: [dome('a', 1, 'unhealthy')] }));
    expect(none.termination).toBe('NO_ROUTE');
    expect(none.selected).toEqual([]);
  });
  it('no muta la entrada', () => {
    const input = base({ guidance: g([{ vaultId: 'a', attracts: [{ term: 'cifrado', score: 0.4 }] }]) });
    const snap = JSON.stringify(input);
    selectDestinations(input);
    expect(JSON.stringify(input)).toBe(snap);
  });
});

describe('revisión #1382', () => {
  it('degraded es elegible como en registry.getHealthy; unhealthy no (apagado y encendido)', () => {
    const domes = [{ id: 'a', weight: 1, status: 'degraded' as const, enabled: true }, dome('b', 1, 'unhealthy')];
    const off = selectDestinations(base({ domes, flags: {} }));
    expect(off.selected).toEqual(['local', 'a']);
    expect(off.skipped).toEqual([{ id: 'b', reason: 'UNHEALTHY' }]);
    expect(selectDestinations(base({ domes })).selected).toEqual(['local', 'a']);
  });
  it('terminación coherente: presupuesto remoto 0 con sanos = BUDGET_EXHAUSTED', () => {
    expect(selectDestinations(base({ budget: { maxVaults: 1, maxRemoteCalls: 3 } })).termination).toBe('BUDGET_EXHAUSTED');
    expect(selectDestinations(base({ budget: { maxVaults: 1, maxRemoteCalls: 3 }, guidance: 'x' })).termination).toBe('BUDGET_EXHAUSTED');
    expect(selectDestinations(base({ allowedDomeIds: ['a'], budget: { maxVaults: 0, maxRemoteCalls: 3 } })).termination).toBe('BUDGET_EXHAUSTED');
  });
  it('POLICY_BLOCK solo si nada está autorizado; autorizados no sanos = NO_ROUTE', () => {
    expect(selectDestinations(base({ allowedDomeIds: [] })).termination).toBe('POLICY_BLOCK');
    expect(selectDestinations(base({ allowedDomeIds: ['a'], domes: [dome('a', 1, 'unhealthy'), dome('b')] })).termination).toBe('NO_ROUTE');
  });
  it('presupuesto NaN no expande nada', () => {
    const r = selectDestinations(base({ budget: { maxVaults: NaN, maxRemoteCalls: NaN } }));
    expect(r.selected).toEqual(['local']);
  });
  it('presupuesto Infinity es fail-closed: no significa «sin tope»', () => {
    const r = selectDestinations(base({ budget: { maxVaults: Infinity, maxRemoteCalls: Infinity } }));
    expect(r.selected).toEqual(['local']);
    expect(r.termination).toBe('BUDGET_EXHAUSTED');
  });
  it('BUDGET_EXHAUSTED sin seleccionados lista los sanos recortados como BUDGET, igual que fallback', () => {
    const budget = { maxVaults: 0, maxRemoteCalls: 3 };
    const allowedDomeIds = ['a', 'b', 'c', 'd'];
    const ad = selectDestinations(base({ budget, allowedDomeIds }));
    const fb = selectDestinations(base({ budget, allowedDomeIds, guidance: 'x' }));
    expect(ad.selected).toEqual([]);
    expect(ad.termination).toBe('BUDGET_EXHAUSTED');
    expect(ad.skipped).toEqual(['a', 'b', 'c', 'd'].map(id => ({ id, reason: 'BUDGET' })));
    expect(ad.skipped).toEqual(fb.skipped);
  });
  it('id de dome repetido cuenta una vez: no se selecciona dos veces ni gasta presupuesto doble', () => {
    const r = selectDestinations(base({ domes: [dome('a', 5), dome('a', 5), dome('b'), dome('c')], allowedDomeIds: ['local', 'a', 'b', 'c'] }));
    expect(r.selected).toEqual(['local', 'a', 'b']);
    expect(new Set(r.selected).size).toBe(r.selected.length);
  });
  it("un id '__proto__' es una clave propia de scores, no reasigna el prototipo", () => {
    const r = selectDestinations(base({ domes: [dome('__proto__', 2), dome('a')], allowedDomeIds: ['local', '__proto__', 'a'] }));
    expect(Object.prototype.hasOwnProperty.call(r.scores, '__proto__')).toBe(true);
    expect(r.scores['__proto__']).toBe(2);
    expect(r.selected).toEqual(['local', '__proto__', 'a']);
  });
  it('términos duplicados, con espacios o puntuación se rechazan', () => {
    const dup = Array.from({ length: 16 }, () => ({ term: 'x', score: 1 }));
    expect(parseGuidance(g([{ vaultId: 'a', attracts: dup }])).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', attracts: [{ term: 'a b', score: 1 }] }])).ok).toBe(false);
    expect(parseGuidance(g([{ vaultId: 'a', specialties: ['c++'] }])).ok).toBe(false);
  });
});

