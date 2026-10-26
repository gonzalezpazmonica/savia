import { describe, it, expect } from 'vitest';
import { parseGuidance, GUIDANCE_LIMITS } from '../../../src/federation/adaptive/guidance.js';
import { selectRoute, ADAPTIVE_FLAGS_DEFAULT, type Candidate } from '../../../src/federation/adaptive/select.js';

const cands: Candidate[] = [
  { id: 'local', weight: 1, local: true, healthy: true },
  { id: 'hr', weight: 0.5, local: false, healthy: true },
  { id: 'fin', weight: 0.6, local: false, healthy: true },
  { id: 'ops', weight: 0.4, local: false, healthy: true },
  { id: 'legal', weight: 0.9, local: false, healthy: false },
];
const all = ['local', 'hr', 'fin', 'ops', 'legal'];
const budget = { maxVaults: 3, maxRemoteCalls: 3 };
const guidance = { version: 1, cues: [
  { dome: 'hr', attracts: ['vacaciones'], repels: [], specialties: ['nomina'] },
  { dome: 'fin', attracts: ['factura'], repels: ['vacaciones'], specialties: [] },
] };
const on = { adaptive: true };

describe('SE-395 R02 guidance schema (AC02)', () => {
  it('acepta un cue válido y normaliza términos', () => {
    const r = parseGuidance({ version: 1, cues: [{ dome: 'a', attracts: [' Foo '], repels: [], specialties: [] }] });
    expect(r.ok && r.guidance.cues[0].attracts).toEqual(['foo']);
  });
  it.each([
    ['no objeto', 'x'], ['versión', { version: 2, cues: [] }], ['campo desconocido top', { version: 1, cues: [], extra: 1 }],
    ['campo desconocido cue', { version: 1, cues: [{ dome: 'a', trust: 1 }] }], ['peso NaN', { version: 1, cues: [{ dome: 'a', weight: NaN }] }],
    ['peso Infinity', { version: 1, cues: [{ dome: 'a', weight: Infinity }] }], ['peso fuera de rango', { version: 1, cues: [{ dome: 'a', weight: 2 }] }],
    ['dome duplicado', { version: 1, cues: [{ dome: 'a' }, { dome: 'a' }] }], ['término vacío', { version: 1, cues: [{ dome: 'a', attracts: [''] }] }],
    ['término largo', { version: 1, cues: [{ dome: 'a', attracts: ['x'.repeat(GUIDANCE_LIMITS.maxTermLength + 1)] }] }],
    ['demasiados términos', { version: 1, cues: [{ dome: 'a', repels: Array(GUIDANCE_LIMITS.maxTermsPerList + 1).fill('x') }] }],
    ['demasiados cues', { version: 1, cues: Array.from({ length: GUIDANCE_LIMITS.maxCues + 1 }, (_, i) => ({ dome: `d${i}` })) }],
  ])('rechaza: %s', (_n, input) => { expect(parseGuidance(input).ok).toBe(false); });
});

