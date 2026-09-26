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
- `--ready` — Show only PBIs with no open blockers (ready-to-start queue)

## Ejecución

- Default: `bash scripts/savia-flow-sprint.sh board <sprint_id>`
- Con `--ready`: `bash scripts/savia-flow-sprint.sh board --ready <sprint_id>`

## Output

**Default**: Shows board columns with counts per state.

**`--ready`** (SPEC-112): PBIs del sprint sin `blockedBy` abierto, listos para empezar.
