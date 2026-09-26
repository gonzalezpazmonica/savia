---
name: memory-consolidate
description: Consolidate and compress memory entries to save context
tier: core
---

---

# /memory-consolidate

> End-of-day consolidation: group by concept, remove redundancy, create summary

```frontmatter
agent: task
model_tier: fast
context_cost: medium
```

## Arguments

- `--dry-run` — Preview consolidations without modifying store
- `--date YYYY-MM-DD` — Consolidate entries from specific date (default: today)

## Process

1. **Find today's entries** matching specified date
2. **Group by concept** from `concepts` array
3. **Deduplicate** same topic_key with lower rev
4. **Generate session-summary** entry listing consolidated concepts
5. **Write back** deduplicated store + summary

## Example Flow

```
Today's entries:
- [2026-03-04 09:15] pattern (concepts: [testing, ci])
- [2026-03-04 09:16] pattern (concepts: [testing, ci])      ← duplicate, dedup
- [2026-03-04 14:30] decision (concepts: [schema])
- [2026-03-04 16:45] convention (concepts: [schema, bash])

Consolidated:
✓ Merged 2 similar testing patterns (rev 1→2)
✓ Created session-summary: "Session 2026-03-04: 3 insights (testing, ci, schema, bash)"
→ Final store: 2 pattern + 1 decision + 1 convention + 1 summary = 5 entries
```

## Output

- **Consolidation report:** what was merged
- **Summary entry:** new session-summary saved to store
- **Changes:** count of entries removed

Use case: Run at end of day to keep memory lean, prevent drift.

## Backend determinista (SE-317)

Además del flujo LLM descrito arriba, existe el pase de reflexión determinista:

```
scripts/memory-consolidate.sh scan|link|distill|prune [--store <file>] [--apply]
```

- `scan` — duplicados y near-duplicates (fingerprint + difflib),
- `link` — aristas tipadas `derived-from` propuestas (cita de hash/título),
- `distill` — episodios agrupados en insights con citas (fuentes `absorbed`),
- `prune` — candidatos a eliminar (`--dry-run` por defecto; nunca borra solo).

Todo candidato va a `output/memory-consolidation/{fecha}-{accion}.jsonl` para
revisión humana. Ref: SE-317 (`docs/propuestas/SE-317-memoria-reflexiva.md`).
