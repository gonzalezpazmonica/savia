---
name: pursuit-handoff
description: Generate sales-to-delivery handoff package for a won pursuit
argument-hint: "OPP-YYYY-NNN"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /pursuit-handoff — Sales-to-delivery handoff (SE-015)

**Argumentos:** `$ARGUMENTS` — OPP-ID required

## Flujo

1. Locate pursuit directory from OPP-ID
2. Verify pursuit.md stage=won (gate: handoff only for won pursuits)
3. Read all pursuit artifacts:
   - pursuit.md (client context, team, contacts)
   - qualification.yaml (risk dimensions)
   - bid-decision.md (conditions, risk appetite)
   - proposal/ (commitments made)
4. Check for SE-017 SOW: look for definition/SOW.md in same tenant
5. Generate handoff.md with sections:
   - Client Context, Key Relationships, Commitments,
     Pricing Assumptions, Known Risks, Compliance, Lessons
6. Cross-reference SE-017 SOW if available

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-handoff — Completado
  {OPP-ID}: Handoff package generated
  Path: {pursuit-dir}/handoff.md
  Next: delivery team reviews handoff
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
