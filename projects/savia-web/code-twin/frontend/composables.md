---
module_id: FrontendComposables
layer: frontend
version: "1.0.0"
last_sync: "2026-06-06T10:00:00Z"
token_budget: 280
stale_after_days: 14
depends_on:
  - FrontendStores
provides:
  - useBridge
  - useSSE
status: STABLE
---
# Frontend Composables — savia-web

## useBridge

**Returns**: `{ get, post, healthCheck, baseUrl, headers }`

**baseUrl()**: reads `useAuthStore().useTls`, `host`, `port` → `proto://host:port`
**headers()**: returns `{ 'Content-Type': 'application/json', 'Authorization': 'Bearer <token>' }`
**get<T>(path)**: `fetch(baseUrl+path, {headers})` → `res.json() as T` | `null` on non-ok or error
**post<T>(path, body)**: `fetch(baseUrl+path, {method:'POST', body:JSON.stringify(body), headers})` → `res.json()` | `null`
**healthCheck()**: `GET /dashboard` → `res.ok` as boolean; swallows errors → `false`

**Error contract**: all methods return `null` / `false` on failure — NEVER throw

## useSSE

**Returns**: `{ connect, disconnect, onMessage }`
**Protocol**: EventSource to `baseUrl/events`
**Auth** (SE-528): `fetch` con cabecera `Authorization: Bearer` (solo si hay token en memoria) y `credentials: 'include'` para la sesión opaca del puente. Nunca credenciales en la URL: el puente responde 401
**reconnect**: auto-reconnect on `onerror` with 3s backoff (max 5 attempts)
