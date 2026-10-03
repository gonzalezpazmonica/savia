---
name: flow-sprint-create
description: Create a new sprint with goal and dates
argument-hint: "<goal> <start_date> <end_date> [capacity_h]"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Create Sprint

**Arguments:** $ARGUMENTS

## Parámetros

- `<goal>` — Sprint goal statement
- `<start_date>` — YYYY-MM-DD
- `<end_date>` — YYYY-MM-DD
- `[capacity_h]` — Team capacity in hours (default: 120)

## Ejecución

1. Execute: `bash scripts/savia-flow-sprint.sh create <goal> <start_date> <end_date> [capacity_h]`
2. Crea `SPR-YYYY-NN` (YYYY = anio de `start_date`, NN = max + 1) con `status: active`.
   Valida fechas reales, fin >= inicio, `capacity_h` entero > 0 y goal no vacio (exit 2).
