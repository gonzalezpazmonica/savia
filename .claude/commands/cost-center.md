---
name: cost-center
description: "Cost management and billing — timesheets, budgets, forecasting, invoicing"
allowed-tools: [Read, Write, Glob, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# Cost Center — Cost Management & Billing

**Uso**: `/cost-center {subcommand} [opciones]`

Gestiona todos los aspectos financieros de los proyectos: timesheets, presupuestos, facturación y pronóstico de costes.

Era 38: v2.12.1

## Subcommands

### 1. Log — Registrar horas

```bash
/cost-center log --user @monica --date 2026-03-03 --task TASK-2026-0042 --project sala-reservas --hours 7.5 --billable
```

- Validar: user, project, hours ≥ 0.5
- Leer rates de `.flow-data/rates.json`
- Calcular cost = hours × rate_for_role
- Crear entrada JSONL: `.flow-data/timesheets/{user}/{YYYY-MM}.jsonl`
- Actualizar ledger: `.flow-data/ledger/{project}.jsonl`
- Output: ✅ + horas acumuladas mes

### 2. Report — Informe de costes

```bash
/cost-center report --period 2026-03 --team backend --project sala-reservas
```

- Filtrar timesheet entries
- Agregar por proyecto/equipo/rol
- Calcular KPIs: cost-per-SP, utilization-rate
- Generar tabla resumen
- Guardar: `output/cost-report-{periodo}.md`

### 3. Budget — Gestión de presupuestos

```bash
/cost-center budget --create sala-reservas --total 50000 --currency EUR --start 2026-03-01 --end 2026-06-30
/cost-center budget --burn sala-reservas
```

Subcomandos internos:
- `--create {project}`: crear presupuesto
- `--update {project}`: modificar
- `--burn {project}`: mostrar consumo vs. presupuesto
- `--status`: tabla all projects

### 4. Forecast — Pronóstico de costes

```bash
/cost-center forecast --project sala-reservas
```

- Calcular burn_rate = actual_burn / elapsed_time
- Proyectar EAC = burn_rate × total_duration
- Comparar EAC vs. BAC
- Si EAC > BAC: mostrar riesgo + opciones
- Output: gráfico ASCII + recomendaciones

### 5. Invoice — Generar facturas

```bash
/cost-center invoice --client acme-corp --period 2026-03 --status draft
```

- Recopilar timesheets para cliente+período
- Agrupar por (project, role)
- Generar JSON schema
- Guardar: `output/invoices/{client}-{YYYY-MM}.json`
- Output: resumen + ruta

## Prerequisitos

- @docs/rules/domain/billing-model.md
- @docs/rules/domain/cost-tracking.md
- @.opencode/skills/cost-management/SKILL.md

## Integration

| Rol | Acceso |
|-----|--------|
| PM | All commands |
| Finance | report, invoice (read-only) |
| Team Lead | log (own team) |
| CEO | report, forecast (aggregated) |
