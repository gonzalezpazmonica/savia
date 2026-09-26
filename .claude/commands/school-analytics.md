---
name: school-analytics
description: Teacher class-wide analytics and progress dashboard
argument-hint: "[--by-project|--by-student]"
allowed-tools: [Read, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# School Analytics

Teacher dashboard for class-wide learning analytics and trends.

## Parameters

- `--by-project` — Group metrics by project (default)
- `--by-student` — Group metrics by student
- `--trend {days}` — Show trend over N days (default: 30)

## Execution

1. Verify role: teacher-only access
2. Scan all `classroom/*/projects/` for timestamps and status
3. Count: submitted projects, evaluated projects, completion rate
4. Calculate: average time to completion, submission rate
5. Audit: `audit-access teacher analytics-view`
6. Generate dashboard table

## Analytics Shown

```
📊 Class Analytics

Total students: X
Total projects: Y
Completion rate: Z%

By Project:
- {name}: X submitted, Y evaluated, Z% completion

By Student:
- {alias}: X projects, avg_completion_time, engagement: HIGH

Trends (30d):
- Submissions/week: trend ↑↓
- Evaluation backlog: X pending
- Most challenging topic: {name}

Key insight: {observation based on data}
```

## Security

- ✅ Teacher-only access (verified by role)
- ✅ No evaluation scores exported (encrypted)
- ✅ Aggregated metrics only (no individual grades)
- ✅ Audit trail recorded

## Output

```yaml
status: OK
role: teacher
students: count
projects: count
completion_rate: percentage
trend_period: 30_days
format: dashboard_table
```

⚡ /compact
