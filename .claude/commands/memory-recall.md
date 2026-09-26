---
name: memory-recall
description: Retrieve relevant memories for current context
tier: core
---

---

# /memory-recall

> Progressive memory disclosure: index → timeline → full details

```frontmatter
agent: task
model_tier: fast
context_cost: low
```

## Arguments

- `index` — Show titles, types, concepts only (minimal tokens)
- `timeline [--limit 10]` — Last N entries with short summaries
- `detail {topic_key}` — Full content of specific entry

## Process

### Index View

```bash
bash "$PROJECT_ROOT/scripts/memory-store.sh" context --limit 100 | \
  awk -F'(' '{print $2}' | cut -d')' -f1 | sort -u
```

Shows unique types and concept breakdown. Minimal output for quick scanning.

### Timeline View

```bash
bash "$PROJECT_ROOT/scripts/memory-store.sh" context --limit "${limit:-10}"
```

Displays last N entries with date, type, and title. One line per entry for easy scrolling.

### Detail View

```bash
bash "$PROJECT_ROOT/scripts/memory-store.sh" context --limit 1000 | \
  grep "\"topic_key\":\"$topic_key\"" | jq '.'
```

Retrieves full entry: content, concepts, tokens, revision. Useful for re-reading decisions or patterns.

## Output

**Index:** Flat list of (type) labels. Shows what's in memory without reading.

**Timeline:** Chronological summaries. Good for "what did we decide recently?"

**Detail:** Full JSONL entry with all metadata. Preserves all context for deep review.

## Examples

```
/memory-recall index
→ Shows: (decision) (bug) (pattern) (convention) (discovery)

/memory-recall timeline --limit 5
→ Shows: [2026-03-04] (pattern) Name conventions in entities
         [2026-03-03] (decision) Adopt GraphQL for frontend

/memory-recall detail auth-flow-v2
→ Shows full entry with content, concepts, estimation
```
