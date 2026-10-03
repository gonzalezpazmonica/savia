---
name: flow-timesheet
description: Log hours spent on a task
argument-hint: "<@handle> <task_id> <hours> [notes]"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Log Timesheet

**Arguments:** $ARGUMENTS

## Parámetros

- `<@handle>` — Developer handle (la `@` es opcional; solo `[A-Za-z0-9._-]`)
- `<task_id>` — Task being worked on
- `<hours>` — Horas (> 0 y <= 24, max 2 decimales; acepta coma es_ES: `1,5`)
- `[notes]` — Optional work description

## Ejecución

Execute: `bash scripts/savia-flow-timesheet.sh log <@handle> <task_id> <hours> [notes]`

## Almacenamiento

📁 Rama `user/{handle}`, fichero `flow/timesheet/{YYYY-MM}.md`, una linea por entrada:
`YYYY-MM-DD HH:MM | task_id | {horas}h | notas` (`|` y saltos de linea en notas se sustituyen).

Exit: 0 ok (publicado en origin) · 1 sin repo de empresa, remoto inaccesible o push no confirmado · 2 entrada invalida (no escribe nada).
