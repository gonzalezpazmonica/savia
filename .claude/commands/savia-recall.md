---
name: savia-recall
description: Recall and retrieve information from Savia memory
tier: core
---

---

# /savia-recall

> Unified memory search: memory-store + agent MEMORY.md files + lessons.md

```frontmatter
agent: task
model_tier: fast
context_cost: low
```

## Arguments

`"query"` — Search term (case-insensitive)

Optional:
- `--type {memory|agent-memory|lessons}` — Filter by source
- `--depth {quick|full}` — Output verbosity (default: quick)

## Process

Search three sources in parallel:

### Source 1: Memory Store (JSONL)

```bash
bash "$PROJECT_ROOT/scripts/memory-store.sh" search "$query"
```

Returns: user-captured decisions, bugs, patterns, conventions

### Source 2: Agent Memory (Markdown)

```bash
find "$PROJECT_ROOT/.claude/agent-memory" -name "MEMORY.md" -exec grep -l "$query" {} \;
```

Returns: patterns learned by agents (architect, security-guardian, etc.)

### Source 3: Lessons (Markdown)

```bash
grep -i "$query" "$PROJECT_ROOT/tasks/lessons.md" 2>/dev/null || true
```

Returns: mistakes to avoid (category, lesson, source)

## Output Format

```
📚 Search Results: "testing"

MEMORY STORE (2 hits):
  [2026-03-04] (pattern) Jest testing with mock factories
  [2026-03-01] (decision) Unit tests before features

AGENT MEMORY (1 hit):
  test-runner.md: N+1 test iteration avoided with batch assertion

LESSONS (1 hit):
  2026-02-28 | Testing | Use .each() not nested loops | Unit test refactor
```

Each result shows source, date, snippet. Link back to original file.

## Use Cases

- "Where did we decide X?" — Check memory-store decisions
- "What patterns exist for Y?" — Check agent MEMORY
- "Did we try this before?" — Check lessons archive
