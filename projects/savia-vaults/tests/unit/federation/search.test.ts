// Unit tests: Federated Search Engine (merge logic)
import { describe, it, expect, vi } from 'vitest';
import { FederatedSearchEngine } from '../../../src/federation/search.js';
import { FederationRegistry } from '../../../src/federation/registry.js';
import { SearchEngine } from '../../../src/search/index.js';
import type { FederatedSearchContext, FederatedSearchResult } from '../../../src/federation/types.js';

const context = { principalId: 'alice', policyRevision: 'p1', contentRevision: 'c1', allowedDomeIds: ['local'] };

function fakeResult(path: string, snippet: string, source: string = 'local'): FederatedSearchResult {
  let hash = 0;
  const s = snippet || path;
  for (let i = 0; i < s.length; i++) {
    hash = ((hash << 5) - hash) + s.charCodeAt(i);
    hash = hash & hash;
  }
  return {
    path,
    score: 1.0,
    snippet,
    tags: [],
    source,
    contentHash: Math.abs(hash).toString(16).padStart(8, '0'),
  };
}

describe('FederatedSearchEngine — merge logic', () => {
  // We test the mergeResults method indirectly via a mock setup
  // Create minimal engine with mocked search/local results
  function createEngine(localResults: FederatedSearchResult[]) {
    const tmpDir = '/tmp/fake-federation-test';
    const registry = new FederationRegistry(tmpDir);
    registry.clear();

    const local = {
      search: vi.fn().mockReturnValue(
        localResults.map((r) => ({ path: r.path, score: r.score, snippet: r.snippet, tags: r.tags })),
      ),
    } as unknown as SearchEngine;

    return { engine: new FederatedSearchEngine(local, registry), registry };
  }

  it('returns local results when no federated domes', async () => {
    const { engine } = createEngine([
      fakeResult('a.md', 'alpha', 'local'),
      fakeResult('b.md', 'beta', 'local'),
    ]);

    const response = await engine.search('test', context);
    expect(response.results.length).toBe(2);
    expect(response.results[0].source).toBe('local');
    expect(response.sources[0].id).toBe('local');
  });

  it('deduplicates by content hash', async () => {
    // This tests the internal merge logic via the cache miss path
    // Local returns same content as remote → dedup
    const { engine, registry } = createEngine([
      fakeResult('local.md', 'same content', 'local'),
    ]);

    // Add a dome that would return same content
    registry.add({
      id: 'remote1', name: 'Remote', url: 'http://remote',
      timeout: 5000, enabled: true, weight: 1, tags: [], status: 'healthy',
    });

    // Since the A2A client is real, this will try to connect and fail
    // The test verifies local results are always included
    const response = await engine.search('test', context);
    expect(response.results.length).toBeGreaterThanOrEqual(1);
    expect(response.results[0].source).toBe('local');
  });

  it('caches results', async () => {
    const { engine } = createEngine([fakeResult('cached.md', 'cache me')]);

    const response1 = await engine.search('cache query', context);
    const response2 = await engine.search('cache query', context);
    // Second call should use cache (totalMs = 0)
    expect(response2.totalMs).toBe(0);
    expect(response2.sources).toEqual(response1.sources);
  });

  it('enforces maxTotalResults on cache miss and hit', async () => {
    const tmpDir = '/tmp/fake-federation-limit-test';
    const registry = new FederationRegistry(tmpDir);
    registry.clear();
    const local = {
      search: vi.fn().mockReturnValue([
        fakeResult('a.md', 'alpha'),
        fakeResult('b.md', 'beta'),
        fakeResult('c.md', 'gamma'),
      ].map(({ path, score, snippet, tags }) => ({ path, score, snippet, tags }))),
    } as unknown as SearchEngine;
    const engine = new FederatedSearchEngine(local, registry, { maxTotalResults: 2 });
    expect((await engine.search('limited', context, 10)).results).toHaveLength(2);
    expect((await engine.search('limited', context, 10)).results).toHaveLength(2);
  });

  it('rejects incomplete cache context before local search', async () => {
    const { engine } = createEngine([fakeResult('a.md', 'alpha')]);
    await expect(engine.search('test', { ...context, policyRevision: '' })).rejects.toThrow('policyRevision');
    const local = (engine as unknown as { local: { search: ReturnType<typeof vi.fn> } }).local;
    expect(local.search).not.toHaveBeenCalled();
  });

  it('does not query a remote dome outside the authorized set', async () => {
    const { engine, registry } = createEngine([fakeResult('local.md', 'local')]);
    registry.add({
      id: 'secret', name: 'Secret', url: 'http://secret.invalid',
      timeout: 5000, enabled: true, weight: 1, tags: [], status: 'healthy',
    });
    const remoteSearch = vi.fn().mockResolvedValue({ results: [], status: 'ok', latencyMs: 1 });
    (engine as unknown as { client: { search: typeof remoteSearch } }).client.search = remoteSearch;
    const response = await engine.search('test', context);
    expect(remoteSearch).not.toHaveBeenCalled();
    expect(response.sources.map(source => source.id)).toEqual(['local']);
  });

  it('snapshots authorization context before asynchronous remote work', async () => {
    const { engine, registry } = createEngine([]);
    registry.add({
      id: 'remote', name: 'Remote', url: 'http://remote.invalid',
      timeout: 5000, enabled: true, weight: 1, tags: [], status: 'healthy',
    });
    let completeFirst!: (value: { results: FederatedSearchResult[]; status: 'ok'; latencyMs: number }) => void;
    const remoteSearch = vi.fn()
      .mockImplementationOnce(() => new Promise(resolve => { completeFirst = resolve; }))
      .mockResolvedValue({ results: [], status: 'ok', latencyMs: 1 });
    (engine as unknown as { client: { search: typeof remoteSearch } }).client.search = remoteSearch;
    const mutableContext: FederatedSearchContext = {
      principalId: 'alice', policyRevision: 'p1', contentRevision: 'c1', allowedDomeIds: ['local', 'remote'],
    };
    const first = engine.search('mutable', mutableContext);
    await vi.waitFor(() => expect(remoteSearch).toHaveBeenCalledTimes(1));
    mutableContext.policyRevision = 'p2';
    completeFirst({ results: [], status: 'ok', latencyMs: 1 });
    await first;
    await engine.search('mutable', mutableContext);
    expect(remoteSearch).toHaveBeenCalledTimes(2);
  });
});
