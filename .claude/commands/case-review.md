---
name: case-review
description: Generate benefit realization review at 90/180/365 days
argument-hint: "BC-YYYY-NNN 90d|180d|365d"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /case-review — Benefit realization review (SE-016)

**Argumentos:** `$ARGUMENTS` — case ID + review period

## Flujo

1. Locate business-case.md by case_id
2. Read benefit-schedule.yaml for planned benefits at review point
3. Read actuals/benefit-actuals.yaml for measured benefits
4. Compare planned vs actual for each benefit metric
5. Calculate overall realization percentage
6. Generate reviews/review-{period}.md with YAML frontmatter
7. Generate recommendation based on realization %:
   - >=90%: On track
   - 70-89%: Below target, specific actions needed
   - <70%: Significant gap, escalation recommended
8. Update benefit_realization_status in business-case.md

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /case-review — Completado
  {BC-ID}: {period} review — {N}% realized
  Path: valuation/reviews/review-{period}.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
