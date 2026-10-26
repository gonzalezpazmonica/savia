---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-26
author: Savia
phase: A
risk: L2
related_specs: [SE-343, SE-226, SE-445, SE-332, SE-471]
origin: síntesis de una tesis sobre calendario agéntico y sprint nocturno; diseño en el repo de investigación privado
---

# SE-472 — Vigencia de la autoridad comprobada antes de cada tarea nocturna

## Problema

Una delegación que caduca o se revoca debe detener las acciones nuevas que cubría. Hoy
`scripts/overnight-sprint-loop.sh` (SE-226) comprueba prerrequisitos al arrancar (doble opt-in SPEC-186 y baseline) y
entre tareas no vuelve a comprobar ninguna autoridad. `scripts/operator-grant.sh` ya emite grants con `expires_at` (TTL
de 24 h para `autonomy:*`, SE-343) y tiene `check --scope` con salida `0 vigente | 1 no/expirado | 2 inválido | 3 sin
grant`, pero solo lo consulta `push-pr.sh` para el merge. Un lote largo puede seguir lanzando tareas después de que la
autorización caduque o se revoque.

## Valor y evidencia

- Hueco de seguridad real y pequeño: la ausencia de la persona no es aprobación, y una autorización vencida tampoco.
- Valor limitado mientras la noche corra sobre la orquestación por cola y no sobre esta skill: por eso P2. El gancho se
  escribe contra una interfaz para que la cola pueda adoptarlo igual.

## Alcance (slice S)

| Slice | Entrega |
|---|---|
| S1 | Antes de cada tarea, el bucle llama a `check_authority` (función en `scripts/lib/`), que por defecto ejecuta `bash scripts/operator-grant.sh check --scope autonomy:overnight` (scope configurable con `OVERNIGHT_GRANT_SCOPE`). Salida 0: sigue. Salida 1, 2 o 3: **no arranca tareas nuevas**; las pendientes pasan a `suspended` con motivo `authority_expired`, `authority_invalid` o `authority_missing` en `state.json` y en el audit log (`output/agent-runs/`). La tarea en curso no se mata: termina o agota su time-box (cierre seguro). |
| S2 | El resumen de la noche incluye «N tareas suspendidas por vigencia»; SE-471 las presenta como decisión. Flag `OVERNIGHT_REQUIRE_GRANT`, **fail-closed**: sin la variable vale `true`. Desactivarlo exige `OVERNIGHT_REQUIRE_GRANT=false` explícito en la configuración local de la operadora (gitignored), nunca un valor por defecto en el repo; cada lote desactivado deja `grant-check disabled` en el audit log y la línea «control de autoridad desactivado» en la cabecera del resumen (SE-471). Mientras SE-343 no esté aprobada, desactivarlo es decisión de la operadora (D3). No se rebaja ningún gate existente. |

## Fuera de alcance

Renovar grants (nunca automático), firmar grants y aplicar el gancho a orquestaciones privadas (pueden adoptar la misma
función).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | BATS con reloj simulado: lote de 5 tareas con un grant que caduca después de la 2.ª. Se ejecutan 2, la 3.ª no arranca y las tareas 3–5 quedan `suspended` con `authority_expired`. |
| AC2 | Negativo: con grant vigente todo el lote, `results.tsv` y los estados finales coinciden con los de la versión anterior (sin regresión). |
| AC3 | Negativo: grant revocado (fichero borrado) a mitad del lote → mismo efecto con `authority_missing`. |
| AC4 | Ningún camino del bucle invoca `operator-grant.sh grant`: stub que falla el test si se llama. |
| AC5 | Con `OVERNIGHT_REQUIRE_GRANT=false` el lote corre, el audit log contiene `grant-check disabled` y el resumen de la noche lo muestra en cabecera. Negativo: sin la variable y sin grant, ninguna tarea arranca (`authority_missing`), y ningún fichero versionado asigna `OVERNIGHT_REQUIRE_GRANT=false` (grep en el test). |
| AC6 | Cada test falla si se quita el gancho (SE-456); los tests existentes de SE-226 en verde. |

## Métrica y kill criterion

- 0 tareas iniciadas tras la caducidad, en tests y en uso real.
- Rediseño si hay más de 1 parada espuria (grant vigente, check fallido por reloj o ruta) en 2 semanas de uso real.

## Riesgos

- Depende de SE-343 (PROPOSED). Si no se aprueba, la fuente de vigencia pasa a ser la caducidad del doble opt-in; la
  interfaz `check_authority` permite cambiar de fuente sin tocar el bucle.
- Paradas espurias por desfase de reloj: el check usa la misma fuente de tiempo que `operator-grant.sh`.

## Esfuerzo

S: una función, un gancho en el bucle y 6 tests.

## Decisiones pendientes de la operadora

- **D1**: scope por defecto `autonomy:overnight` o reutilizar uno existente de SE-343 (propuesta: el nuevo, más
  estrecho).
- **D2**: si la orquestación por cola adopta el gancho en el mismo slice (propuesta: no; primero S1 con sus tests).
- **D3**: mientras SE-343 siga PROPOSED, ¿se desactiva el control en local (`OVERNIGHT_REQUIRE_GRANT=false`) o se emite
  antes un grant `autonomy:overnight` con `operator-grant.sh grant`? (propuesta: emitir el grant; desactivar solo con
  registro explícito).

## Referencias cruzadas

SE-343 (grants con caducidad), SE-226 (checkpoints del bucle nocturno), SE-445 (salvaguardas de ejecución autónoma),
SE-332 (handback), SE-471 (relevo con evidencia).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/overnight-sprint-loop.sh` y `scripts/lib/` | bash invocado por la skill `overnight-sprint` | el mismo bash, invocado por la skill equivalente |
| `scripts/operator-grant.sh` | sin cambios | sin cambios |

### Verification protocol

- [ ] Los tests BATS corren sin frontend.
- [ ] La skill `overnight-sprint` arranca el mismo bucle desde los dos frontends.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: lógica en el bucle bash; ningún binding de frontend.
