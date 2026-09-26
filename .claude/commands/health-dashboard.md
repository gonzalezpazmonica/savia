---
name: health-dashboard
description: Dashboard de salud del proyecto unificado — Savia muestra una vista rápida adaptada al rol
developer_type: all
agent: none
context_cost: medium
model_tier: mid
tier: core
---

# /health-dashboard

> 🦉 Savia te muestra la salud del proyecto desde tu perspectiva.

---

## Cargar perfil de usuario

Grupo: **Reporting** + **Sprint & Daily** — cargar:

- `identity.md` — nombre, rol
- `preferences.md` — language, detail_level
- `projects.md` — qué proyectos monitorizar
- `tone.md` — alert_style, celebrate

Ver `.claude/profiles/context-map.md`.
Leer `@docs/rules/domain/role-workflows.md` para métricas por rol.

---

## Flujo

### Paso 1 — Recopilar datos del proyecto

1. Identificar proyecto activo (o pedir selección si multi-proyecto)
2. Obtener datos según fuentes disponibles:
   - Sprint actual: progreso, burndown, items por estado
   - PRs: abiertos, pendientes de review, antigüedad
   - Pipeline: último build, status, cobertura
   - Deuda técnica: tendencia si hay datos previos
   - Equipo: utilización, bloqueantes, WIP

### Paso 2 — Adaptar vista al rol

Cada rol ve la sección que más le importa PRIMERO:

**PM**: Sprint progress → Team workload → Bloqueantes → Delivery risk
**Tech Lead**: PR status → Code quality → Specs → Deuda técnica
**QA**: Test coverage → Bugs → Compliance → PR testing gaps
**Product Owner**: Feature delivery → KPIs → Backlog health → Stakeholder metrics
**Developer**: My items → PRs → Specs assigned → Build status
**CEO/CTO**: Multi-project summary → Team utilization → Risk → Trends

### Paso 3 — Calcular score de salud

Score compuesto (0-100) basado en dimensiones ponderadas por rol:

| Dimensión | PM | TL | QA | PO | Dev | CEO |
|---|---|---|---|---|---|---|
| Sprint progress | 30% | 15% | 10% | 25% | 20% | 20% |
| Code quality | 10% | 30% | 30% | 5% | 25% | 15% |
| Team health | 25% | 15% | 10% | 15% | 10% | 25% |
| Delivery pace | 20% | 20% | 10% | 35% | 15% | 25% |
| Risk exposure | 15% | 20% | 40% | 20% | 30% | 15% |

Score semáforo:

- 🟢 80-100 — Saludable
- 🟡 60-79 — Atención necesaria
- 🟠 40-59 — Riesgo medio
- 🔴 0-39 — Riesgo alto

### Paso 4 — Mostrar dashboard

Banner: `🦉 Health Dashboard — {proyecto} · {fecha}`

```
📊 Salud: {score}/100 {semáforo}

{sección primaria del rol — datos detallados}

{sección secundaria — resumen}

{alertas activas, ordenadas por severidad}

{sugerencia de acción más relevante}
```

### Paso 5 — Acciones sugeridas

Según las anomalías detectadas, sugerir el comando más relevante:

- Sprint desviado → `/sprint-status` para detalle
- PRs estancados → `/pr-pending` para revisar
- Cobertura baja → sugerir tests
- Equipo sobrecargado → `/team-workload`
- Deuda creciente → `/debt-analyze`

---

## Subcomandos

- `/health-dashboard` — proyecto activo, rol del usuario
- `/health-dashboard {proyecto}` — proyecto específico
- `/health-dashboard all` — resumen multi-proyecto (útil para CEO/CTO)
- `/health-dashboard trend` — tendencia de las últimas 4 semanas

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: health_dashboard
project: "{proyecto}"
score: 78
level: "attention"
dimensions:
  sprint_progress: 85
  code_quality: 72
  team_health: 80
  delivery_pace: 75
  risk_exposure: 68
alerts:
  - severity: high
    message: "2 PRs open > 5 days"
  - severity: medium
    message: "Coverage dropped 3% this sprint"
suggested_action: "/pr-pending"
```

---

## Restricciones

- **NUNCA** inventar datos — si no hay fuente, mostrar "Sin datos"
- **SIEMPRE** indicar de dónde viene cada dato (Azure DevOps, git, specs)
- **NUNCA** ejecutar acciones correctivas sin confirmación
- Si no hay proyecto activo → sugerir `/profile-edit` para configurar proyectos
