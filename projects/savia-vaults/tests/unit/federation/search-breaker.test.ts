// SE-287 AC-4.3 / K6-a: contrato del cortacircuitos a través de search().
// Registro y motor reales; solo transporte y reloj controlados. Consultas únicas
// evitan la caché. Mutante esperado: omitir allow() debe romper «omite el dome».
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FederatedSearchEngine } from '../../../src/federation/search.js';
import { FederationRegistry } from '../../../src/federation/registry.js';
import type { A2AClient } from '../../../src/federation/a2a-client.js';
import type { FederatedDome, FederatedSearchContext } from '../../../src/federation/types.js';
import type { SearchEngine } from '../../../src/search/index.js';

const THRESHOLD = 5; // SE-287 AC-4.3; valores por defecto de CircuitBreaker.
const COOLDOWN_MS = 300_000;
const dome = (id: string): FederatedDome => ({
  id, name: id, url: `https://${id}.example`, timeout: 2000,
  enabled: true, weight: 1, tags: [], status: 'healthy',
});
const ok = (id: string) => ({
  status: 'ok' as const, latencyMs: 1,
  results: [{ path: `${id}.md`, score: 1, snippet: id, tags: [], source: id, contentHash: id }],
});
const failed = (status: 'error' | 'timeout') => ({ status, results: [], latencyMs: 1 });

