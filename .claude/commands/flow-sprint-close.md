---
name: flow-sprint-close
description: Close sprint, move pending tasks to backlog, generate report
argument-hint: "<sprint_id>"
allowed-tools: [Bash, Read]
model_tier: mid
context_cost: medium
tier: core
---

# Close Sprint

**Arguments:** $ARGUMENTS

## Parámetros

- `<sprint_id>` — Sprint identifier (SPR-YYYY-NN)

## Ejecución

1. Execute: `bash scripts/savia-flow-sprint.sh close <sprint_id>`
2. Marca `status: closed` y `closed: <hoy>`. Cerrar un sprint ya cerrado no cambia nada
   (conserva la fecha original). Sprint inexistente: exit 1; ID mal formado: exit 2.

## Limitaciones (no implementado)

El script NO mueve tareas pendientes, NO calcula velocity ni genera informe:
las tareas no enlazan con el sprint de forma fiable. Hacerlo a mano con
`/flow-velocity` y `/flow-task-move`.
