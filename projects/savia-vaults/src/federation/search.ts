import { SearchEngine } from '../search/index.js';
import { FederationRegistry } from './registry.js';
import { A2AClient } from './a2a-client.js';
import { FederationCache } from './cache.js';
import type { FederatedDome, FederatedSearchContext, FederatedSearchResult, FederatedSearchResponse } from './types.js';

export class FederatedSearchEngine {
  private local: SearchEngine; private registry: FederationRegistry; private client: A2AClient; private cache: FederationCache; private localTimeout: number; private maxTotalResults: number;

  constructor(local: SearchEngine, registry: FederationRegistry, opts: { localTimeout?: number; maxTotalResults?: number; cacheTtlMs?: number } = {}) {
    if (opts.maxTotalResults !== undefined && (!Number.isInteger(opts.maxTotalResults) || opts.maxTotalResults <= 0)) throw new Error('maxTotalResults must be a positive integer');
    this.local = local; this.registry = registry; this.client = new A2AClient();
    this.cache = new FederationCache(1000, opts.cacheTtlMs ?? 300000);
    this.localTimeout = opts.localTimeout ?? 2000; this.maxTotalResults = opts.maxTotalResults ?? 50;
  }

  async search(query: string, context: FederatedSearchContext, maxResults = 10): Promise<FederatedSearchResponse> {
    this.validateContext(context);
    if (!Number.isInteger(maxResults) || maxResults <= 0) throw new Error('maxResults must be a positive integer');
    const start = Date.now();
    const authorizedContext: FederatedSearchContext = {
      principalId: context.principalId,
      policyRevision: context.policyRevision,
      contentRevision: context.contentRevision,
      allowedDomeIds: [...context.allowedDomeIds],
    };
    const allowedDomeIds = new Set(authorizedContext.allowedDomeIds);
    const localAllowed = allowedDomeIds.has('local');
    const domes = this.registry.getHealthy().filter(dome => allowedDomeIds.has(dome.id));
    const domeIds = [...(localAllowed ? ['local'] : []), ...domes.map(d => d.id)];
    const cacheRequest = { query, domeIds, maxResults, context: authorizedContext };
    const cached = this.cache.get(cacheRequest);
    if (cached) return { ...cached, totalMs: 0 };

    const localResults = localAllowed
      ? await Promise.race([this.localSearch(query, maxResults), new Promise<FederatedSearchResult[]>(r => setTimeout(() => r([]), this.localTimeout))])
      : [];
    const remoteResults = await Promise.all(domes.map(d => this.client.search(d, query, Math.ceil(maxResults * d.weight))));
    const totalLimit = Math.min(this.maxTotalResults, maxResults * domeIds.length);
    const allResults = this.merge(localResults, remoteResults, domes, maxResults, totalLimit);

    for (let i = 0; i < domes.length; i++) {
      const r = remoteResults[i];
      if (r.status !== 'ok') this.registry.updateStatus(domes[i].id, domes[i].status === 'healthy' ? 'degraded' : 'unhealthy');
      else if (domes[i].status !== 'healthy') this.registry.updateStatus(domes[i].id, 'healthy');
    }
    const response: FederatedSearchResponse = { results: allResults, sources: [...(localAllowed ? [{ id: 'local', name: 'Local', status: 'ok' as const, count: localResults.length, latencyMs: 0 }] : []), ...domes.map((d, i) => ({ id: d.id, name: d.name, status: remoteResults[i].status, count: remoteResults[i].results.length, latencyMs: remoteResults[i].latencyMs }))], totalMs: Date.now() - start };
    this.cache.set(cacheRequest, response);
    return response;
  }

  private async localSearch(query: string, maxResults: number): Promise<FederatedSearchResult[]> {
    return this.local.search({ query, maxResults }).map(r => ({ path: r.path, score: r.score, snippet: r.snippet, tags: r.tags, source: 'local', contentHash: this.hash(r.snippet || r.path) }));
  }

  private merge(local: FederatedSearchResult[], remotes: Array<{ results: FederatedSearchResult[]; status: string; latencyMs: number }>, domes: FederatedDome[], max: number, totalLimit: number): FederatedSearchResult[] {
    const seen = new Set<string>(); const merged: FederatedSearchResult[] = [];
    for (const r of local) { if (merged.length >= totalLimit) break; if (!seen.has(r.contentHash)) { seen.add(r.contentHash); merged.push(r); } }
    const rem = remotes.map((r, i) => ({ dome: domes[i], ...r })).filter(r => r.status === 'ok').sort((a, b) => b.dome.weight - a.dome.weight);
    const queues = rem.map(r => [...r.results]); const maxes = rem.map(r => Math.ceil(max * r.dome.weight));
    while (merged.length < totalLimit && queues.some(q => q.length > 0)) {
      for (let i = 0; i < queues.length && merged.length < totalLimit; i++) {
        if (queues[i].length === 0) continue;
        if (merged.filter(r => r.source === rem[i].dome.id).length >= maxes[i]) { queues[i] = []; continue; }
        const r = queues[i].shift()!; if (!seen.has(r.contentHash)) { seen.add(r.contentHash); merged.push(r); }
      }
    }
    return merged;
  }

  async healthCheckAll(): Promise<Array<{ id: string; name: string; healthy: boolean; latencyMs: number }>> {
    const domes = this.registry.listEnabled();
    return Promise.all(domes.map(async d => { const r = await this.client.healthCheck(d); this.registry.updateStatus(d.id, r.healthy ? 'healthy' : 'unhealthy'); return { ...r, id: d.id, name: d.name }; }));
  }

  private validateContext(context: FederatedSearchContext): void {
    for (const field of ['principalId', 'policyRevision', 'contentRevision'] as const) {
      if (!context || typeof context[field] !== 'string' || context[field].trim() === '') throw new Error(`${field} must be a non-empty string`);
    }
    if (!Array.isArray(context.allowedDomeIds) || context.allowedDomeIds.some(id => typeof id !== 'string' || id.trim() === '')) throw new Error('allowedDomeIds must be an array of non-empty strings');
  }

  private hash(s: string): string { let h = 0; for (let i = 0; i < s.length; i++) { h = ((h << 5) - h) + s.charCodeAt(i); h = h & h; } return Math.abs(h).toString(16).padStart(8, '0'); }
}
