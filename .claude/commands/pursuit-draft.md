---
name: pursuit-draft
description: Generate proposal sections from library assets for a pursuit
argument-hint: "OPP-YYYY-NNN [--sections executive-summary,technical-approach]"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /pursuit-draft — Draft proposal sections (SE-015)

**Argumentos:** `$ARGUMENTS` — OPP-ID required

## Flujo

1. Locate pursuit directory from OPP-ID
2. Verify bid-decision.md exists with decision=go (gate: cannot draft without bid approval)
3. Read pursuit.md for client context, practice, compliance requirements
4. Search library/ for relevant assets:
   - `library/capabilities/` matching practice area
   - `library/case-studies/` matching sector or engagement type
   - `library/team-bios/` for listed pursuit team members
   - `library/templates/` matching engagement type
5. Create `proposal/` directory if missing
6. Draft sections:
   - `executive-summary.md` — value proposition + differentiators
   - `technical-approach.md` — methodology + architecture
   - `compliance-matrix.md` — mapping requirements to capabilities
7. Mark each section as DRAFT requiring human review

## Privacy

All drafting uses context from the local library/ directory.
No pursuit content is sent to external APIs.
Air-gap mode: uses savia-dual Ollama fallback if available.

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-draft — Completado
  {OPP-ID}: {N} sections drafted
  Path: {pursuit-dir}/proposal/
  Status: DRAFT — requires human review
  Next: review sections, then /pursuit-handoff when won
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
