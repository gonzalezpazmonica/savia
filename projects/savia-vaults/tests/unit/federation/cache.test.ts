// Unit tests: Federation Cache
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { FederationCache } from '../../../src/federation/cache.js';
import type { FederatedSearchContext, FederatedSearchResponse, FederatedSearchResult } from '../../../src/federation/types.js';

function makeResult(path: string, snippet: string): FederatedSearchResult {
  return { path, score: 1, snippet, tags: [], source: 'local', contentHash: 'hash' + path };
}

describe('FederationCache', () => {
  let cache: FederationCache;
  const alice: FederatedSearchContext = { principalId: 'alice', policyRevision: 'p1', contentRevision: 'c1', allowedDomeIds: ['local'] };
  const request = (context: FederatedSearchContext = alice) => ({ query: 'test', domeIds: ['local'], maxResults: 10, context });
  const response = (results = [makeResult('a.md', 'snippet a')]): FederatedSearchResponse => ({
    results,
    sources: [{ id: 'local', name: 'Local', status: 'ok', count: results.length, latencyMs: 1 }],
    totalMs: 3,
  });

  beforeEach(() => {
    vi.useFakeTimers();
    cache = new FederationCache(10, 60000); // 10 entries, 60s TTL
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns null for uncached query', () => {
    expect(cache.get(request())).toBeNull();
  });

  it('stores and retrieves results', () => {
    const cached = response();
    cache.set(request(), cached);
    expect(cache.get(request())).toEqual(cached);
  });

  it('returns null after TTL expires', () => {
    cache.set(request(), response());
    vi.advanceTimersByTime(61000);
    expect(cache.get(request())).toBeNull();
  });

  it('different query+dome combos are separate entries', () => {
    cache.set({ ...request(), query: 'query1' }, response([makeResult('a.md', 'a')]));
    cache.set({ ...request(), query: 'query2' }, response([makeResult('b.md', 'b')]));
    expect(cache.get({ ...request(), query: 'query1' })!.results).toHaveLength(1);
    expect(cache.get({ ...request(), query: 'query2' })!.results).toHaveLength(1);
  });

  it('different dome order produces same cache key', () => {
    cache.set({ ...request(), query: 'q', domeIds: ['a', 'b'] }, response([makeResult('x.md', 'x')]));
    expect(cache.get({ ...request(), query: 'q', domeIds: ['b', 'a'] })).not.toBeNull();
  });

  it('evicts oldest when full', () => {
    for (let i = 0; i < 10; i++) {
      cache.set({ ...request(), query: `q${i}` }, response([makeResult(`${i}.md`, `${i}`)]));
    }
    expect(cache.size).toBe(10);
    cache.set({ ...request(), query: 'new' }, response([makeResult('new.md', 'new')]));
    expect(cache.size).toBe(10); // still 10, oldest evicted
  });

  it('invalidate clears everything', () => {
    cache.set({ ...request(), query: 'a' }, response([makeResult('a.md', 'a')]));
    cache.set({ ...request(), query: 'b' }, response([makeResult('b.md', 'b')]));
    cache.invalidate();
    expect(cache.size).toBe(0);
  });

  it('isolates entries by principal', () => {
    cache.set(request(), response());
    expect(cache.get(request({ ...alice, principalId: 'bob' }))).toBeNull();
  });

  it('treats a policy revision after revoke as a miss', () => {
    cache.set(request(), response());
    expect(cache.get(request({ ...alice, policyRevision: 'p2' }))).toBeNull();
  });

  it('treats a content revision change as a miss', () => {
    cache.set(request(), response());
    expect(cache.get(request({ ...alice, contentRevision: 'c2' }))).toBeNull();
  });

  it('keeps source attribution in a cache hit', () => {
    const cached = response();
    cache.set(request(), cached);
    expect(cache.get(request())?.sources).toEqual(cached.sources);
  });
});
