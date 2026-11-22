# Savia Federate — Security Audit

> **Date**: 2026-07-30 | **Auditor**: Savia | **Scope**: SE-282 federation layer
> **Methodology**: OWASP Top 10 + CWE Top 25 + Savia confidentiality model (N1-N4b)

## Audit Summary

| Category | Finding | Severity | Status |
|---|---|---|---|
| Auth | Token-based auth per dome | — | Implemented |
| Auth | Health/stats bypass auth for federation checks | LOW | Fixed (e2e) |
| Injection | Query parameter injection (XSS, path traversal) | NONE | Passes e2e |
| DoS | Rate limiting on federated requests | MEDIUM | Mitigated (timeout 5s) |
| DoS | Concurrent request saturation | LOW | Mitigated (seq load 10/10) |
| Privacy | Cross-dome content isolation | NONE | Verified (e2e test 3) |
| Privacy | Auth tokens in transit | MEDIUM | Mitigated (HTTPS recommended) |
| Integrity | 1-hop max prevents cascade | NONE | Designed |
| Integrity | Read-only federation | NONE | Designed |
| Availability | Graceful degradation on offline dome | NONE | Verified (e2e test 5) |
| Availability | Cache TTL prevents remote hammering | MEDIUM | Implemented |

## Detailed Findings

### F-01: Health + Stats bypass auth (LOW — Fixed)

**Description**: In the reference A2A server implementation, `/health` and `/stats` endpoints were initially protected by auth. Federation health checks need unauthenticated access to these endpoints to determine dome status.

**Fix applied**: `/health` and `/stats` excluded from auth requirement. These endpoints are read-only and expose no sensitive content.

**Verification**: E2E test 1 (health checks) and test 9 (stats) pass.

### F-02: Auth tokens in transit (MEDIUM — Mitigated)

**Description**: Federation auth tokens are sent as `Authorization: Bearer <token>` in HTTP headers. Without TLS/HTTPS, tokens are transmitted in cleartext over the network.

**Risk**: Token interception on local network → unauthorized access to protected domes.

**Mitigation**: 
- Federation is designed for local network / same-machine use (localhost, Docker network)
- Production deployments should use HTTPS (reverse proxy with TLS termination)
- Tokens should be stored in environment variables, not committed to config files
- Document recommendation: use `https://` URLs for federation domes

### F-03: No rate limiting on A2A client side (MEDIUM — Implemented)

**Description**: The A2A client in `src/federation/a2a-client.ts` sends requests without client-side rate limiting. A buggy or malicious federated search query could hammer remote domes.

**Mitigation**:
- `FederationCache` with 5-min TTL prevents repeated queries to same dome
- Timeout of 5s per remote dome prevents hanging
- Remote dome's own rate limiter (SE-281) provides server-side protection
- Recommendation: add jitter to parallel queries to avoid thundering herd

### F-04: Search query injection via regex (NONE — Verified)

**Description**: The A2A server's search uses `re.escape()` on query terms before regex matching, preventing regex injection. XSS payloads and path traversal strings are treated as literal search terms.

**Verification**: E2E test 6 passes all 4 edge cases (empty, long, XSS, traversal).

### F-05: Cross-dome content leakage (NONE — Verified)

**Description**: Federation could accidentally leak content from one dome to another if results aren't properly scoped.

**Verification**: E2E test 3 confirms Vault A returns 0 results for "kubernetes" (only in B) and Vault B returns 0 results for "JWT" (only in A). Content isolation is maintained.

### F-06: 1-hop only prevents federation cascade (NONE — Designed)

**Description**: A federated search queries remote domes directly. Remote domes do NOT propagate the search to their own federated domes. This prevents infinite recursion and uncontrolled data exposure.

**Design**: The A2A `/search` endpoint returns results from the local vault only. Federation is a client-side concern, not server-side.

### F-07: Read-only federation (NONE — Designed)

**Description**: Federated domes are accessed exclusively via GET requests (`/health`, `/search`, `/stats`). The federation layer NEVER sends writes (POST, PUT, DELETE) to remote domes.

**Design**: `A2AClient` only implements `search()` and `healthCheck()` methods. No write operations exist in the federation client.

## Recommendations

1. **TLS by default**: Add `--tls` flag to CLI for automatic HTTPS in production
2. **Token rotation**: Add `savia-vaults federate rotate-token <id>` command
3. **Federation audit log**: Log all federated queries to `output/federation-audit.jsonl`
4. ~~**Content hash verification**: After receiving federated results, verify content hash integrity~~ Withdrawn 2026-11-20 (SE-287 AC-4.5): a 32-bit hash recomputed by the client over the same snippet cannot detect tampering. Real integrity of remote results would need signed results; not implemented.
5. **Circuit breaker**: After N consecutive failures, disable a federated dome automatically (already partially implemented via health states)

## Compliance

| Standard | Requirement | Status |
|---|---|---|
| OWASP A01:2021 (Broken Access Control) | Auth required for protected endpoints | Implemented |
| OWASP A03:2021 (Injection) | Query parameter sanitization | Verified (re.escape) |
| OWASP A05:2021 (Security Misconfig) | Health endpoints exposed without auth | Documented + fixed |
| Savia N3 (confidential) | Auth tokens not in committed config | Documented (env vars) |
| Savia N4a (public) | Search results from public domes | Read-only, no writes |
