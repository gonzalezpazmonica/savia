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
    const { response, receipt } = await runShadow({ queryId: 'q-00000001', selection, baseline: () => { invocations++; return engine.search('q', ctx, 10); } });
    expect(invocations).toBe(1);
    expect(calls()).toBe(plain.calls());
    expect(calls()).toBe(3);
    expect(response.results.length).toBe(3);
    expect(receipt.baseline.remoteCalls).toBe(3);
    fs.rmSync(dir, { recursive: true, force: true }); fs.rmSync(plain.dir, { recursive: true, force: true });
  });
  it('el receipt es contrafactual: estima ahorro y resultados que se habrían perdido', async () => {
    const { dir, engine } = mk();
    const { receipt } = await runShadow({ queryId: 'q-00000002', selection, baseline: () => engine.search('q', ctx, 10) });
    expect(receipt.evidenceType).toBe('counterfactual-estimate');
    expect(receipt.challenger.selected).toEqual(['local', 'a']);
    expect(receipt.estimate.remoteCallsSaved).toBe(2);
    expect(receipt.estimate.baselineResultsFromSkippedSources).toBe(2);
    expect(receipt.estimate.baselineResultsTotal).toBe(3);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  it('el receipt no contiene la consulta, destinos denegados ni credenciales', async () => {
    const { dir, engine } = mk();
    const { receipt } = await runShadow({ queryId: 'q-00000003', selection, baseline: () => engine.search('q', ctx, 10) });
    const text = JSON.stringify(receipt);
    expect(text).not.toContain('secreta-xyz');
    expect(text).not.toMatch(/"d"/);
    expect(receipt.challenger.deniedCount).toBe(1);
    fs.rmSync(dir, { recursive: true, force: true });
  });
  it('rechaza queryId no opaco (p. ej. la propia consulta) y no ejecuta el baseline', async () => {
    let ran = 0;
    for (const bad of ['consulta secreta xyz', 'short', '']) {
      await expect(runShadow({ queryId: bad, selection, baseline: async () => { ran++; throw new Error('no'); } })).rejects.toThrow(/opaco/);
    }
    expect(ran).toBe(0);
  });
  it('rechaza un queryId que contiene la consulta aunque tenga formato válido', async () => {
    let ran = 0;
    const sel = { ...selection, query: 'password123' };
    await expect(runShadow({ queryId: 'PASSWORD123', selection: sel, baseline: async () => { ran++; throw new Error('no'); } })).rejects.toThrow(/consulta/);
    expect(ran).toBe(0);
  });
  it('un fallo del baseline se propaga (shadow no lo enmascara)', async () => {
    await expect(runShadow({ queryId: 'q-00000004', selection, baseline: async () => { throw new Error('boom'); } })).rejects.toThrow('boom');
  });
});
