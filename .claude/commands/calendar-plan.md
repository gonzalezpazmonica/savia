---
name: calendar-plan
description: "Planificar semana con focus blocks automaticos y priorizacion Eisenhower"
argument-hint: "[--week current|next] [--project nombre]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: heavy
context_cost: high
tier: core
---

# /calendar-plan — Planificar Semana

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Flujo

1. Leer calendario de la semana (cache o sync)
2. Leer fuentes de trabajo: backlog PM, deadlines, digestiones pendientes, follow-ups
3. Clasificar cada item (Eisenhower: DO/SCHEDULE/DELEGATE/ELIMINATE)
4. Identificar huecos libres en calendario
5. Asignar focus blocks a items SCHEDULE por deadline proximity
6. Crear eventos en Outlook (si GRAPH_CALENDAR_SYNC=true) o mostrar plan
7. Alertar: dias sin capacidad, reuniones sin agenda, deadlines en riesgo

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 /calendar-plan — Planificar Semana
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
