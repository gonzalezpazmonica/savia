---
name: skill-rank
description: Show skill effectiveness ranking based on invocation data
argument-hint: "[--detail SKILL] [--dormant] [--deprecated] [--export csv]"
allowed-tools: [Read, Bash, Glob, Grep, Write]
model_tier: mid
context_cost: medium
tier: core
---

# /skill-rank

Show skill effectiveness ranking based on real invocation data.

## Parameters

- (none): Full ranking table
- `--detail {name}`: Per-invocation log for one skill
- `--dormant`: List dormant skills only
- `--deprecated`: List deprecation candidates only
- `--export csv`: Export as CSV

## Flow

1. Run `bash scripts/skill-feedback-rank.sh` with user arguments
2. Display result in chat
3. Show output file path

## Data source

- `data/skill-invocations.jsonl` (append-only, gitignored)
- Populated by `scripts/skill-feedback-log.sh` after each skill activation

## Scoring formula

```
effectiveness = success_rate * 0.50 + accept_rate * 0.30 + recency_weight * 0.20
```
