---
name: school-evaluate
description: Teacher evaluates student project using encrypted rubric
argument-hint: "<alias> <project_name> <rubric_name>"
allowed-tools: [Bash, Read, Write]
model_tier: mid
context_cost: medium
tier: core
---

# School Evaluate

Teacher assessment of student project. Evaluation stored ENCRYPTED.

## Parameters

- `<alias>` — Student alias
- `<project_name>` — Project being evaluated
- `<rubric_name>` — Rubric template (e.g., "rubric-algebra-2024")

## Execution

1. Verify role: `verify_role teacher` (teacher-only gate)
2. Load rubric: `teacher/rubrics/{rubric_name}.md`
3. Prompt: Enter evaluation (strengths, improvements, grade)
4. Filter content: `bash scripts/savia-school-security.sh filter-content "{evaluation}"`
5. Encrypt: `bash scripts/savia-school-security.sh encrypt-eval {alias} "{content}"`
6. Audit: `audit-access {alias} evaluation`
7. Confirm: "Evaluation encrypted and stored"

## Rubric Structure

```
Criteria: (Conceptual Understanding, Execution, Communication)
Scores: 1 (Novice) - 4 (Exemplary)
Comments: Encrypted field
```

## Output

```yaml
status: OK
student: {alias}
project: {project_name}
evaluated_at: ISO8601
encryption: AES-256
access: teacher_only
```

⚡ /compact
