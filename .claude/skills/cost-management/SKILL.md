---
layer: peripheral
name: cost-management
description: "Usar cuando se gestionan timesheets, presupuestos, facturas o forecasting de costes."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: reporting
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.memory: project
  savia.priority: medium
  savia.summary: "Gestion de costes: timesheets, presupuestos, forecasting e invoicing. Registra horas por tarea/proyecto, calcula desviaciones, genera facturas. Output: informes Excel/Word."
  savia.tags: "cost, budget, forecasting, invoicing"
---

# Skill: Cost Management

> Prerequisito: @docs/rules/domain/billing-model.md, @docs/rules/domain/cost-tracking.md

Orquesta timesheet logging, budget tracking, forecasting y generación de invoices.

## Flujo 1 — Log de horas (`log`)

1. Validar entrada:
   - `date`, `user`, `task_id`, `project`, `hours` (todos requeridos)
   - `hours` es decimal ≥ 0.5
   - `user` tiene perfil
   - `project` existe en `projects/{proj}/CLAUDE.md`
2. Leer rates de `.flow-data/rates.json` (o `.flow-data/{project}/.rates.local.json`)
3. Calcular cost = hours × rate_for_role
4. Crear entrada JSONL en `.flow-data/timesheets/{user}/{YYYY-MM}.jsonl`
5. Actualizar ledger: añadir entrada type "time" a `.flow-data/ledger/{project}.jsonl`
6. Output: confirmación + acumulado del mes

Error handling:
- Horas duplicadas (misma user/task/date): advertir, preguntar si actualizar
- Rate no encontrado: sugerir `/cost-center budget --create-rates`
- User sin perfil: sugerir `/profile-setup {user}`

## Flujo 2 — Informe de costes (`report`)

Parámetros: `--period {YYYY-MM}`, `--team {nombre}`, `--project {slug}`, `--client {slug}`

1. Recopilar timesheet entries según filtros
2. Agregar por:
   - Proyecto
   - Equipo (si `--team`)
   - Cliente (si `--client`)
   - Rol
3. Calcular KPIs: cost-per-SP, utilization-rate, burn-rate
4. Generar tabla resumen:
   ```
   Project     │ Hours  │ Cost (€) │ Team      │ Status
   ────────────┼────────┼──────────┼───────────┼─────────
   sala-reservas │ 160   │ 13,600   │ Backend   │ On-budget
   api-v3      │ 120    │ 14,400   │ Backend   │ 5% over
   ```
5. Guardar en `output/cost-report-{periodo}.md`

## Flujo 3 — Gestión de presupuestos (`budget`)

Subcomandos:
- `--create {project}`: crear presupuesto inicial (solicitar total, moneda, fechas)
- `--update {project}`: modificar presupuesto (total, alerts)
- `--burn {project}`: mostrar burn actual vs. presupuesto
- `--status`: comparar todos los proyectos

Output: tabla con budget/actual/remaining/% spent + alertas

```
Project         │ Total   │ Spent  │ Remaining │ Status
────────────────┼─────────┼────────┼───────────┼──────────
sala-reservas   │ €50,000 │ €42,500 │ €7,500    │ 85% ⚠️
api-v3          │ €60,000 │ €48,000 │ €12,000   │ 80% ⚠️
```

## Flujo 4 — Pronóstico (`forecast`)

1. Leer ledger del proyecto
2. Calcular:
   - `elapsed_days` = hoy - fecha_inicio_presupuesto
   - `burn_rate` = actual_burn / elapsed_days
   - `remaining_days` = fecha_fin_presupuesto - hoy
   - `EAC` = burn_rate × (elapsed_days + remaining_days)
3. Comparar `EAC` vs. `BAC`:
   - Si EAC > BAC: mostrar riesgo y opciones (reducir scope, extender)
   - Si EAC < BAC: proyecto bajo presupuesto

Output: gráfico ASCII de proyección + recomendaciones

```
Forecast: EAC = €55,200 (BAC = €50,000)
Risk: 10.4% over budget
Options:
  1. Reduce scope (descope €5,200 worth of features)
  2. Extend timeline (add 2 weeks)
  3. Increase budget (request €5,200 approval)
```

## Flujo 5 — Generación de invoices (`invoice`)

Parámetros: `--client {slug}`, `--period {YYYY-MM}`, `--status draft|final`

1. Recopilar timesheet entries para cliente + período
2. Agrupar por (project, role)
3. Generar invoice JSON con schema de @billing-model.md
4. Guardar en `output/invoices/{client}-{YYYY-MM}.json`
5. Status = "draft" (editable), cambiar a "final" cuando aprobado
6. Output: resumen + ruta del PDF

## Errores

| Problema | Solución |
|----------|----------|
| Horas duplicadas | Advertir, preguntar si mezclar o descartar |
| Rate no definido | Crear rate primero con `/cost-center budget --create-rates` |
| Proyecto sin presupuesto | Crear presupuesto con `/cost-center budget --create {project}` |
| Período sin datos | Mostrar período más reciente disponible |

## Seguridad

- **Rates are git-ignored**: `.flow-data/rates.json` nunca en commit
- **No PII in invoices**: solo @handles, nunca nombres reales
- **Ledger is immutable**: no editar historial, solo adjustments adelante
- **Auditable**: cada entrada tiene timestamp y user para trazabilidad
