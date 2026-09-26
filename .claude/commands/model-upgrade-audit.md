---
name: model-upgrade-audit
description: "Audit workspace components for prompt debt that newer models may not need"
argument-hint: "[--scope full|agents|skills|rules] [--changed-since ERA-N]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /model-upgrade-audit $ARGUMENTS

Skill: `@.opencode/skills/model-upgrade-audit/SKILL.md`

## Execution

1. Parse `$ARGUMENTS` -> extract scope and filters
2. Detect current model from pm-config.md
3. Inventory components in scope (glob agents + skills + rules)
4. Launch `model-upgrade-auditor` agent via Task with:
   - Component list with paths
   - Workaround pattern definitions
   - Current model info
5. Collect per-component analysis
6. Write YAML report to `output/model-audit/{date}-audit.yaml`
7. Show summary grouped by recommendation (APPLY / REVIEW / SKIP)

## Output (chat summary)

```
Model Upgrade Audit
Components: {N} audited | {N} simplifiable | {N} no change
Savings: ~{N} tokens/session ({pct}% reduction)
APPLY (low risk): {list}
REVIEW (medium): {list}
SKIP (high risk): {list}
Report: output/model-audit/{date}-audit.yaml
```
