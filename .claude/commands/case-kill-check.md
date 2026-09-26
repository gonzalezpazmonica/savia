---
name: case-kill-check
description: Run valuation sentinel across all active cases for kill recommendations
argument-hint: "[--tenant tenant-id]"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Bash, Glob, Grep]
tier: core
---

# /case-kill-check — Kill recommendation scan (SE-016)

**Argumentos:** `$ARGUMENTS` (optional tenant filter)

## Flujo

1. Scan all business-case.md files with status=active
2. For each active case:
   - Check cost variance: >30% threshold
   - Check risk-adjusted NPV: negative?
   - Check timeline variance: >40% threshold
   - Check benefit realization: <50% at review point
3. For cases exceeding thresholds, generate kill recommendation:
   - Reasons (which thresholds exceeded)
   - Sunk cost vs remaining commitment
   - Salvage value estimate (if available)
   - Decision deadline
4. Output summary table + individual recommendations

**This is ALWAYS a recommendation. The investment committee decides.**

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /case-kill-check — Completado
  Active cases: {N} | Alerts: {N} | Kill recommended: {N}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
