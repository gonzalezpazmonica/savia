---
name: school-setup
description: Configure classroom and initialize Savia School vertical
argument-hint: "<school_name> <course> <subject>"
allowed-tools: [Read, Write, Bash]
model_tier: mid
context_cost: low
tier: core
---

# School Setup

Configure a new classroom for the Savia School vertical.

## Parameters

- `<school_name>` — School name (e.g., "Academia Matemática")
- `<course>` — Course/grade level (e.g., "3º ESO")
- `<subject>` — Subject area (e.g., "Álgebra")

## Execution

1. Read AEPD compliance checklist from `.opencode/skills/savia-school/references/school-safety-config.md`
2. Prompt: Confirm parental consent form location and archival method
3. Execute: `bash scripts/savia-school.sh setup {name} {course} {subject}`
4. Create CODEOWNERS: `teacher/* → @profesor` (git protection)
5. Initialize empty `teacher/rubrics/` with template structure
6. Confirm: Directory structure created with encryption enabled

## Output Format

```yaml
status: OK
school: {name}
structure: initialized
encryption: enabled
gdpr: compliant
message: "Classroom ready for enrollment"
```

⚡ /compact — Libera contexto antes del siguiente comando
