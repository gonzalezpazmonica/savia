---
name: flow-task-create
description: Create a new task in Savia Flow with frontmatter metadata
argument-hint: "<type> <title> <@assigned> <sprint> [priority]"
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# Create Task

**Arguments:** $ARGUMENTS

> Uso: `/flow-task-create task "Build API" @developer SPR-2026-01 high`

## Parámetros

- `<type>` — task|bug|spike|subtask
- `<title>` — Task title
- `<@assigned>` — Developer handle
- `<sprint>` — Sprint ID (SPR-YYYY-NN)
- `[priority]` — critical|high|medium|low (default: medium)

## Ejecución

1. Banner: `🆕 Creating Task`
2. Execute: `bash scripts/savia-flow-tasks.sh create <type> <title> <@assigned> <sprint> [priority]`
3. Mostrar resultado + ID de task
4. Banner de finalización

## Restricciones

- Title ≤ 100 caracteres
- Sprint debe existir
- Handle debe ser válido
