---
name: school-forget
description: GDPR Article 17 — Right to Erasure, complete data deletion
argument-hint: "<alias>"
allowed-tools: [Bash]
model_tier: mid
context_cost: low
tier: core
---

# School Forget

GDPR Article 17: Right to Erasure — Permanent deletion of student data.

## CRITICAL: Requires Parent/Guardian Consent

This command is **destructive and irreversible**. Must be authorized by:
- Parent/guardian if student is minor
- Student themselves if adult

## Execution

1. Prompt: "Confirm right to erasure request. Type: DELETE {alias}"
2. Verify request source (parent email + signed consent required)
3. Execute: `bash scripts/savia-school.sh forget {alias}`
   - Deletes: `classroom/{alias}/` (all projects, diary, progress)
   - Deletes: `teacher/evaluations/{alias}/` (all encrypted evals)
4. Audit final action: `audit-access {alias} deletion-final`
5. Confirm: "All data deleted. Audit trail retained for 30 days per GDPR."

## What's Permanently Deleted

- ❌ Projects and deliverables
- ❌ Progress records
- ❌ Learning diary
- ❌ Portfolio
- ❌ Encrypted evaluations

## What's Retained (30 days)

- ✅ Audit log (for legal compliance)
- ✅ Consent record (proof of authorization)

## Output

```yaml
status: OK
student: {alias}
action: permanent_deletion
executed_at: ISO8601
audit_trail: retained_30_days
gdpr_compliant: true
message: "Data erasure complete. Audit trail available to student upon request."
```

⚠️ This action CANNOT be undone. Verify authorization before confirming.

⚡ /compact
