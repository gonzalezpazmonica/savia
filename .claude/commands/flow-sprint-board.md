---
name: flow-sprint-board
description: Display sprint board with task counts by column
argument-hint: "<sprint_id>"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Sprint Board

**Arguments:** $ARGUMENTS

## Parámetros

- `<sprint_id>` — Sprint identifier
- `--ready` — NO implementado en el script (SPEC-112 pendiente); no pasarlo

## Ejecución

- Default: `bash scripts/savia-flow-sprint.sh board <sprint_id>`


## Output

Metadatos del sprint: goal, status, start_date, end_date, capacity_h, closed.
El script no cuenta tareas por columna. Sprint inexistente: exit 1.
