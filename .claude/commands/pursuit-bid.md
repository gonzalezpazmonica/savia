---
name: pursuit-bid
description: Record bid/no-bid decision for a qualified pursuit
argument-hint: "OPP-YYYY-NNN go|no-go [--rationale 'reason']"
context_cost: low
model_tier: fast
allowed-tools: [Read, Write, Bash]
tier: core
---

# /pursuit-bid — Record bid decision (SE-015)

**Argumentos:** `$ARGUMENTS` — OPP-ID + decision (go|no-go)

## Flujo

1. Parse OPP-ID and decision from arguments
2. Locate pursuit directory (search tenants/*/pipeline/pursuits/ and projects/*/pipeline/pursuits/)
3. Verify qualification.yaml exists (gate: cannot bid without qualification)
4. Read qualification scores for context
5. If rationale not provided via --rationale, ask the user for rationale
6. Write bid-decision.md with YAML frontmatter:
   - decision, decided_by (active user), decided_on (today)
   - rationale, risk_appetite, conditions
7. Update pursuit.md stage to "pursuit" if decision=go, "lost" if decision=no-go

## Important

**The human ALWAYS makes this decision.** This command records the decision, it does not make it.
Never auto-populate the decision. The user must explicitly say go or no-go.

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-bid — Completado
  {OPP-ID}: Decision = {go|no-go}
  Recorded by: {user}
  Next: /pursuit-draft {OPP-ID} (if go)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
