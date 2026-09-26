---
name: pursuit-close
description: Close a pursuit as won or lost and trigger post-mortem analysis
argument-hint: "OPP-YYYY-NNN won|lost [--competitor 'name']"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /pursuit-close — Close pursuit (SE-015)

**Argumentos:** `$ARGUMENTS` — OPP-ID + outcome (won|lost)

## Flujo

1. Parse OPP-ID and outcome from arguments
2. Locate pursuit directory
3. Update pursuit.md stage to won or lost
4. If lost: record competitor who won (if --competitor provided)
5. Generate postmortem.md with structured analysis:
   - Timeline of pursuit stages with dates
   - Qualification scores summary (BANT + MEDDIC)
   - What worked well
   - What could improve
   - Lessons for future pursuits
6. If won: suggest `/pursuit-handoff {OPP-ID}` as next step

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-close — Completado
  {OPP-ID}: {won|lost}
  Postmortem: {pursuit-dir}/postmortem.md
  Next: /pursuit-handoff {OPP-ID} (if won)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
