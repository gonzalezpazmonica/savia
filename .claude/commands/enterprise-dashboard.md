---
name: enterprise-dashboard
description: "Enterprise analytics — portfolio metrics, team health, risk matrix, forecasting"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[portfolio|team-health|risk-matrix|forecast] [--project proyecto] [--team equipo] [--quarters 2]"
model_tier: mid
context_cost: medium
tier: core
---

# /enterprise-dashboard — Analytics Empresarial

> Skill: @.opencode/skills/enterprise-analytics/SKILL.md
> Config: @docs/rules/domain/enterprise-metrics.md

Visualización de métricas SPACE multi-proyecto, salud por equipo, matriz de riesgos, forecasting.

## Subcomandos

### `/enterprise-dashboard portfolio [--risk-only]`

Vista agregada de todos los proyectos:
- Velocity trend por proyecto
- Portfolio health score
- Top risks
- Output: tabla + gráficos ASCII

### `/enterprise-dashboard team-health --team equipo`

Salud del equipo en 5 dimensiones SPACE:
- Radar chart (ASCII)
- Scores individuales
- Recomendaciones
- Output: análisis + acciones

### `/enterprise-dashboard risk-matrix`

Mapa de riesgos cross-proyecto:
- Dependencies críticas
- Probabilidad × impacto
- Mitigación sugerida
- Output: matriz + alertas

### `/enterprise-dashboard forecast [--quarters 2]`

Predicción de velocity próximos quarters:
- Ranges (optimistic/likely/pessimistic)
- Confidence intervals
- Output: gráfico + tabla

## Datos almacenados

```
output/analytics/
├── dashboard-YYYYMMDD.md
├── forecasts/
│   └── forecast-YYYYMM.md
└── risk-matrix-YYYYMM.md
```

## Integración

| Comando | Relación |
|---|---|
| `/ceo-report` | Incluye portfolio health |
| `/team-evaluate` | Detalla team health |
