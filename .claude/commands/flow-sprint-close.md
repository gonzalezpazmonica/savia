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

1. Move incomplete tasks to backlog
2. Calculate velocity
3. Generate summary report
4. Display final stats

## Resultado

📄 Report guardado en: reports/{sprint_id}-summary.md
