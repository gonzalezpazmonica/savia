---
name: savia-board
description: >
  Kanban board ASCII para Savia Flow. Muestra PBIs agrupados por estado.
argument-hint: "[--project <name>]"
allowed-tools: [Read, Bash, Glob]
model_tier: fast
context_cost: low
tier: core
---

# Savia Board

**Argumentos:** $ARGUMENTS

> Uso: `/savia-board` | `/savia-board --project alpha`

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md

## Pasos de ejecucion

1. Mostrar banner: `--- Savia Board ---`
2. Verificar company repo configurado
3. Si no hay proyecto en args, preguntar nombre del proyecto
4. Ejecutar: `bash scripts/savia-flow.sh board <project>`
5. Mostrar board ASCII con columnas: New | Ready | In Progress | Review | Done
6. Si hay WIP > 5 en In Progress, avisar
7. Mostrar banner de finalizacion

## Voz Savia (humano)

"Aqui tienes el tablero de {project}."

## Modo agente

```yaml
status: OK
project: "name"
counts: {new: N, ready: N, in_progress: N, review: N, done: N}
```

## Restricciones

- Solo lectura, no modifica estado
- Si el proyecto no existe, error claro con proyectos disponibles

/compact — Ejecuta para liberar contexto antes del siguiente comando
