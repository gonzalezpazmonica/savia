---
name: case-recompute
description: Recompute NPV, IRR, and risk-adjusted NPV for a business case
argument-hint: "BC-YYYY-NNN"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /case-recompute — Recompute valuation (SE-016)

**Argumentos:** `$ARGUMENTS` — case ID required

## Flujo

1. Locate business-case.md by case_id
2. Read assumptions.yaml, risk-register.yaml, benefit-schedule.yaml
3. Read actuals/ if available (cost-actuals.yaml, benefit-actuals.yaml)
4. Compute:
   - NPV using assumptions cash flows and discount rate
   - IRR via Newton-Raphson approximation
   - Risk-adjusted NPV = NPV * (1 - weighted_risk_factor)
   - Variance: compare actuals vs planned on cost, timeline, benefit
5. Update frontmatter: estimated_npv_eur, estimated_irr_pct, risk_adjusted_npv_eur
6. Update variance_alerts with current status (green/amber/red)
7. Update last_recomputed timestamp

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /case-recompute — Completado
  {BC-ID}: NPV {N}K | IRR {N}% | Risk-NPV {N}K
  Variance: cost {status} | timeline {status} | benefit {status}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
