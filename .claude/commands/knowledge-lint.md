---
name: knowledge-lint
description: Health check for the persistent knowledge base — detect orphans, stale refs, missing evidence
argument-hint: "[--fix]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /knowledge-lint — Knowledge base health check (LLM Wiki pattern)

**Argumentos:** `$ARGUMENTS` (optional: --fix for auto-repair)

Inspired by Karpathy's LLM Wiki gist. Runs 6 checks on the persistent
memory store to detect degradation before it compounds.

## Ejecucion

```bash
bash scripts/knowledge-lint.sh ${ARGUMENTS:-}
```

Show full output. If errors found, suggest specific fixes.

## 6 Checks

1. **Orphan index entries** — MEMORY.md references files that dont exist
2. **Unlisted memories** — .md files in memory/ not in MEMORY.md
3. **Missing evidence_type** — memories without sourced/analyzed/inferred/gap classification
4. **Oversized index** — MEMORY.md approaching 200-line truncation limit
5. **Stale project memories** — project-type memories older than 90 days
6. **Duplicate descriptions** — identical hook lines in MEMORY.md

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /knowledge-lint — Completado
  Status: {HEALTHY|NEEDS ATTENTION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
