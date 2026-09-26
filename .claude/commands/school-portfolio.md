---
name: school-portfolio
description: Student portfolio view and learning journey showcase
argument-hint: "<alias> [--export pdf|html]"
allowed-tools: [Read, Write, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# School Portfolio

Display student's complete learning portfolio and project showcase.

## Parameters

- `<alias>` — Student alias
- `--export {pdf|html}` — Generate exportable format (student can share)

## Execution

1. Verify isolation and consent
2. Load projects: all in `classroom/{alias}/projects/`
3. Load progress.md and learning diary
4. Compile summary: completed projects, evaluations (summary), growth metrics
5. If export: generate PDF/HTML suitable for sharing (no sensitive data)
6. Audit: `audit-access {alias} portfolio-view`

## Portfolio Contents

```
📖 {alias}'s Learning Portfolio

Progress: X projects completed
Completion rate: Y%
Latest achievement: {date}

📝 Project Showcase:
- {project}: Brief description, completion date
- {project}: Brief description, completion date

📊 Growth: Areas improved, learning goals met

🎯 Next Steps: Recommended projects/skills
```

## Export Options

- **PDF**: Student can print/archive (no encryption)
- **HTML**: Student can embed in blog/website

All exports exclude encrypted evaluations and identifiers.

## Output

```yaml
status: OK
student: {alias}
projects: count
format: {"portfolio" | "pdf" | "html"}
shareable: true
```

⚡ /compact
