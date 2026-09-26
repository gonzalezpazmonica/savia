---
name: score-diff
description: >
  Compara métricas de calidad del workspace entre dos git refs para tracking de regresiones.
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - Task
tier: core
---

# /score-diff — Compare Workspace Metrics Between Versions

## Description

Compares PM-Workspace quality metrics between two git refs to track
improvement or regression over time. Inspired by kimun's score diff.

## Usage

```
/score:diff [--from <ref>] [--to <ref>] [--dimension <name>]
```

**Defaults**: `--from HEAD~5` `--to HEAD`

## Process

### Step 1: Collect Metrics at Each Ref

For each git ref, compute:

- **Files**: total count, avg lines, files over 150-line cap
- **Rules**: domain rules count, avg lines
- **Tests**: test count, pass rate (from last CI run if available)
- **Agents**: count, agents with MEMORY.md
- **Commands**: count, commands with frontmatter
- **Context**: CLAUDE.md line count, estimated token load

### Step 2: Compute Deltas

For each metric, calculate:
- Absolute delta (new - old)
- Percentage change
- Direction arrow (↑ improvement, ↓ regression, → stable)
- Score using piecewise curves from `scoring-curves.md`

### Step 3: Classify Changes

Apply Rule of Three severity:
- **3+ regressions** in same dimension → CRITICAL (action required)
- **2 regressions** → WARNING (monitor)
- **1 regression** → INFO (acceptable variance)
- **All stable or improving** → HEALTHY

### Step 4: Output

```
═══════════════════════════════════════════════════════
  Score Diff: v2.1.0 → v2.3.0
═══════════════════════════════════════════════════════

  Dimension         Before   After   Delta   Score
  ──────────────────────────────────────────────────
  Rules             62       65      +3 ↑     85
  Commands          336      339     +3 ↑     90
  Tests             400      430     +30 ↑    95
  CLAUDE.md lines   120      120     → 0      100
  Avg file size     78       80      +2 →     95
  Files > 150 ln    0        0       → 0      100

  Overall: 94/100 — HEALTHY
  Trend: ↑ Improving (3 consecutive releases)
═══════════════════════════════════════════════════════
```

Save to: `output/scores/YYYYMMDD-score-diff.md`

## Subagent Config

```yaml
model_tier: fast
memory: project
permissionMode: plan
```

Use the fast tier — this is a data-collection task, not reasoning.

## Scheduling

Recommended: run after each release or weekly.
Can integrate with `/hub-audit` for combined health report.

## References

- kimun (lnds/kimun). Score diffing with git refs
- scoring-curves.md for normalization breakpoints
