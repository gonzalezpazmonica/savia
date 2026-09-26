---
name: case-init
description: Scaffold a business case from pursuit and SOW data
argument-hint: "OPP-YYYY-NNN [--tenant tenant-id]"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /case-init — Create business case (SE-016)

**Argumentos:** `$ARGUMENTS` — OPP-ID required

## Flujo

1. Locate pursuit from OPP-ID (SE-015 pipeline)
2. Read pursuit.md for investment context (estimated_value_eur, practice)
3. Check for SE-017 SOW (definition/SOW.md) for contract value
4. Generate case ID: `BC-{YYYY}-{NNN}`
5. Create `valuation/` directory with:
   - `business-case.md` — frontmatter from pursuit + SOW data
   - `assumptions.yaml` — seeded from pursuit pricing
   - `risk-register.yaml` — seeded from qualification low scores
   - `benefit-schedule.yaml` — empty template with review dates
6. Set status=draft, benefit_realization_status=not-started

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /case-init — Completado
  Case: {BC-ID} for {project}
  Path: valuation/business-case.md
  Next: /case-recompute {BC-ID}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
