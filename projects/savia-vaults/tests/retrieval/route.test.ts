// SE-489 — contrato RetrievalRoute: registro, presupuesto y contador.
import { describe, it, expect, afterEach } from 'vitest';
import {
  BUDGET_CAPS, BudgetMeter, DEFAULT_BUDGET, ROUTE_CONTRACT_VERSION, RouteError,
  getRoute, listRoutes, registerRoute, resolveBudget, unregisterRoute, type RetrievalRoute,
} from '../../src/retrieval/route.js';

const dummy = (id: string, extra: Partial<RetrievalRoute> = {}): RetrievalRoute => ({
  id, description: 'test', contractVersion: ROUTE_CONTRACT_VERSION, supportsAsOf: false, requiresDeclaredBudget: false,
  run: async () => ({ hits: [], evidence: [], trace: { route: id, reason: 't', seed: 0, steps: [], denied: 0 }, consumed: { latencyMs: 0, modelCalls: 0, nodes: 0, hops: 0, inputTokens: 0 } }),
  ...extra,
});

describe('SE-489 registro de rutas', () => {
  afterEach(() => { unregisterRoute('Tx1'); unregisterRoute('Tx2'); });

  it('registra y recupera una ruta por id', () => {
    registerRoute(dummy('Tx1'));
    expect(getRoute('Tx1').id).toBe('Tx1');
    expect(listRoutes()).toContain('Tx1');
  });

  it('rechaza un id repetido sin sustituir la ruta', () => {
    const first = dummy('Tx2', { description: 'primera' });
    registerRoute(first);
    expect(() => registerRoute(dummy('Tx2', { description: 'segunda' }))).toThrow(/DUPLICATE_ROUTE/);
    expect(getRoute('Tx2').description).toBe('primera');
  });

  it('una ruta desconocida es UNKNOWN_ROUTE', () => {
    expect(() => getRoute('NoExiste')).toThrow(RouteError);
    expect(() => getRoute('NoExiste')).toThrow(/UNKNOWN_ROUTE/);
  });

  it('rechaza ids no válidos y versiones de contrato distintas', () => {
    expect(() => registerRoute(dummy('../x'))).toThrow(/INVALID_ROUTE/);
    expect(() => registerRoute({ ...dummy('Tx1'), contractVersion: 99 as unknown as 1 })).toThrow(/INVALID_ROUTE/);
    expect(listRoutes()).not.toContain('Tx1');
  });
});

describe('SE-489 presupuesto', () => {
  it('ausente ⇒ el de por defecto, no declarado', () => {
    expect(resolveBudget(undefined)).toEqual({ budget: DEFAULT_BUDGET, declared: false });
  });

  it('parcial ⇒ completa con los valores por defecto y queda declarado', () => {
    const r = resolveBudget({ maxNodes: 10 });
    expect(r.declared).toBe(true);
    expect(r.budget).toEqual({ ...DEFAULT_BUDGET, maxNodes: 10 });
  });

  it.each([
    [{ maxNodes: -1 }], [{ maxNodes: 1.5 }], [{ maxNodes: '3' }], [{ maxHops: BUDGET_CAPS.maxHops + 1 }],
    [{ maxTokens: 3 }], ['x'], [[1]],
  ])('rechaza %j (cierre seguro)', (input) => {
    expect(() => resolveBudget(input)).toThrow(/INVALID_BUDGET/);
  });

  it('acepta el tope exacto', () => {
    expect(resolveBudget({ maxHops: BUDGET_CAPS.maxHops }).budget.maxHops).toBe(BUDGET_CAPS.maxHops);
  });
});

describe('SE-489 BudgetMeter', () => {
  it('no deja pasar del límite y marca qué se agotó', () => {
    const m = new BudgetMeter({ ...DEFAULT_BUDGET, maxNodes: 2 });
    expect(m.consume('nodes')).toBe(true);
    expect(m.consume('nodes')).toBe(true);
    expect(m.consume('nodes')).toBe(false);
    expect(m.snapshot().nodes).toBe(2);
    expect(m.exhausted).toBe('nodes');
  });

  it('un consumo que excedería no descuenta nada', () => {
    const m = new BudgetMeter({ ...DEFAULT_BUDGET, maxInputTokens: 10 });
    expect(m.consume('inputTokens', 11)).toBe(false);
    expect(m.snapshot().inputTokens).toBe(0);
    expect(m.consume('inputTokens', 10)).toBe(true);
  });

  it('agotado el tiempo, nada más se consume', () => {
    let t = 0;
    const m = new BudgetMeter({ ...DEFAULT_BUDGET, maxLatencyMs: 100 }, () => t);
    expect(m.consume('hops')).toBe(true);
    t = 100;
    expect(m.timeLeftMs()).toBe(0);
    expect(m.consume('hops')).toBe(false);
    expect(m.exhausted).toBe('latencyMs');
    expect(m.snapshot().latencyMs).toBe(100);
  });

  it('rechaza cantidades negativas o no finitas', () => {
    const m = new BudgetMeter(DEFAULT_BUDGET);
    expect(m.consume('nodes', -1)).toBe(false);
    expect(m.consume('nodes', Number.NaN)).toBe(false);
    expect(m.snapshot().nodes).toBe(0);
  });
});
