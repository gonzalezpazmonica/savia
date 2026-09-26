---
name: agent-cost
description: Coste estimado de uso de agentes por sprint/proyecto
developer_type: agent-single
agent: azure-devops-operator
context_cost: low
model_tier: fast
tier: core
---

# Comando: agent-cost

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` -> obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **SDD & Agentes** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
3. Adaptar output segun `identity.rol` (tech lead vs PM)
4. Si no hay perfil -> continuar con comportamiento por defecto

## 2. Descripcion

Estima el coste de uso de agentes basandose en tokens consumidos. Agrupa por agente, comando y opcionalmente por sprint. Incluye columnas de budget vs actual y alertas de presupuesto excedido.

## 3. Datos

- Trazas: `projects/{proyecto}/traces/agent-traces.jsonl`
- Alertas: `projects/{proyecto}/traces/budget-alerts.jsonl`

## 4. Modelo de costes

Configurable en `CLAUDE.local.md`:
- **Opus 4.6**: $15/M tokens entrada, $75/M tokens salida
- **Sonnet 4.6**: $3/M entrada, $15/M salida
- **Haiku 4.5**: $0.80/M entrada, $4/M salida

## Comportamiento

**Agrupacion:** por agente, por comando
**Opcional `--sprint`:** grupos por sprint si se especifica

**Calculo:** coste_total = (tokens_in * precio_entrada + tokens_out * precio_salida) / 1_000_000

## Output

### Tabla principal con budget columns

```
| Agent | Invocations | Tokens In | Tokens Out | Budget | Actual | Delta | Status | Cost |
```

Where:
- `Budget` = `token_budget` from trace (per agent frontmatter)
- `Actual` = average `tokens_in + tokens_out` across invocations
- `Delta` = `Actual - Budget` (negative = under, positive = over)
- `Status` = "OK" if Delta <= 0, "OVER" if Delta > 0

### Budget Violations section

Read from `budget-alerts.jsonl` (last 30 days):

```
Budget Violations (last 30 days):
| Agent | Count | Avg Overage | Max Overage | Recommendation |
```

Recommendations:
- Overage > 50%: "Reduce input context or split task"
- Overage 20-50%: "Review context selection strategy"
- Overage < 20%: "Minor -- consider increasing budget"

If no violations file or empty: "No budget violations recorded."

### Cost summary

- Subtotal por agente
- Coste total del periodo
- Tendencia: costes de los ultimos 3 sprints (si existe historico)

### Optimization recommendations

- Identify most expensive agents
- Flag agents consistently over budget
- Suggest model downgrades for simple tasks

## Ejemplos

```
/agent-cost
/agent-cost --sprint "Sprint 2026-05"
```

## Requisitos

- Trazas disponibles en `projects/{proyecto}/traces/`
- Configuracion de costes actualizada
