# SE-283 — Savia Federate: Security Hardening Corrections

> **Source**: SE-282 security audit (2026-07-30) — 11 findings, 5 recommendations
> **Parent**: SE-281 (Gap Corrections), SE-282 (Savia Federate)

## Metadatos

- **Task ID:** SE-283
- **PBI padre:** Era 200 — Savia Intelligence Layer
- **developer_type:** agent-single
- **status:** DONE — Implemented: circuit-breaker, audit-logger, hash-verify (3 modules, 6 tests passing on real code). Not implemented: TLS support, client-side rate limiting, token rotation CLI (see SE-286 S3).
- **nota 2026-11-20:** `hash-verify` retirado (ver nota al final y SE-287 AC-4.5); hoy quedan circuit-breaker y audit-logger.
- **stack:** TypeScript + Node.js 22+ + bash
- **estimacion:** 10h (5 slices)

## Problema

La auditoria de seguridad de Savia Federate (SE-282) identifico 11 hallazgos. De ellos, 2 son MEDIUM (requieren accion) y 5 son recomendaciones de hardening para produccion. Sin estas correcciones, un despliegue federado en red real es vulnerable a:

- **F-02**: Tokens de autenticacion transmitidos en texto plano (sin TLS)
- **F-03**: Sin rate limiting del lado cliente → dome remoto saturable
- **R-01**: Sin registro de auditoria → queries federadas sin trazabilidad
- **R-02**: Sin rotacion de tokens → tokens comprometidos permanecen validos
- **R-03**: Sin verificacion de integridad → resultados federados no autenticados
- **R-04**: Sin circuit breaker → dome caido se reintenta indefinidamente

## Objetivo

Cerrar los 6 hallazgos accionables de la auditoria, llevando Savia Federate a un nivel de seguridad apto para produccion en red.

## Implementacion

### Slice 1 — TLS Support (2h)

**Finding**: F-02 — Auth tokens transmitted in cleartext.

**Solucion**: Añadir soporte TLS al servidor A2A y al cliente de federacion.

```typescript
// A2A server: accept --tls --cert <path> --key <path>
// A2A client: accept https:// URLs, configurable rejectUnauthorized

interface A2AServerOptions {
  tls?: { cert: string; key: string };
}

interface A2AClientOptions {
  rejectUnauthorized: boolean; // default true in production
}
```

**CLI**:
```bash
savia-vaults serve --transport a2a --tls --cert cert.pem --key key.pem
savia-vaults federate add prod https://vault.example.com:8923
```

**Config schema**: `server.tls` section with `enabled`, `cert`, `key`.

### Slice 2 — Client-Side Rate Limiting (2h)

**Finding**: F-03 — No rate limiting on A2A client side.

**Solucion**: Token bucket rate limiter en el cliente A2A, compartido entre todos los domes federados.

```typescript
class A2AClientRateLimiter {
  private limiter: RateLimiter; // reused from SE-281
  constructor(maxRequestsPerMinute: number = 60);
  acquire(): Promise<void>; // waits for token before sending
}
```

Integrado en `A2AClient.search()`: antes de enviar request, esperar token. Si no hay tokens disponibles en 5s, skip dome (no bloquear).

**Config**: `federation.clientRateLimit.maxRequestsPerMinute` (default 60).

### Slice 3 — Federation Audit Log (2h)

**Finding**: R-01 — No audit trail for federated queries.

**Solucion**: Log JSONL de todas las queries federadas.

```
output/federation-audit.jsonl:
{"ts":"2026-07-30T22:00:00Z","query":"architecture","dome":"specs","status":"ok","results":3,"latency_ms":45}
{"ts":"2026-07-30T22:00:05Z","query":"architecture","dome":"team-docs","status":"timeout","results":0,"latency_ms":5001}
```

**Implementacion**: `FederationAuditLogger` class, writes to `output/federation-audit.jsonl`. Rotacion diaria (max 10MB, gzipped).

### Slice 4 — Circuit Breaker (2h)

**Finding**: R-04 — Dome caido se reintenta en cada busqueda.

