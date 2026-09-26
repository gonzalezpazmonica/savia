---
name: school-progress
description: View student progress and portfolio
argument-hint: "<alias> [--portfolio]"
allowed-tools: [Read, Bash]
model_tier: mid
context_cost: low
tier: core
---

# School Progress

Display student learning progress and portfolio summary.

## Parameters

- `<alias>` — Student alias
- `--portfolio` — Show full portfolio instead of quick progress

## Execution

1. Verify student isolation: `check-isolation {alias}`
2. Read `classroom/{alias}/progress.md`
3. If `--portfolio`: Read `classroom/{alias}/portfolio.md` and list projects
4. Count completed projects, submission dates, grades (summary only)
5. Audit: `audit-access {alias} progress-view`

## Quick Progress View

```
Student: {alias}
Projects completed: X
Last submission: DATE
Overall engagement: HIGH|MEDIUM|LOW
Feedback: {brief summary of last evaluation}
```

## Portfolio View

```
📚 Portfolio: {alias}

Projects:
1. {project_name} - Submitted DATE - Status: EVALUATED
2. {project_name} - Submitted DATE - Status: PENDING

Learning Diary: Last 3 entries shown (teacher-controlled)
```

## Security

- Student sees only own data
- Teacher sees all + analytics
- Evaluations remain encrypted

⚡ /compact
