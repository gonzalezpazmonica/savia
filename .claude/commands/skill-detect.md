---
name: skill-detect
description: Detect repeated patterns and propose new skills automatically
argument-hint: "[scan|propose|refine|status]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /skill-detect — Deteccion y propuesta de skills (SE-030)

**Argumentos:** `$ARGUMENTS` (default: `status`)

## Modos

| Modo | Que hace |
|------|----------|
| `status` | Muestra propuestas pendientes, skills activos, invocaciones |
| `scan` | Analiza logs de invocaciones y detecta patrones repetidos |
| `propose NAME [desc] [domain]` | Genera scaffold SKILL.md + DOMAIN.md |
| `refine` | Sugiere mejoras a skills con alta tasa de fallo |

## Ejecucion

```bash
bash scripts/skill-detect.sh ${ARGUMENTS:-status}
```

Mostrar output completo. Si el modo es `propose`, informar que el PM
debe revisar y mover a `.opencode/skills/` para activar.