describe('FederatedSearchEngine — cortacircuitos por dome (SE-287 AC-4.3)', () => {
  let dir: string;
  let registry: FederationRegistry;
  let engine: FederatedSearchEngine;
  let remote: ReturnType<typeof vi.fn<A2AClient['search']>>;
  let context: FederatedSearchContext;
  let queryNumber: number;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
    dir = mkdtempSync(join(tmpdir(), 'federation-breaker-'));
    registry = new FederationRegistry(dir);
    registry.add(dome('remote'));
    remote = vi.fn<A2AClient['search']>().mockResolvedValue(failed('error'));
    const local = { search: vi.fn().mockReturnValue([]) } as unknown as SearchEngine;
    engine = new FederatedSearchEngine(local, registry, {
      client: { search: remote, healthCheck: vi.fn().mockResolvedValue({ healthy: true, latencyMs: 1 }) },
    });
    context = { principalId: 'reader', policyRevision: 'p1', contentRevision: 'c1', allowedDomeIds: ['remote'] };
    queryNumber = 0;
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
    rmSync(dir, { recursive: true, force: true });
  });

  const search = () => engine.search(`consulta-${++queryNumber}`, context);
  const callsTo = (id: string) => remote.mock.calls.filter(([target]) => target.id === id).length;
  const failConsecutively = async (count = THRESHOLD) => {
    for (let i = 0; i < count; i++) await search();
  };
  const expectSkipped = async () => {
    const before = callsTo('remote');
    const response = await search();
    expect(callsTo('remote')).toBe(before);
    expect(response.sources).toContainEqual(expect.objectContaining({ id: 'remote', status: 'skipped', count: 0 }));
    expect(response.results.filter(result => result.source === 'remote')).toEqual([]);
  };

  it.each(['error', 'timeout'] as const)('sigue llamando antes de cinco fallos consecutivos (%s)', async status => {
    remote.mockResolvedValue(failed(status));
    for (let i = 1; i < THRESHOLD; i++) {
      const response = await search();
      expect(callsTo('remote')).toBe(i);
      expect(response.sources).toContainEqual(expect.objectContaining({ id: 'remote', status, count: 0 }));
    }
  });

  it('omite el dome tras el quinto fallo y lo marca skipped durante todo el enfriamiento', async () => {
    await failConsecutively();
    expect(callsTo('remote')).toBe(THRESHOLD);
    await expectSkipped();
    await expectSkipped(); // Una consulta distinta tampoco debe llegar al transporte.
    vi.advanceTimersByTime(COOLDOWN_MS - 1);
    await expectSkipped();
  });

  it('sondea tras el enfriamiento y vuelve a consultar normalmente tras una sonda correcta', async () => {
    await failConsecutively();
    remote.mockResolvedValue(ok('remote'));
    vi.advanceTimersByTime(COOLDOWN_MS + 1);
    const probe = await search();
    expect(callsTo('remote')).toBe(THRESHOLD + 1);
    expect(probe.sources).toContainEqual(expect.objectContaining({ id: 'remote', status: 'ok', count: 1 }));
    expect(probe.results).toEqual(ok('remote').results);
    await search();
    expect(callsTo('remote')).toBe(THRESHOLD + 2);

    // La sonda debe cerrar y reiniciar la racha, no solo permitir una llamada.
    remote.mockResolvedValue(failed('error'));
    await failConsecutively(THRESHOLD - 1);
    expect(callsTo('remote')).toBe(2 * THRESHOLD + 1);
    remote.mockResolvedValue(ok('remote'));
    expect((await search()).results).toEqual(ok('remote').results);
    expect(callsTo('remote')).toBe(2 * THRESHOLD + 2);
  });

  it.each(['error', 'timeout'] as const)('reinicia el enfriamiento cuando la sonda falla (%s)', async status => {
    await failConsecutively();
    vi.advanceTimersByTime(COOLDOWN_MS + 1);
    remote.mockResolvedValue(failed(status));
    const probe = await search();
    expect(callsTo('remote')).toBe(THRESHOLD + 1);
    expect(probe.sources).toContainEqual(expect.objectContaining({ id: 'remote', status }));
    await expectSkipped();
    vi.advanceTimersByTime(COOLDOWN_MS - 1);
    await expectSkipped();
    vi.advanceTimersByTime(2);
    await search();
    expect(callsTo('remote')).toBe(THRESHOLD + 2);
  });

  it('un éxito intermedio reinicia los fallos: cinco errores no consecutivos no abren el circuito', async () => {
    await search();
    remote.mockResolvedValue(ok('remote'));
    await search();
    remote.mockResolvedValue(failed('error'));
    await failConsecutively(THRESHOLD - 1);
    expect(callsTo('remote')).toBe(THRESHOLD + 1);
    const fifth = await search();
    expect(callsTo('remote')).toBe(THRESHOLD + 2);
    expect(fifth.sources).toContainEqual(expect.objectContaining({ id: 'remote', status: 'error' }));
    await expectSkipped();
  });

  it('no salta un dome sano cuando otro tiene el circuito abierto', async () => {
    registry.add(dome('healthy'));
    context.allowedDomeIds.push('healthy');
    remote.mockImplementation(async target => target.id === 'healthy' ? ok('healthy') : failed('error'));
    await failConsecutively();
    for (let i = 1; i <= 2; i++) {
      const response = await search();
      expect(callsTo('remote')).toBe(THRESHOLD);
      expect(callsTo('healthy')).toBe(THRESHOLD + i);
      expect(response.sources).toContainEqual(expect.objectContaining({ id: 'remote', status: 'skipped', count: 0 }));
      expect(response.sources).toContainEqual(expect.objectContaining({ id: 'healthy', status: 'ok', count: 1 }));
      expect(response.results).toEqual(ok('healthy').results);
    }
  });

  it('nunca salta un dome que siempre responde correctamente, incluso pasado el enfriamiento', async () => {
    remote.mockResolvedValue(ok('remote'));
    for (let i = 1; i <= THRESHOLD + 2; i++) {
      if (i === THRESHOLD) vi.advanceTimersByTime(COOLDOWN_MS + 1);
      const response = await search();
      expect(callsTo('remote')).toBe(i);
      expect(response.sources).toEqual([expect.objectContaining({ id: 'remote', status: 'ok', count: 1 })]);
      expect(response.results).toEqual(ok('remote').results);
    }
  });
});
