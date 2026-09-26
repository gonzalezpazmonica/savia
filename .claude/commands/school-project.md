---
name: school-project
description: Student creates a new project from template
argument-hint: "<alias> <project_name>"
allowed-tools: [Read, Bash, Write]
model_tier: mid
context_cost: low
tier: core
---

# School Project

Create a new project for a student from the standard template.

## Parameters

- `<alias>` — Student alias
- `<project_name>` — Project name (e.g., "proyecto-ecuaciones-cuadraticas")

## Execution

1. Verify student isolation: `bash scripts/savia-school-security.sh check-isolation {alias}`
2. Verify consent: `bash scripts/savia-school-security.sh gdpr-consent {alias}`
3. Execute: `bash scripts/savia-school.sh project-create {alias} {project_name}`
4. Copy template from `templates/project.template.md`
5. Audit: `audit-access {alias} project-creation`
6. Return project directory path

## Project Template Structure

```
projects/{project_name}/
├── README.md           (objectives, requirements)
├── PROGRESS.md         (student self-assessment)
├── DELIVERABLES/       (code, documents)
└── .submitted          (marker file after submission)
```

## Output

```yaml
status: OK
student: {alias}
project: {project_name}
path: classroom/{alias}/projects/{project_name}
ready: true
```

⚡ /compact
