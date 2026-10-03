---
name: billing-model
description: "Cost Management & Billing — Rate tables, timesheets, budgets, invoices, EAC calculations"
auto_load: false
paths: [".opencode/commands/cost-center*", ".opencode/skills/cost-management/*"]
context_tier: L2
token_budget: 858
---

# Regla: Modelo de Facturación

> Era 38: v2.12.1 — Cost Management & Billing
> Complementa: @.opencode/skills/savia-flow-practice/references/flow-tasks-config.md

**Principio**: Los costes son datos de primera clase. Timesheets, presupuestos y ledger (`.flow-data/`) se versionan en Git; rates son git-ignorados; invoices e informes se generan en `output/` (git-ignorado, no se versionan).

## Rate Table Schema

`.flow-data/rates.json` (git-ignored, local per PM; importes en moneda/hora):

```json
{
  "rates_by_role": {
    "developer": 85,
    "senior_developer": 120,
    "architect": 150,
    "qa_engineer": 70,
    "product_owner": 100,
    "scrum_master": 95
  },
  "currency": "EUR",
  "last_updated": "2026-03-01"
}
```

Configurable por proyecto en `projects/{proj}/.rates.local.json` (overrides globales).
Ambos ficheros están en `.gitignore` (`.flow-data/rates.json` y `**/.rates.local.json`), también dentro de los proyectos de ejemplo publicados.

## Timesheet Format (JSONL)

```
.flow-data/timesheets/{user}/{YYYY-MM}.jsonl
```

Schema per entry:
```json
{"date":"2026-03-03","user":"@monica","task_id":"TASK-2026-0042","project":"sala-reservas","hours":7.5,"notes":"API auth refactor","billable":true}
```

Fields:
- `date`: ISO 8601
- `user`: @handle (corresponds to `.claude/profiles/{handle}/`)
- `task_id`: reference to Savia Flow task or Azure DevOps ID
- `project`: project slug
- `hours`: decimal (0.5 precision minimum)
- `notes`: optional description
- `billable`: boolean (false for internal, vacation, training)

## Budget Schema

```
.flow-data/budgets/{project}.json
```

```json
{
  "project": "sala-reservas",
  "total_budget": 50000,
  "currency": "EUR",
  "start_date": "2026-03-01",
  "end_date": "2026-06-30",
  "alerts_at": [50, 75, 90],
  "by_role": {
    "developer": 10000,
    "qa_engineer": 5000
  }
}
```

Alerts triggered when actual_burn / total_budget reaches thresholds (e.g., 50%, 75%, 90%).

## Invoice Schema

```
output/invoices/{client}-{YYYY-MM}.json
```

```json
{
  "client": "acme-corp",
  "period": "2026-03",
  "currency": "EUR",
  "entries": [
    {"project":"sala-reservas","hours":160,"rate":85,"subtotal":13600,"role":"developer"},
    {"project":"sala-reservas","hours":40,"rate":120,"subtotal":4800,"role":"senior_developer"}
  ],
  "total": 18400,
  "generated_at": "2026-03-31T17:00:00Z",
  "status": "draft"
}
```

No PII in invoices. Hours aggregated by role/project. Individual timesheets used for backup only.

## Cost KPIs

| KPI | Formula | Insight |
|-----|---------|---------|
| **cost-per-story-point** | Σ(hours × rate) / total_SP_completed | Efficiency metric |
| **utilization-rate** | billable_hours / available_hours | Capacity usage |
| **budget-burn-rate** | actual_burn / elapsed_time | Pace of spending |
| **EAC (Estimate at Completion)** | BAC / CPI | Projected final cost |

Where:
- `BAC` = Budget at Completion (original budget)
- `CPI` = Cost Performance Index = EV / AC
- `EV` = Earned Value = (% complete) × BAC
- `AC` = Actual Cost = Σ timesheet hours × rates
- `SPI` = Schedule Performance Index = EV / PV

Formula for EAC (EVM): `EAC = BAC / CPI` (if CPI < 1.0, project over budget; CPI > 1.0 means under budget). Requires `% complete`; `/cost-center forecast` uses the linear burn-rate EAC of cost-tracking.md instead.

## Integration

| Consumer | Usage |
|----------|-------|
| `/cost-center report` | Aggregate timesheets → generate cost report |
| `/cost-center budget` | Track burn vs. budget, trigger alerts |
| `/cost-center invoice` | Generate client-ready invoices |
| `/cost-center forecast` | Use velocity to project EAC |
