---
name: feasibility-probe
description: "Validate spec feasibility with a time-boxed prototype attempt"
argument-hint: "<spec_path> [--budget 15]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
model_tier: mid
context_cost: high
tier: core
---

# /feasibility-probe $ARGUMENTS

Skill: `@.opencode/skills/feasibility-probe/SKILL.md`

## Execution

1. Parse `$ARGUMENTS` -> extract `spec_path` and optional `--budget N` (default 15 min)
2. Read and validate the spec file
3. Extract requirements as checklist
4. Launch `feasibility-probe` agent via Task with:
   - Spec content
   - Budget constraint
   - Working directory: `/tmp/feasibility-probe-{timestamp}/`
5. Collect agent report
6. Write to `output/feasibility/{spec-id}-probe.yaml`
7. Route by score:
   - `>= 80`: "Ready for sprint planning"
   - `40-79`: "Recommend decomposition" + show suggestions
   - `< 40`: "Requires research" + escalate

## Output (chat summary)

```
Feasibility Probe: {spec_id}
Score: {N}/100 | {resolved}/{total} requirements resolved
Complexity: {level} | Budget used: {N}m of {budget}m
Blocking: {count} sections
Report: output/feasibility/{spec-id}-probe.yaml
Recommendation: {action}
```
