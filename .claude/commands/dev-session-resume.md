---
name: dev-session-resume
description: "Reanudar una dev-session interrumpida desde el ultimo checkpoint"
argument-hint: "{session-id}"
allowed-tools: [Read, Glob, Grep, Bash, Write, Edit, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /dev-session-resume — Reanudar Dev-Session

Regla: `@docs/rules/domain/dev-session-locks.md`

## Flujo

1. Buscar locks en `.claude/sessions/`
2. Si `$ARGUMENTS`: buscar lock especifico por session-id
3. Si sin argumentos: listar sesiones con lock y preguntar cual reanudar
4. Verificar si lock es stale (PID muerto + >30 min sin update)
5. Si stale: limpiar y crear nuevo lock
6. Leer `output/dev-sessions/{id}/state.json`
7. Sintetizar briefing: slices completados, slice actual, pendientes
8. Cargar contexto del slice actual
9. Continuar implementacion desde donde se quedo

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 /dev-session resume — Recuperar sesion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
