// SE-287 AC-4.5 retirado (2026-11-20): el hash de 32 bits lo recalcula el cliente local
// (a2a-client.ts) sobre el mismo snippet que después comprobaría; no protegía nada.
import { describe, it, expect, vi } from 'vitest';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { FederatedSearchEngine } from '../../../src/federation/search.js';
import { FederationRegistry } from '../../../src/federation/registry.js';
import type { SearchEngine } from '../../../src/search/index.js';

const ROOT = join(__dirname, '../../..');
const SRC = join(ROOT, 'src');
const DOCS = ['docs/FEDERATION.md', 'docs/FEDERATION.es.md'];

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap(f => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
}

describe('hash de integridad débil retirado', () => {
  it('no existe src/federation/hash-verify.ts', () => {
    expect(existsSync(join(SRC, 'federation/hash-verify.ts'))).toBe(false);
  });

  it('ningún fuente referencia hash-verify ni sus funciones', () => {
    const offenders = walk(SRC).filter(f => /\.ts$/.test(f)
      && /hash-verify|verifyContentHash|filterTamperedResults/.test(readFileSync(f, 'utf8')));
    expect(offenders).toEqual([]);
  });

  it('la documentación pública no promete verificación de integridad de resultados remotos', () => {
    const promise = /(tampered|manipulad)[^\n]*(discard|descart)|(prevents?|evita|protege)[^\n]*MITM/i;
    const offenders = DOCS.filter(d => promise.test(readFileSync(join(ROOT, d), 'utf8')));
    expect(offenders).toEqual([]);
  });
});

describe('contentHash como clave de deduplicación (comportamiento)', () => {
  const context = { principalId: 'alice', policyRevision: 'p1', contentRevision: 'c1', allowedDomeIds: ['local'] };

  function engineWith(rows: Array<{ path: string; snippet: string }>, dir: string) {
    const registry = new FederationRegistry(dir);
    registry.clear();
    const local = {
      search: vi.fn().mockReturnValue(rows.map(r => ({ ...r, score: 1, tags: [] }))),
    } as unknown as SearchEngine;
    return new FederatedSearchEngine(local, registry);
  }

  it('dos resultados con el mismo snippet se fusionan en uno', async () => {
    const engine = engineWith([{ path: 'a.md', snippet: 'mismo texto' }, { path: 'b.md', snippet: 'mismo texto' }], '/tmp/fake-fed-dedup-same');
    const r = await engine.search('dedup-same', context);
    expect(r.results.map(x => x.path)).toEqual(['a.md']);
  });

  it('snippets distintos no se fusionan (caso negativo)', async () => {
    const engine = engineWith([{ path: 'a.md', snippet: 'texto uno' }, { path: 'b.md', snippet: 'texto dos' }], '/tmp/fake-fed-dedup-diff');
    const r = await engine.search('dedup-diff', context);
    expect(r.results.map(x => x.path)).toEqual(['a.md', 'b.md']);
  });
});
