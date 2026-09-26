---
name: school-diary
description: Student learning diary and reflection journal
argument-hint: "<alias> [--add|--view]"
allowed-tools: [Read, Write, Bash]
model_tier: mid
context_cost: low
tier: core
---

# School Diary

Student self-assessment journal for learning reflections.

## Parameters

- `<alias>` — Student alias
- `--add` — Record new diary entry
- `--view` — Read past entries (default)

## Execution

### Add Entry

1. Prompt: "What did you learn today? What was challenging?"
2. Filter: `filter-content "{entry}"` (age-appropriate check)
3. Append to: `classroom/{alias}/DIARY.md` (plaintext, ISO8601 dated)
4. Audit: `audit-access {alias} diary-write`
5. Confirm: "Entry saved"

### View Entries

1. Read `classroom/{alias}/DIARY.md` (last 10 entries)
2. Show: date, brief summary
3. Audit: `audit-access {alias} diary-read`

## Diary Format

```markdown
# {alias} Learning Diary

## {ISO8601_date}
What I learned: ...
What was hard: ...
Questions: ...

---

## {ISO8601_date}
...
```

## Student Privacy

- Entries are plaintext but folder is alias-protected
- Teacher has read access only (educational oversight)
- No encryption—simplicity over confidentiality for reflection

## Output

```yaml
status: OK
student: {alias}
entries: count
mode: "add|view"
```

⚡ /compact
