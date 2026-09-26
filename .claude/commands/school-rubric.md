---
name: school-rubric
description: Create or edit evaluation rubrics for grading
argument-hint: "<rubric_name> [--edit|--view]"
allowed-tools: [Read, Write, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# School Rubric

Teacher tool to create and manage evaluation rubrics.

## Parameters

- `<rubric_name>` — Unique rubric identifier (e.g., "rubric-algebra-2024")
- `--edit` — Create or modify rubric
- `--view` — Display existing rubric

## Execution

### Create/Edit

1. Prompt: "Define rubric criteria (comma-separated)"
2. Prompt: "Define scoring levels (e.g., Novice:1, Developing:2, Proficient:3, Exemplary:4)"
3. Generate template structure
4. Save to: `teacher/rubrics/{rubric_name}.md`
5. Confirm: "Rubric created and available for evaluations"

### View

1. Read `teacher/rubrics/{rubric_name}.md`
2. Display criteria, levels, and descriptions
3. Show usage: "Used in X evaluations"

## Rubric Template

```markdown
# {rubric_name}

## Criteria

### Conceptual Understanding
1. Novice: Shows limited understanding
2. Developing: Understands basic concepts
3. Proficient: Applies concepts accurately
4. Exemplary: Extends understanding creatively

### Execution
1. Novice: Incomplete or inaccurate execution
...
```

## Security

- ✅ Teacher-only creation/edit (role verified)
- ✅ Audit: creation/modification logged
- ✅ Version control: timestamped

## Output

```yaml
status: OK
rubric: {rubric_name}
mode: "view|edit|create"
criteria_count: X
levels: 4
ready_for_use: true
```

⚡ /compact
