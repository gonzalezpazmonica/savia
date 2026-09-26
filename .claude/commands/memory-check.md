---
name: memory-check
description: >
  Health check de las capas de memoria de Savia. Verifica auto-memory,
  memory-store, vectorial, SQLite cache, knowledge graph, agent memory,
  personal vault, session-hot e instincts.
allowed-tools: [Bash]
model_tier: fast
context_cost: low
tier: core
---

# /memory-check — Savia Memory Health Check

Savia tiene 10 capas de memoria que coexisten. Este comando verifica que todas están sanas y detecta drift, huérfanos y caps excedidos.

## Uso

`/memory-check` — sin argumentos. Ejecuta todos los checks.

## Capas verificadas

1. Auto-memory (MEMORY.md + topic files) — existe, cap 200 líneas / 25KB, huérfanos
2. memory-store JSONL — script ejecutable, stats
3. Vector memory — sentence-transformers + faiss-cpu, índice
4. SQLite memory-cache.db — existe, número de entradas
5. Knowledge graph — entities + relations
6. Agent memory — public / private / project (3 niveles)
7. Personal Vault — inicializado o no
8. session-hot.md (pre-compact) — existe, TTL 24h
9. Instincts registry — registry.json + entradas
10. memory-stack-load.sh — ejecutable

## Ejecución

Invoca `bash scripts/memory-check.sh`.

Exit codes: `0` = OK o warnings · `1` = FAILs críticos (caps excedidos, ficheros core missing).

## Remedios comunes

| Hallazgo | Remedio |
|---|---|
| MEMORY.md > 200 líneas | `/memory-compress` para consolidar |
| Huérfanos topic files | Añadir al índice o archivar |
| Vector deps ausentes | `bash scripts/install-memory-deps.sh` |
| Knowledge graph vacío | `bash scripts/knowledge-graph.sh rebuild` |
| private-agent-memory missing | Crear directorio (gitignored) |
| session-hot.md stale | Normal sin pre-compact reciente |

## Cuándo ejecutar

- Inicio de sesión larga
- Tras `/compact` o `/clear`
- Antes de `/backup`
- Si Savia no recuerda algo que debería
- Proactivamente una vez por semana
