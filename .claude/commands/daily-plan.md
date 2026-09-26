---
name: daily-plan
description: Generate or show today's agent activation plan with token budgets
argument-hint: "[generate|show|status]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /daily-plan — Plan de activacion de agentes (SE-034)

**Argumentos:** `$ARGUMENTS` (default: `status`)

## Modos

| Modo | Que hace |
|------|----------|
| `status` | Resumen: plan activo, items en cola, budget disponible |
| `generate` | Genera plan del dia desde backlog + specs aprobadas |
| `show` | Muestra plan activo sin regenerar |

## Ejecucion

```bash
bash scripts/daily-activation-plan.sh ${ARGUMENTS:-status}
```

Si el modo es `generate`, mostrar el plan completo.
Si el modo es `show` y no hay plan, informar y sugerir `generate`.

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /daily-plan — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
