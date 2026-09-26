---
name: school-enroll
description: Enroll student using alias (NO real names — privacy-first)
argument-hint: "<alias>"
allowed-tools: [Read, Bash, Write]
model_tier: mid
context_cost: low
tier: core
---

# School Enroll

Register a new student using an alias. NO personally identifiable information stored.

## Parameters

- `<alias>` — Student alias (e.g., "estudiante-001", NOT real name)

## Execution

1. Prompt: "Are you enrolling under an alias? Confirm: YES"
2. Verify alias format: alphanumeric + hyphens only
3. Execute: `bash scripts/savia-school.sh enroll {alias}`
4. Create empty portfolio.md and progress.md
5. Request parental consent form upload (external, not stored)
6. Create .consent marker if provided
7. Audit: `bash scripts/savia-school-security.sh audit-access {alias} enrollment`

## Security Checks

- ✅ Alias isolation: no cross-student access
- ✅ Consent verification: required before any data processing
- ✅ Audit trail: enrollment logged

## Output

```yaml
status: OK
student: {alias}
folder: classroom/{alias}
consent: recorded
audit: logged
```

⚡ /compact
