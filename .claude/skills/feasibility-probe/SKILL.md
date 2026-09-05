---
layer: peripheral
name: feasibility-probe
description: Usar cuando se necesita validar si una spec es técnicamente viable antes de implementarla.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: sdd-framework
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.priority: high
  savia.summary: "Valida viabilidad de un spec con prototipo time-boxed. Intenta implementar las secciones criticas, mide bloqueos. Output: score de viabilidad + secciones problematicas."
  savia.tags: "feasibility, estimation, prototype, spec, planning"
  savia.user-invocable: True
---

# Feasibility Probe

Validates a spec by attempting a time-boxed prototype. Produces a viability report that feeds sprint planning with evidence-based estimates.

## Decision Checklist

Before running the probe:

1. Is the spec approved (status: approved)? If NO -> abort, spec needs review first.
2. Does the spec have testable acceptance criteria? If NO -> abort, spec is too vague.
3. Are external dependencies documented? If NO -> warn, will mock everything.
4. Is the budget appropriate for spec size? If >20 requirements -> suggest splitting.
5. Has this spec been probed before? If YES -> show previous score, ask if re-probe.

## Parameters

| Param | Required | Default | Description |
|---|---|---|---|
| spec_path | Yes | - | Path to the spec file |
| budget_minutes | No | 15 | Max time for prototype attempt (time-box, orthogonal to model thinking) |

**Thinking budget (SE-067 — Opus 4.7 adaptive):** Fixed `budget_tokens` removed. Opus 4.7 uses adaptive thinking — the model decides when and how much to think per step. Simple probes get fast responses, complex reasoning steps get deep thought. Over a multi-step probe run this adds up to lower token usage vs the old fixed 50000-token budget with no quality loss.

To steer thinking rate when needed, append to the probe prompt:
- More thinking: `"Think carefully and step-by-step; this is harder than it looks."`
- Less thinking: `"Prioritize responding quickly rather than thinking deeply."`

## Execution Flow

```
1. Read spec -> extract requirements checklist
2. Launch feasibility-probe agent (Task) with budget
3. Agent attempts prototype in /tmp/
4. Agent writes report to output/feasibility/
5. Parse score and route:
   - >= 80: "Ready for sprint planning"
   - 40-79: "Recommend decomposition" + suggestions
   - < 40:  "Requires research" + escalate to human
6. Store report in memory for model-upgrade-audit tracking
```

## Output

Report saved to: `output/feasibility/{spec-id}-probe.yaml`

Summary shown in chat:
```
Feasibility: {score}/100 | {resolved}/{total} requirements
Complexity: {level} | Time: {minutes}m
Blocking: {list of blocked sections}
Recommendation: {action}
```

## Integration Points

- **Pre-sprint**: Run on all specs before sprint planning
- **SDD pipeline**: Optional gate between spec-approve and dev-session
- **Memory**: Results stored for longitudinal tracking
- **Model audit**: SPEC-002 consumes historical probe data

## Scoring Formula

```
score = (resolved * 100 + partial * 50) / total_requirements
complexity = score >= 90 ? "trivial"
           : score >= 70 ? "low"
           : score >= 50 ? "medium"
           : score >= 30 ? "high"
           : "requires-research"
```
