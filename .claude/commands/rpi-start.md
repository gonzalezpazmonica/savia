---
name: rpi-start
description: >
  Start a Research → Plan → Implement workflow for a feature with GO/NO-GO gates.
argument-hint: "{feature-name} [--project name] [--skip-research]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /rpi-start — Research → Plan → Implement Workflow

Orchestrates existing skills through a formal workflow with validation gates.

## Usage

- `/rpi-start {feature}` — Start full RPI workflow
- `/rpi-start {feature} --project {name}` — Specify project
- `/rpi-start {feature} --skip-research` — Skip to Plan phase

## Workflow

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔬 /rpi-start — Research → Plan → Implement
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Phase 1 — Research (skill: product-discovery)

1. Create folder: `rpi/{feature-slug}/`
2. Create `REQUEST.md` from user's feature description
3. Execute product-discovery skill: JTBD, user personas, competitive analysis
4. Output: `RESEARCH.md` with findings
5. **GO/NO-GO Gate 1**: Present findings, ask PM to proceed or pivot

### Phase 2 — Plan (skill: pbi-decomposition + architect)

1. Decompose feature into PBIs using pbi-decomposition skill
2. Architecture analysis via architect agent
3. Risk assessment via risk-predict
4. Output: `PLAN.md` with PBIs, architecture, risks, timeline
5. **GO/NO-GO Gate 2**: Present plan, ask PM to approve or revise

### Phase 3 — Implement (skill: spec-driven-development)

1. Generate specs for each PBI via sdd-spec-writer
2. Assign to developer agents based on language pack
3. Track progress via spec-status
4. Output: `IMPLEMENT.md` with status of each spec
5. **Completion Gate**: All specs implemented and reviewed

## File Structure

```
rpi/{feature-slug}/
├── REQUEST.md       ← Original feature request
├── RESEARCH.md      ← Phase 1 output (discovery)
├── PLAN.md          ← Phase 2 output (decomposition + architecture)
└── IMPLEMENT.md     ← Phase 3 output (spec status tracker)
```

## GO/NO-GO Gates

| Gate | Criteria for GO | Actions on NO-GO |
|---|---|---|
| Gate 1 | Research validates need | Pivot, descope, or cancel |
| Gate 2 | Plan is feasible + approved | Revise scope or architecture |
| Completion | All specs pass review | Fix issues, re-review |

## Agent Assignment by Phase

| Phase | Agent | Skill |
|---|---|---|
| Research | business-analyst | product-discovery |
| Plan | architect + business-analyst | pbi-decomposition |
| Implement | {lang}-developer | spec-driven-development |
| Review | code-reviewer | — |
