---
name: flow-timesheet-report
description: Generate timesheet report for date range
argument-hint: "<@handle> <from_date> <to_date>"
allowed-tools: [Bash, Read]
model_tier: mid
context_cost: low
tier: core
---

# Timesheet Report

**Arguments:** $ARGUMENTS

## Parámetros

- `<@handle>` — Developer
- `<from_date>` — YYYY-MM-DD
- `<to_date>` — YYYY-MM-DD

## Ejecución

1. Execute: `bash scripts/savia-flow-timesheet.sh report <@handle> <from_date> <to_date>`
2. Aggregate and display totals
