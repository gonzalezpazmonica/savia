---
name: pursuit-qualify
description: Run BANT + MEDDIC qualification scoring on a pursuit
argument-hint: "OPP-YYYY-NNN [--tenant tenant-id]"
context_cost: medium
model_tier: mid
allowed-tools: [Read, Write, Bash, Glob, Grep]
tier: core
---

# /pursuit-qualify — Qualify a pursuit (SE-015)

**Argumentos:** `$ARGUMENTS` — OPP-ID required

## Flujo

1. Locate pursuit directory from OPP-ID (search tenants/*/pipeline/pursuits/)
2. Read pursuit.md frontmatter
3. Verify stage is at least `lead`
4. Analyze pursuit data and compute BANT scoring:
   - Budget (0-5): Is budget confirmed? By whom?
   - Authority (0-5): Economic buyer identified? Access confirmed?
   - Need (0-5): Is need regulatory, strategic, or nice-to-have?
   - Timing (0-5): Hard deadline? Decision timeline clear?
5. Compute MEDDIC scoring:
   - Metrics, Economic Buyer, Decision Criteria, Decision Process,
     Identify Pain, Champion (0-5 each)
6. Calculate totals and percentages
7. Generate recommendation (GO / NO-GO / NEEDS-INFO) based on:
   - BANT >= 60% AND MEDDIC >= 50% → recommend GO
   - Either below threshold → recommend NEEDS-INFO
   - Both below 40% → recommend NO-GO
8. Write qualification.yaml to pursuit directory
9. Update pursuit.md stage to "qualification" if currently "lead"

## Output format (qualification.yaml)

```yaml
bant:
  budget: { score: N, max: 5, rationale: "..." }
  authority: { score: N, max: 5, rationale: "..." }
  need: { score: N, max: 5, rationale: "..." }
  timing: { score: N, max: 5, rationale: "..." }
  total: N
  max: 20
  pct: N

meddic:
  metrics: { score: N, rationale: "..." }
  economic_buyer: { score: N, rationale: "..." }
  decision_criteria: { score: N, rationale: "..." }
  decision_process: { score: N, rationale: "..." }
  identify_pain: { score: N, rationale: "..." }
  champion: { score: N, rationale: "..." }
  total: N
  max: 30
  pct: N

recommendation: "GO | NO-GO | NEEDS-INFO — rationale"
bid_no_bid: pending
```

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-qualify — Completado
  {OPP-ID}: BANT {N}% | MEDDIC {N}%
  Recommendation: {GO|NO-GO|NEEDS-INFO}
  Next: /pursuit-bid {OPP-ID} {go|no-go}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
