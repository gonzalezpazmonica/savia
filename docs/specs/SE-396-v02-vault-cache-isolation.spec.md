---
status: IMPLEMENTING
implementation_state: IMPLEMENTED_PENDING_HUMAN_REVIEW
approval: "Operadora 2026-09-09: aprobación global de trabajo pendiente"
priority: P1
developer_type: agent-single
created: 2026-09-21
parent: SE-396
related_specs: [SE-282, SE-291, SE-395]
risk: L2
---

# SE-396 V02 — Aislamiento e integridad de cache federada

## 1. Contexto y objetivo

V01 aisló los motores de conocimiento MCP por dome. La cache de búsqueda
federada aún identifica entradas sólo por consulta y lista de domes, devuelve
un `sources` vacío en hits y no aplica `maxTotalResults`. Esto permite reutilizar
resultados entre principales o revisiones de policy/contenido incompatibles y
pierde provenance.

V02 hace que una entrada sólo sea reutilizable bajo el mismo contexto autorizado,
conserva attribution y aplica un límite total duro. No crea policy ni decide
acceso: el llamante debe entregar el contexto emitido después de autorización.

## 2. Contrato técnico

```typescript
interface FederatedSearchContext {
  principalId: string;
  policyRevision: string;
  contentRevision: string;
}

search(
  query: string,
  context: FederatedSearchContext,
  maxResults?: number,
): Promise<FederatedSearchResponse>
```

La clave efectiva contiene consulta, domes ordenados, `principalId`,
`policyRevision`, `contentRevision` y `maxResults`. Cambiar cualquiera produce
miss. Una revocación debe publicar una nueva `policyRevision`; por tanto una
entrada anterior no puede ser hit después de revoke.

La cache almacena la respuesta completa (`results` y `sources`). En hit sólo
`totalMs` cambia a `0`; attribution no se reconstruye ni se elimina. Tanto miss
como hit retornan como máximo `maxTotalResults` resultados.

## 3. Reglas y límites

1. Los tres campos de contexto son strings no vacíos; contexto ausente o vacío
   falla antes de consultar búsqueda local o remota.
2. `maxResults` es un entero positivo.
3. `maxTotalResults` es un entero positivo y limita la salida total aunque haya
   más domes o pesos.
4. La cache conserva LRU, TTL y máximo de entradas existentes.
5. No se guardan tokens, consultas completas en receipts ni nombres nuevos de
   principal fuera de la clave en memoria.
6. No se activa routing adaptativo, multi-hop ni una nueva fuente de policy.

## 4. Escenarios ejecutables

### V02-AC1 — principal aislado

Given una respuesta cacheada por `alice`, when `bob` repite consulta y revisiones,
then obtiene miss.

### V02-AC2 — revoke/policy revision

Given una respuesta de `alice` con policy `p1`, when revoke produce `p2`, then la
consulta con `p2` obtiene miss y nunca reutiliza `p1`.

### V02-AC3 — revisión de contenido

Given una respuesta bajo contenido `c1`, when la revisión pasa a `c2`, then la
consulta obtiene miss.

### V02-AC4 — provenance en hit

Given una respuesta con sources local y remota, when hay hit, then se devuelven
exactamente esos sources y `totalMs=0`.

### V02-AC5 — presupuesto duro

Given resultados locales y remotos por encima de `maxTotalResults=2`, when se
busca en miss y después en hit, then ambas respuestas contienen exactamente dos
resultados como máximo.

### V02-AC6 — fail closed de contexto

Given cualquier campo de contexto vacío, when se busca, then lanza error antes de
invocar el motor local o clientes remotos.

## 5. Archivos

- Modificar `projects/savia-vaults/src/federation/types.ts`.
- Modificar `projects/savia-vaults/src/federation/cache.ts`.
- Modificar `projects/savia-vaults/src/federation/search.ts`.
- Modificar tests unitarios de cache y búsqueda federada.
- Actualizar specs/roadmap/planning/changelog tras evidencia verde.

## 6. Estrategia y matriz de compliance

Primero se añaden AC1–AC6 y se registra fallo contra la implementación anterior.
Después se aplica el mínimo cambio y se ejecutan tests dirigidos, suite completa,
typecheck y gates del workspace. Código fuente sin test no acredita cumplimiento.

| AC | Evidencia requerida |
|---|---|
| V02-AC1 | test de cache, distinto principal = miss |
| V02-AC2 | test de cache, nueva policy revision = miss |
| V02-AC3 | test de cache, nueva content revision = miss |
| V02-AC4 | test de engine, hit conserva sources |
| V02-AC5 | test de engine, miss e hit respetan límite |
| V02-AC6 | test de engine, contexto inválido no ejecuta local |

## 7. Stop y rollback

STOP si el contexto autorizado requiere inventar una autoridad o storage nuevo.
Rollback: revertir esta slice restaura la API y cache anteriores; no hay migración
ni datos persistentes. Revisión humana y CI son obligatorias antes de merge.

## 8. Amendment A — selección autorizada antes de cache (append-only)

La revisión de implementación detectó que identificar policy por revisión no
impide por sí solo consultar un dome no autorizado. El contexto añade
`allowedDomeIds: string[]`, conjunto calculado por la autoridad llamante. El
engine filtra local y remotos contra ese conjunto antes de lookup o llamadas;
un destino ausente ejecuta cero búsquedas. La clave usa los domes efectivos ya
filtrados. El contexto se copia al entrar para impedir que una mutación durante
I/O asíncrona envenene otra revisión. Este amendment amplía V02-AC6: un remote
denegado no recibe llamadas.

## 9. Evidencia de implementación — 2026-09-21

TDD rojo: 14/16 tests dirigidos fallaron contra la cache anterior; la regresión
del amendment falló porque el remote denegado recibió una llamada. Tras el cambio,
18/18 tests dirigidos pasan. Suite SaviaVaults: 349/349 tests; typecheck, build y
lint correctos. La primera ejecución sandboxed produjo 3 fallos E2E por `EPERM`
en sockets IPC/localhost; la repetición con sockets locales habilitados pasó.

| AC | Test | Estado |
|---|---|---|
| V02-AC1 | `cache.test.ts` — principal aislado | PASS |
| V02-AC2 | `cache.test.ts` — policy revision tras revoke | PASS |
| V02-AC3 | `cache.test.ts` — content revision | PASS |
| V02-AC4 | `cache.test.ts` y `search.test.ts` — sources en hit | PASS |
| V02-AC5 | `search.test.ts` — límite en miss/hit | PASS |
| V02-AC6 | `search.test.ts` — inválido/remote no autorizado/snapshot TOCTOU | PASS |

Evidencia local/de integración; no acredita revisión humana, merge, despliegue
ni graduación del experimento adaptativo SE-395.
