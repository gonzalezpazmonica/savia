---
name: flow-burndown
description: Show sprint burndown chart data
argument-hint: "<sprint_id>"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Burndown Chart

**Arguments:** $ARGUMENTS

## Parámetros

- `<sprint_id>` — Sprint identifier

## Ejecución

Execute: `bash scripts/savia-flow-sprint.sh burndown <sprint_id>`

## Output

NO implementado: el script responde exit 2. Las tareas no registran historico
diario por columna; no inventar datos de burndown.
