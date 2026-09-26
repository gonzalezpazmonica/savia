---
name: school-export
description: GDPR Article 15 — Export all student data in portable format
argument-hint: "<alias>"
allowed-tools: [Read, Bash, Write]
model_tier: mid
context_cost: medium
tier: core
---

# School Export

GDPR Article 15: Right to Access — Export all student data.

## Execution

1. Verify request authenticity (student or parent/guardian)
2. Execute: `bash scripts/savia-school.sh export {alias}`
3. Compress all student folder into dated tarball
4. Contents included:
   - Projects and deliverables
   - Progress tracking
   - Learning diary (plaintext)
   - Portfolio snapshot
   - Evaluations (encrypted — key provided separately if requested)
5. Generate MANIFEST.md with file list
6. Output file: `output/gdpr-export-{alias}-YYYYMMDD.tar.gz`
7. Audit: `audit-access {alias} gdpr-export`
8. Message: "Export ready. Download link provided. Valid for 30 days."

## Contents Exported

```
gdpr-export-{alias}/
├── projects/         (all deliverables)
├── progress.md       (growth records)
├── DIARY.md          (reflections)
├── portfolio.html    (showcase summary)
└── MANIFEST.md       (file list with dates)
```

## Security

- ✅ Encrypted evaluations included (encrypted key provided via separate channel)
- ✅ No teacher comments exposed (encrypted)
- ✅ All timestamps included (audit trail)

## Output

```yaml
status: OK
student: {alias}
format: tar.gz
size: estimated_MB
path: output/gdpr-export-{alias}-YYYYMMDD.tar.gz
expires: "+30 days"
audit: logged
```

⚡ /compact
