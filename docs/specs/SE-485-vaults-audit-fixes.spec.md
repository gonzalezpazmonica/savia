---
status: APPROVED
priority: P2
developer_type: agent-single
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SE-481, SE-482]
origin: auditoría SVTC-00 (PR #1420, hallazgos N1-N5); decisión de la operadora 2026-10-30 (AskUserQuestion) — spec y arreglo ya
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-485 — Vaults: cinco fallos de la auditoría SVTC-00

La auditoría reprodujo cinco fallos nuevos con scripts ejecutables, en `projects/savia-vaults/eval/audit-svtc00/` (#1420). Ninguno es una fuga entre cúpulas.

## Requisitos

### R1 (N1) — Backlinks por nombre
`resolveBacklinks` (`src/knowledge/wikilink-validator.ts`) compara el destino del enlace con la ruta, así que `[[destino]]` nunca resuelve a `destino.md`.
- Resolver los destinos con la **misma** función de resolución de wikilinks que usa el grafo: nombre sin extensión, ruta relativa y alias si existen.
- Los backlinks siguen filtrando las notas fuera de nivel, en cuarentena o sin permiso.

### R2 (N2) — A2A `/stats`
`/stats` ignora `?dome=` y falla en modo usuario. Debe:
- respetar `dome`;
- autorizar por usuario como el resto de rutas A2A;
- devolver solo los recuentos de lo que ese principal puede ver.

**Sin contadores de lo oculto.** `outOfLevel` y `quarantined` se reservan a la operadora (la vista MCP local de `vault_health`), nunca a A2A, porque revelan existencia.

### R3 (N3) — A2A `/context/<nota>` de una nota fuera de nivel o en cuarentena
Hoy responde 500. Debe responder **exactamente igual** que una nota inexistente: mismo código (404), mismo cuerpo y sin diferencias observables de cabeceras. Así no queda un oráculo de existencia (INV-04 de SE-482). Las demás excepciones siguen siendo 500, sin detalles internos en el cuerpo.

### R4 (N4) — Identificadores inexistentes
- Una consulta que es (o contiene como término dominante) un identificador con forma de código (`[A-Z]{1,5}-\d[\d-]*`) y no aparece literal en ningún documento permitido no debe presentar como respuesta documentos con identificadores parecidos.
- `vault_rag` y `vault_search` marcan esos resultados con `exactMatch:false` y añaden a `degradation` o a los avisos la nota «identificador no encontrado literalmente». Los vecinos no se ocultan, porque pueden ser útiles; se marcan.
- Si el identificador sí existe, el documento exacto queda primero (ya lo garantiza SE-481).

### R5 (N5) — `includeStale` en el resto de vistas
- `vault_search` y A2A `/search` aceptan `includeStale`, con el mismo valor por defecto que `vault_rag` y la misma función `excludedReason`.
- `vault_read` de una nota obsoleta sigue sirviéndola (lectura directa), pero añade en los metadatos `stale: <motivo>`.
- El valor por defecto de `vault_search` no cambia si eso rompe a clientes existentes. En ese caso se documenta y el opt-in queda explícito (AC-5 decide con evidencia de los tests existentes).

## Criterios de aceptación

- **AC-1:** cada script de reproducción de N1-N5 de la auditoría, convertido en test vitest, falla contra main y pasa con el arreglo.
- **AC-2 (N3):** respuesta A2A idéntica, byte a byte en el cuerpo y en el código, para una nota oculta y una inexistente.
- **AC-3 (N2):** un usuario con permiso solo en la cúpula X no obtiene recuentos de Y, ni de lo oculto en X.
- **AC-4 (N4):** `CT-2099-999` devuelve resultados con `exactMatch:false` y el aviso. `CT-2026-047` (existente) devuelve su documento primero con `exactMatch:true`.
- **AC-5 (N5):** `includeStale:false` excluye lo obsoleto en `vault_search` y A2A `/search`. La decisión sobre el valor por defecto queda documentada en la PR.
- **AC-6:** suite completa de savia-vaults en verde, más tsc y eslint.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor savia-vaults (MCP/A2A) | stdio MCP | stdio MCP, mismo binario |

### Verification protocol

- [ ] Tests vitest del servidor (independientes del frontend)
- [ ] Sin hooks nuevos

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en el servidor, independiente del frontend)
