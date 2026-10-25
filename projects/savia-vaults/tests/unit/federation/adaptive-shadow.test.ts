// SE-395 R03: shadow solo ejecuta baseline, cero llamadas extra, receipt contrafactual sin secretos (AC13, AC15).
import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runShadow } from '../../../src/federation/adaptive/shadow.js';
import { FederatedSearchEngine } from '../../../src/federation/search.js';
import { FederationRegistry } from '../../../src/federation/registry.js';
import type { SearchEngine } from '../../../src/search/index.js';
import type { FederatedDome } from '../../../src/federation/types.js';

const mk = () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shadow-'));
  const reg = new FederationRegistry(dir);
  for (const id of ['a', 'b', 'c', 'd']) reg.add({ id, name: id, url: 'http://x.invalid', timeout: 100, enabled: true, weight: 1, tags: [], status: 'healthy' });
  let calls = 0;
  const client = { async search(d: FederatedDome, _q: string) { calls++; return { results: [{ path: `${d.id}/doc`, score: 1, snippet: `s ${d.id}`, tags: [], source: d.id, contentHash: `h-${d.id}` }], status: 'ok' as const, latencyMs: 5 }; }, async healthCheck() { return { healthy: true, latencyMs: 1 }; } };
  const local = { search: () => [] } as unknown as SearchEngine;
  const engine = new FederatedSearchEngine(local, reg, { client });
  return { dir, engine, calls: () => calls, reg };
};
const ctx = { principalId: 'p', policyRevision: 'r1', contentRevision: 'c1', allowedDomeIds: ['local', 'a', 'b', 'c'] };
const domes = ['a', 'b', 'c', 'd'].map(id => ({ id, weight: 1, status: 'healthy' as const, enabled: true }));
const selection = { query: 'consulta secreta-xyz', allowedDomeIds: ctx.allowedDomeIds, domes, guidance: { version: 1, cues: [] }, budget: { maxVaults: 2, maxRemoteCalls: 1 } };

describe('runShadow', () => {
  it('ejecuta el baseline una vez y no añade llamadas remotas', async () => {
    const { dir, engine, calls } = mk();
    const plain = mk();
    await plain.engine.search('q', ctx, 10);
    let invocations = 0;
    const { response, receipt } = await runShadow({ selection, baseline: () => { invocations++; return engine.search('q', ctx, 10); } });
    expect(invocations).toBe(1);
    expect(calls()).toBe(plain.calls());
    expect(calls()).toBe(3);
    expect(response.results.length).toBe(3);
    expect(receipt.baseline.remoteCalls).toBe(3);
    fs.rmSync(dir, { recursive: true, force: true }); fs.rmSync(plain.dir, { recursive: true, force: true });
  });
  it('el receipt es contrafactual: estima ahorro y resultados que se habrían perdido', async () => {
    const { dir, engine } = mk();
    const { receipt } = await runShadow({ selection, baseline: () => engine.search('q', ctx, 10) });
    expect(receipt.evidenceType).toBe('counterfactual-estimate');
    expect(receipt.challenger.selected).toEqual(['local', 'a']);
    expect(receipt.estimate.remoteCallsSaved).toBe(2);
    expect(receipt.estimate.baselineResultsFromSkippedSources).toBe(2);
    expect(receipt.estimate.baselineResultsTotal).toBe(3);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  it('el receipt no contiene la consulta, destinos denegados ni credenciales', async () => {
    const { dir, engine } = mk();
    const { receipt } = await runShadow({ selection, baseline: () => engine.search('q', ctx, 10) });
    const text = JSON.stringify(receipt);
    expect(text).not.toContain('secreta-xyz');
    expect(text).not.toMatch(/"d"/);
    expect(receipt.challenger.deniedCount).toBe(1);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  it('queryId es un UUID generado dentro de runShadow, distinto por ejecución y ajeno a la consulta', async () => {
    const { dir, engine } = mk();
    // Consulta de un carácter: con el control antiguo («queryId contiene la consulta») casi cualquier id la contenía.
    const sel = { ...selection, query: 'a' };
    const r1 = await runShadow({ selection: sel, baseline: () => engine.search('a', ctx, 10) });
    const r2 = await runShadow({ selection: sel, baseline: () => engine.search('a', ctx, 10) });
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
    expect(r1.receipt.queryId).toMatch(uuid);
    expect(r2.receipt.queryId).toMatch(uuid);
    expect(r1.receipt.queryId).not.toBe(r2.receipt.queryId);
    // Mismo selection -> mismo configHash: el id no se deriva de la entrada.
    expect(r1.receipt.configHash).toBe(r2.receipt.configHash);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  it('guidance no serializable falla ANTES de ejecutar el baseline (no se pierde la búsqueda)', async () => {
    let ran = 0;
    const sel = { ...selection, guidance: { version: 1, cues: [], n: 1n } };
    await expect(runShadow({ selection: sel, baseline: async () => { ran++; throw new Error('no'); } })).rejects.toThrow(/BigInt/);
    expect(ran).toBe(0);
  });
  it('un fallo del baseline se propaga (shadow no lo enmascara)', async () => {
    await expect(runShadow({ selection, baseline: async () => { throw new Error('boom'); } })).rejects.toThrow('boom');
  });
});
