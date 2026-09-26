---
name: calendar-deadlines
description: "Deadlines proximos con estado de preparacion — nada se queda atras"
argument-hint: "[--days 14] [--project nombre]"
allowed-tools: [Read, Glob, Grep, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# /calendar-deadlines — Guardian de Deadlines

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Fuentes de deadlines

- Ceremonias Scrum (sprint boundaries, reviews, retros)
- Steercos y reuniones con stakeholders
- Informes ejecutivos y reportes recurrentes
- Digestiones pendientes (reuniones >48h sin procesar)
- Follow-ups comprometidos en 1:1s
- Tareas PM sin mover >5 dias
- Releases y deployment windows

## Flujo

1. Recopilar deadlines de todas las fuentes
2. Calcular proximity score (exponencial: mas cerca = mas urgente)
3. Evaluar estado de preparacion (% completado, dependencias)
4. Clasificar: en riesgo / en tiempo / completado
5. Mostrar timeline con alertas

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ /calendar-deadlines — Nada se queda atras
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
