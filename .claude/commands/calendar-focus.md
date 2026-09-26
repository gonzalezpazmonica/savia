---
name: calendar-focus
description: "Crear bloque de focus para una tarea especifica — Deep Work protegido"
argument-hint: "{tarea} [--duration 90m] [--when tomorrow-morning]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: low
tier: core
---

# /calendar-focus — Bloque de Deep Work

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Flujo

1. Identificar tarea (argumento o `my-focus` si no especificado)
2. Buscar proximo hueco libre >= 45 min en calendario
3. Crear evento tentative "[Savia] Focus: {tarea}" con color azul
4. Si sync activo: crear en Outlook. Si no: mostrar sugerencia
5. Respetar reglas: no antes de daily, no despues de 17h, 15 min buffer

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 /calendar-focus — Proteger tiempo
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