describe('SE-395 R02 selección', () => {
  it('AC01: flags por defecto en false y sin flag devuelve el baseline por peso', () => {
    expect(Object.values(ADAPTIVE_FLAGS_DEFAULT).every(v => v === false)).toBe(true);
    const s = selectRoute({ query: 'vacaciones', candidates: cands, allowedIds: all, guidance, budget });
    expect(s).toMatchObject({ mode: 'baseline', fallbackReason: 'flag_off', selected: ['local', 'fin', 'hr'] });
  });

  it('AC03: un destino denegado no se puntúa ni se selecciona, aunque su cue lo atraiga al máximo', () => {
    const g = { version: 1, cues: [{ dome: 'hr', attracts: ['vacaciones', 'x'], specialties: ['vacaciones'], weight: 1 }] };
    const s = selectRoute({ query: 'vacaciones x', candidates: cands, allowedIds: ['local', 'fin', 'ops'], guidance: g, budget, flags: on });
    expect(s.selected).not.toContain('hr');
    expect(s.scored.map(x => x.id)).not.toContain('hr');
    expect(JSON.stringify(s)).not.toContain('hr"');
  });

  it('AC03: DENY no es un peso: autorizar el destino lo cambia de ausente a primero', () => {
    const g = { version: 1, cues: [{ dome: 'hr', attracts: [], specialties: ['nomina'] }] };
    const d = selectRoute({ query: 'nomina', candidates: cands, allowedIds: ['local', 'fin'], guidance: g, budget, flags: on });
    const a = selectRoute({ query: 'nomina', candidates: cands, allowedIds: ['local', 'fin', 'hr'], guidance: g, budget, flags: on });
    expect(d.selected).not.toContain('hr');
    expect(a.scored[0].id).toBe('hr');
  });

  it('AC03: un destino no sano no se selecciona aunque esté autorizado y atraído', () => {
    const g = { version: 1, cues: [{ dome: 'legal', specialties: ['contrato'] }] };
    const s = selectRoute({ query: 'contrato', candidates: cands, allowedIds: all, guidance: g, budget, flags: on });
    expect(s.selected).not.toContain('legal');
  });

  it('AC04: atracción sube y repulsión baja el destino sin excluirlo', () => {
    const s = selectRoute({ query: 'vacaciones nomina', candidates: cands, allowedIds: all, guidance, budget: { maxVaults: 5, maxRemoteCalls: 5 }, flags: on });
    expect(s.mode).toBe('adaptive');
    expect(s.scored[0].id).toBe('hr');
    expect(s.selected).toContain('fin'); // repelido pero autorizado y con hueco
    const fin = s.scored.find(x => x.id === 'fin')!;
    expect(fin.matched.repels).toBe(1);
    expect(fin.score).toBeLessThan(0.6);
  });

  it('AC04: desempate estable por id y orden de entrada irrelevante', () => {
    const tie: Candidate[] = [{ id: 'b', weight: 0.5, local: false, healthy: true }, { id: 'a', weight: 0.5, local: false, healthy: true }];
    const g = { version: 1, cues: [{ dome: 'a', attracts: ['q'] }, { dome: 'b', attracts: ['q'] }] };
    const r1 = selectRoute({ query: 'q', candidates: tie, allowedIds: ['a', 'b'], guidance: g, budget, flags: on });
    const r2 = selectRoute({ query: 'q', candidates: [...tie].reverse(), allowedIds: ['b', 'a'], guidance: g, budget, flags: on });
    expect(r1.selected).toEqual(['a', 'b']);
    expect(r2).toEqual(r1);
  });

  it('AC05: el resultado es subconjunto de autorizados y sanos y respeta maxVaults y maxRemoteCalls', () => {
    const s = selectRoute({ query: 'vacaciones factura', candidates: cands, allowedIds: ['local', 'hr', 'fin', 'legal'], guidance, budget: { maxVaults: 3, maxRemoteCalls: 1 }, flags: on });
    expect(s.selected.length).toBeLessThanOrEqual(2); // local + 1 remoto
    expect(s.selected.filter(i => i !== 'local').length).toBe(1);
    for (const id of s.selected) expect(['local', 'hr', 'fin']).toContain(id);
  });

  it('AC06: guidance inválida cae al baseline con policy y presupuesto', () => {
    const s = selectRoute({ query: 'vacaciones', candidates: cands, allowedIds: ['local', 'hr', 'ops'], guidance: { version: 1, cues: [{ dome: 'hr', weight: NaN }] }, budget, flags: on });
    expect(s).toMatchObject({ mode: 'baseline', fallbackReason: 'invalid_guidance', selected: ['local', 'hr', 'ops'] });
  });

  it('AC06: sin señal o sin guidance cae al baseline', () => {
    expect(selectRoute({ query: 'zzz', candidates: cands, allowedIds: all, guidance, budget, flags: on }).fallbackReason).toBe('no_signal');
    expect(selectRoute({ query: 'zzz', candidates: cands, allowedIds: all, budget, flags: on }).fallbackReason).toBe('no_guidance');
  });

  it('AC06: fallback con presupuesto remoto agotado termina sin expansión (no broadcast)', () => {
    const s = selectRoute({ query: 'x', candidates: cands.filter(c => !c.local), allowedIds: all, guidance: 'basura', budget: { maxVaults: 3, maxRemoteCalls: 3, remoteCallsUsed: 3 }, flags: on });
    expect(s.selected).toEqual([]);
    expect(s.termination).toBe('BUDGET_EXHAUSTED');
  });

  it('AC06: sin ningún destino autorizado termina en POLICY_BLOCK', () => {
    const s = selectRoute({ query: 'x', candidates: cands, allowedIds: [], budget, flags: on });
    expect(s).toMatchObject({ selected: [], termination: 'POLICY_BLOCK' });
  });

  it('es pura: misma entrada, misma salida y no muta la entrada', () => {
    const input = { query: 'vacaciones', candidates: cands, allowedIds: all, guidance, budget, flags: on };
    const snap = JSON.stringify(input);
    expect(selectRoute(input)).toEqual(selectRoute(input));
    expect(JSON.stringify(input)).toBe(snap);
  });
});
