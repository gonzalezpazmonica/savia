---
layer: peripheral
name: risk-scoring
description: Usar cuando se calcula el riesgo de una tarea para decidir el nivel de revisión requerido.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Calcula score de riesgo (0-100) para tasks y PRs. 8 factores: complejidad, seguridad, deps, cobertura, etc. Enruta a nivel de review apropiado (low/medium/high/critical)."
  savia.tags: "risk, scoring, escalation, review-routing"
---

# Risk Scoring for Intelligent Escalation

Automated 4-phase pipeline to assess task complexity and route code reviews to appropriate escalation levels based on risk factors, replacing fixed Code Review rules with intelligent, data-driven routing.

## Decision Checklist

Before scoring, answer sequentially:

1. Does the change touch critical paths (auth, payments, data migration)? -> If YES: minimum score = 51 (High)
2. Is this a security patch or compliance fix? -> If YES: auto-escalate to Critical (76+)
3. Does the PR introduce new external dependencies? -> If YES: add +10 to base score
4. Is this the author's first change to this module? -> If YES: add +10 (unfamiliarity penalty)
5. Are there >500 lines changed? -> If YES: add +15 to base score

### Abort Conditions
- PR modifies .env, secrets, or credentials -> STOP, mandatory security review
- PR has no tests and touches business logic -> STOP, require tests first

---

## Phase 1: Collect Risk Signals

Extract risk indicators from task metadata: files touched, modules affected, external dependencies, security tags, compliance tags, data migration, production impact, change history.

## Phase 2: Calculate Risk Score (0-100)

Weighted scoring system across 8 dimensions: file count, module criticality, external dependencies, security, compliance, data impact, historical signals.

## Phase 3: Route to Review Level

Four-tier escalation based on score (enforced, not advisory):
- Low (0-25): Skip consensus panel. Auto-merge after PR Guardian Gates 1-5 pass. Spot-check only
- Medium (26-50): Standard 4-judge consensus panel (reflection + code + business + performance)
- High (51-75): Full 4-judge consensus + mandatory human reviewer. Veto on any CRITICAL finding
- Critical (76-100): Full consensus + security team review + PM approval. Block merge until all sign off

## Phase 4: Generate Risk Report

Comprehensive breakdown with score, factor breakdown, review requirements, suggested reviewers, timeline, and mitigations.

## Integration Points

- **PR Guardian Gate 7**: Risk score informs context impact analysis
- **consensus-validation**: Tier determines which judges run (Low skips, Medium-Critical runs full panel)
- **dag-scheduling**: High/Critical PRs dispatch judges via DAG for parallel execution
- **Audit Trail**: All routing decisions logged to `output/risk/{timestamp}-{pr}.json`
- **PM Override**: Can manually escalate or de-escalate tier
