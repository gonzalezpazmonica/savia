---
name: savia-sprint
description: >
  Ciclo de vida del sprint en Savia Flow: iniciar, cerrar, ver estado.
  Sprints almacenados como carpetas en el company repo.
argument-hint: "[start|close|status] [--project <name>]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Sprint

**Argumentos:** $ARGUMENTS

> Uso: `/savia-sprint start` | `/savia-sprint close` | `/savia-sprint status`

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md
2. `.opencode/skills/company-messaging/references/flow-schemas.md`

## Pasos de ejecucion

1. Mostrar banner: `--- Savia Sprint ---`
2. Verificar company repo configurado
3. Si no hay proyecto en args, preguntar nombre del proyecto
4. Detectar accion:
   - **start**: Preguntar nombre del sprint (ej: sprint-2026-05),
     goal, fecha inicio, fecha fin.
     Ejecutar: `bash scripts/savia-flow.sh sprint-start <project> <name> <goal> <start> <end>`
   - **close**: Verificar sprint activo.
     Ejecutar: `bash scripts/savia-flow.sh sprint-close <project>`
     Mostrar velocidad calculada.
   - **status**: Leer `sprints/current.md` y el sprint.md activo.
     Mostrar goal, fechas, PBIs asignados al sprint.
5. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
6. Mostrar banner de finalizacion

## Voz Savia (humano)

- Start: "Sprint arrancado. Ya puedes asignar PBIs."
- Close: "Sprint cerrado con velocidad de X SP."
- Status: "Sprint activo: {name} ({start} - {end})"

## Modo agente

```yaml
status: OK
action: "start|close|status"
sprint: "sprint-YYYY-NN"
velocity: N
```

## Restricciones

- NUNCA cerrar sprint sin confirmacion
- Si no hay sprint activo y se pide close, error claro

/compact — Ejecuta para liberar contexto antes del siguiente comando
