---
name: calendar-rebalance
description: "Rebalancear focus blocks tras cambio de prioridades o calendario"
argument-hint: "[--reason 'nueva reunion'] [--project nombre]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /calendar-rebalance — Rebalancear Agenda

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Cuando usar

- Nueva reunion anadida que rompe un focus block
- Cambio de prioridades (nueva urgencia, deadline adelantado)
- Cancelacion de reunion que libera hueco aprovechable
- Tras `/sprint-plan` con nuevas asignaciones

## Flujo

1. Detectar cambios vs plan anterior
2. Reclasificar items (Eisenhower actualizado)
3. Reasignar focus blocks a huecos disponibles
4. Si no cabe todo: alertar con items que se quedan fuera
5. Actualizar calendario (si sync activo) o mostrar plan revisado

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 /calendar-rebalance — Reajustar Agenda
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
