import type { FederatedSearchContext, FederatedSearchResponse } from './types.js';

export interface FederationCacheRequest {
  query: string;
  domeIds: string[];
  maxResults: number;
  context: FederatedSearchContext;
}

interface CacheEntry { response: FederatedSearchResponse; timestamp: number; }

export class FederationCache {
  private cache: Map<string, CacheEntry> = new Map();
  private maxSize: number; private ttlMs: number;
  constructor(maxSize = 1000, ttlMs = 300000) { this.maxSize = maxSize; this.ttlMs = ttlMs; }

  private buildKey(request: FederationCacheRequest): string {
    return JSON.stringify([
      request.query,
      [...request.domeIds].sort(),
      request.maxResults,
      request.context.principalId,
      request.context.policyRevision,
      request.context.contentRevision,
    ]);
  }

  get(request: FederationCacheRequest): FederatedSearchResponse | null {
    const key = this.buildKey(request); const entry = this.cache.get(key);
    if (!entry || Date.now() - entry.timestamp > this.ttlMs) { if (entry) this.cache.delete(key); return null; }
    this.cache.delete(key); this.cache.set(key, entry); return this.clone(entry.response);
  }

  set(request: FederationCacheRequest, response: FederatedSearchResponse): void {
    const key = this.buildKey(request);
    if (this.cache.size >= this.maxSize) { const oldest = this.cache.keys().next().value; if (oldest) this.cache.delete(oldest); }
    this.cache.set(key, { response: this.clone(response), timestamp: Date.now() });
  }

  invalidate(): void { this.cache.clear(); }
  get size(): number { return this.cache.size; }

  private clone(response: FederatedSearchResponse): FederatedSearchResponse {
    return {
      results: response.results.map(result => ({ ...result, tags: [...result.tags] })),
      sources: response.sources.map(source => ({ ...source })),
      totalMs: response.totalMs,
    };
  }
}
