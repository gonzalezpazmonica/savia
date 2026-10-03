---
name: flow-velocity
description: Show historical velocity metrics
argument-hint: ""
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Velocity Metrics

**Arguments:** $ARGUMENTS

## Ejecución

Execute: `bash scripts/savia-flow-sprint.sh velocity`

## Output

Lista todos los sprints del equipo con status, campo `velocity` y `capacity_h`.
El campo `velocity` no se recalcula al cerrar (queda en 0 salvo edicion manual).
