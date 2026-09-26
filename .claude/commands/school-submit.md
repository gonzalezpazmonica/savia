---
name: school-submit
description: Student submits completed project for evaluation
argument-hint: "<alias> <project_name>"
allowed-tools: [Bash, Read]
model_tier: mid
context_cost: low
tier: core
---

# School Submit

Mark a student project as submitted for teacher evaluation.

## Parameters

- `<alias>` — Student alias
- `<project_name>` — Project name

## Execution

1. Verify student isolation and consent (security pre-check)
2. Execute: `bash scripts/savia-school.sh submit {alias} {project_name}`
3. Create .submitted marker with timestamp
4. Verify deliverables exist (prevent empty submissions)
5. Audit: `audit-access {alias} submission`
6. Notify teacher (console message; no email storage)

## Validation

- ✅ Project directory exists
- ✅ Student consent active
- ✅ Deliverables present (at least one file)
- ✅ Timestamp recorded

## Output

```yaml
status: OK
student: {alias}
project: {project_name}
submitted_at: ISO8601_timestamp
next_step: "Teacher will evaluate within 3 working days"
```

⚡ /compact
