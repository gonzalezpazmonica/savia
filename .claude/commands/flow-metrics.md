---
name: flow-metrics
description: Dashboard de métricas de flujo Savia Flow (cycle time, lead time, throughput, CFR)
developer_type: pm
agent: azure-devops-operator
context_cost: moderate
model_tier: mid
max_context: 5000
allowed_modes: [pm, lead, ceo, all]
tier: core
---

# /flow-metrics — Dashboard de Métricas de Flujo

> Indicadores DORA + de flujo específicos de Savia Flow: cycle time, lead time, throughput, CFR.

## Uso
`/flow-metrics [--track {exploration|production}] [--person {nombre}] [--trend {weeks}] [--compare {sprint1} {sprint2}]`

## Subcomandos
- `--track exploration|production`: Métricas de una pista (default: ambas)
- `--person {nombre}`: Métricas individuales de un builder/spec-writer
- `--trend {weeks}`: Gráfico de tendencia (últimas N semanas, default: 4)
- `--compare {sprint1} {sprint2}`: Comparativa de dos sprints

## Métricas principales

### Flow Metrics
- **Cycle Time** (mediana + p95): tiempo desde Ready hasta Deployed en Production
- **Lead Time** (mediana + p95): tiempo desde Spec-Ready en Exploration hasta Deployed
- **Throughput**: items/semana completados (Deployed)
- **CFR** (Cumulative Flow Ratio): items completados vs. en progreso

### DORA Metrics
- **Deployment Frequency**: deploys/semana
- **Lead Time for Changes**: tiempo desde commit a producción
- **MTTR** (Mean Time To Recovery): tiempo promedio de rollback
- **Change Failure Rate**: % deploys que resultan en rollback

### AI-Specific
- **Spec-to-Built Time**: promedio Spec-Ready hasta Built (por builder)
- **Handoff Latency**: tiempo promedio esperando siguiente rol (spec-writer → builder)
- **Rework Rate**: % items re-abiertos tras Deployed/Validating

## Cálculos

Usar timestamps custom fields:
- `Cycle Time Start`: cuando entra a Production (Ready)
- `Cycle Time End`: cuando se marca Deployed
- Cycle Time = (Cycle Time End - Cycle Time Start) en días

Fechas de estado via audit trail de work items.

## Targets y calibración

```
┌──────────────────┬─────────┬─────────┬─────────┐
│ Métrica          │ Verde   │ Amarillo│ Rojo    │
├──────────────────┼─────────┼─────────┼─────────┤
│ Cycle Time p50   │ ≤5 días │ 5-7     │ >7      │
│ Cycle Time p95   │ ≤10     │ 10-14   │ >14     │
│ Lead Time p50    │ ≤15     │ 15-20   │ >20     │
│ Throughput       │ ≥3 it/w │ 2-3     │ <2      │
│ CFR              │ ≥70%    │ 50-70%  │ <50%    │
│ Rework Rate      │ <5%     │ 5-10%   │ >10%    │
└──────────────────┴─────────┴─────────┴─────────┘
```

## Output

Formato dashboard con indicadores coloreados (verde/amarillo/rojo):

```
FLOW METRICS — {proyecto} — última semana

━━━ Cycle Time (Production) ━━━━━━━━━━━━━━━━━━
P50 ..................... 4.2 días  ✅ BIEN
P95 ..................... 8.5 días  ✅ BIEN

━━━ Lead Time (Exploration → Deployed) ━━━
P50 ..................... 12 días   ✅ BIEN
P95 ..................... 18 días   ✅ BIEN

━━━ Throughput ━━━━━━━━━━━━━━━━━━━━━━━━━━
Deployed/semana ......... 4.2       ✅ BIEN (target 3+)

━━━ Cumulative Flow Ratio ━━━━━━━━━━━━━━
Completados / En Progreso 0.78     ✅ BIEN (target >0.7)

━━━ Rework Rate ━━━━━━━━━━━━━━━━━━━━━━━
Re-abiertos ............ 3.2%       ✅ BIEN (target <5%)

━━━ Interpretación ━━━━━━━━━━━━━━━━━━━━━
Flujo estable. Cycle time bajando. Alertar si lead time sube.
```

Si >40 líneas → guardar en `projects/{proyecto}/.flow/metrics-{date}.md`

## Interpretación automática

Sugerir acciones basadas en desviaciones:
- Cycle time subiendo → revisar WIP limits
- Rework >10% → aumentar validación en Gate-Review
- Throughput bajando → capacidad reducida o bloqueos
- CFR <50% → demasiado work-in-progress, parar intake
