---
name: calendar-today
description: "Vista del dia con alertas, reuniones, focus blocks y recomendaciones"
argument-hint: "[--project nombre]"
allowed-tools: [Read, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /calendar-today — Vista del Dia

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Flujo

1. Leer cache de calendario (`data/calendar-cache.json`)
2. Filtrar eventos de hoy
3. Cruzar con: deadlines del proyecto, tareas PM pendientes, digestiones atrasadas
4. Clasificar huecos libres (Eisenhower: DO/SCHEDULE/DELEGATE/ELIMINATE)
5. Mostrar: timeline del dia, alertas, % capacidad productiva, recomendacion de focus

## Integracion con daily-routine

`/calendar-today` se integra como primer paso de `/daily-routine` para el rol PM.
Si no hay cache: sugerir `/calendar-sync` primero.

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌅 /calendar-today — Tu dia
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