**Solucion**: Circuit breaker con 3 estados: CLOSED (normal), OPEN (dome disabled after N failures), HALF_OPEN (probe after cooldown).

```typescript
class CircuitBreaker {
  private failures: Map<string, number> = new Map();
  private state: Map<string, 'CLOSED' | 'OPEN' | 'HALF_OPEN'> = new Map();
  private threshold: number = 5;        // failures before opening
  private cooldownMs: number = 300000;   // 5 min before HALF_OPEN probe
  private probeTimeout: number = 2000;   // 2s probe timeout
}
```

Reemplaza el health tracking actual (healthy/degraded/unhealthy) con estados de circuit breaker. Mejor que el sistema actual porque:
- Cooldown temporal (no permanente)
- HALF_OPEN permite recuperacion automatica
- CLOSED tras probe exitoso

### Slice 5 — Token Rotation + Content Hash Verification (2h)

**Findings**: R-02 (token rotation) + R-03 (hash verification).

**Token rotation**:
```bash
savia-vaults federate rotate-token specs
# Generates new token, updates config, logs rotation event
```

**Content hash verification** (RETIRADO 2026-11-20, ver nota al final; el código de abajo es solo histórico): Tras recibir resultados federados, verificar que el content hash coincide con el snippet. Si no coincide → descartar resultado + warning log.

```typescript
function verifyContentHash(result: FederatedSearchResult): boolean {
  const computed = hashContent(result.snippet);
  return computed === result.contentHash;
}
```

## Criterios de Aceptacion

**AC-1**: `savia-vaults serve --tls --cert cert.pem --key key.pem` inicia servidor HTTPS.

**AC-2**: Cliente A2A acepta URLs `https://` y verifica certificados.

**AC-3**: Rate limiter bloquea tras 60 req/min compartidos entre todos los domes.

**AC-4**: `output/federation-audit.jsonl` contiene entrada por cada query federada.

**AC-5**: Circuit breaker desactiva dome tras 5 fallos consecutivos, reintenta a los 5 min.

**AC-6**: Dome se reactiva automaticamente tras probe exitoso en HALF_OPEN.

**AC-7**: `savia-vaults federate rotate-token specs` genera nuevo token y actualiza config.

**AC-8**: Resultados federados con hash incorrecto se descartan (no llegan al usuario).

## File Inventory

| Accion | Path |
|---|---|
| CREATE | `projects/savia-vaults/src/federation/circuit-breaker.ts` |
| CREATE | `projects/savia-vaults/src/federation/audit-logger.ts` |
| CREATE | `projects/savia-vaults/src/federation/hash-verify.ts` (retirado 2026-11-20, ver nota) |
| MODIFY | `projects/savia-vaults/src/federation/a2a-client.ts` (TLS + rate limit + ~~hash verify~~ retirado) |
| MODIFY | `projects/savia-vaults/src/server/a2a.ts` (TLS support) |
| MODIFY | `projects/savia-vaults/src/cli/index.ts` (--tls, rotate-token) |
| MODIFY | `projects/savia-vaults/src/config/schema.json` (tls, clientRateLimit) |
| CREATE | `projects/savia-vaults/tests/unit/federation/circuit-breaker.test.ts` |
| CREATE | `projects/savia-vaults/tests/unit/federation/audit-logger.test.ts` |
| CREATE | `projects/savia-vaults/tests/unit/federation/hash-verify.test.ts` (retirado 2026-11-20) |
| MODIFY | `projects/savia-vaults/docs/FEDERATION.md` (security hardening section) |
| MODIFY | `projects/savia-vaults/docs/FEDERATION.es.md` (seccion hardening) |

**Retirada/enmienda 2026-11-20 por decisión de la operadora (pregunta interactiva):** `hash-verify.ts` y su test se retiran (hash de 32 bits que el cliente local recalcula sobre el mismo snippet que comprobaría: salía bien por construcción, no protegía nada y no tenía consumidor; la integridad de resultados remotos queda sin cubrir). Ver SE-287 AC-4.5.
