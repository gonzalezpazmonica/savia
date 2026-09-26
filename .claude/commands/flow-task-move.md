---
name: flow-task-move
description: Move task between board columns (todo, in-progress, review, done)
argument-hint: "<task_id> <new_status>"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Move Task

**Arguments:** $ARGUMENTS

> Uso: `/flow-task-move TASK-2026-0001 in-progress`

## Parámetros

- `<task_id>` — Task identifier (TASK-YYYY-NNNN)
- `<new_status>` — todo|in-progress|review|done

## Ejecución

1. Execute: `bash scripts/savia-flow-tasks.sh move <task_id> <new_status>`
2. Mostrar cambio de columna
