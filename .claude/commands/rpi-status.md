---
name: rpi-status
description: Track progress of active RPI (Research → Plan → Implement) workflows.
argument-hint: "[feature-name] [--all]"
allowed-tools: [Read, Glob, Grep]
model_tier: fast
context_cost: low
tier: core
---

# /rpi-status — RPI Workflow Progress

Show current status of active Research → Plan → Implement workflows.

## Usage

- `/rpi-status` — Show all active RPI workflows
- `/rpi-status {feature}` — Detailed status for a specific feature
- `/rpi-status --all` — Include completed workflows

## Behavior

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 /rpi-status — RPI Workflows
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### List mode (default)

1. Scan `rpi/*/` directories
2. For each, determine phase by checking which files exist:
   - Only REQUEST.md → Phase 1 (Research)
   - REQUEST.md + RESEARCH.md → Gate 1 pending or Phase 2
   - + PLAN.md → Gate 2 pending or Phase 3
   - + IMPLEMENT.md → Phase 3 in progress or Complete
3. Display summary table:

| Feature | Phase | Gate | Status | Started |
|---|---|---|---|---|
| oauth-login | Plan | Gate 2 ✅ | 3/5 PBIs planned | 2026-03-01 |

### Detail mode (`/rpi-status {feature}`)

1. Read all files in `rpi/{feature}/`
2. Show phase-by-phase progress:
   - Research: key findings
   - Plan: PBI count, architecture decisions
   - Implement: spec status per PBI (pending/in-progress/done)
3. Show next action needed

## Phase Detection

| Files present | Current phase |
|---|---|
| REQUEST.md | Research (Phase 1) |
| + RESEARCH.md | Gate 1 or Plan (Phase 2) |
| + PLAN.md | Gate 2 or Implement (Phase 3) |
| + IMPLEMENT.md | In Progress or Complete |
