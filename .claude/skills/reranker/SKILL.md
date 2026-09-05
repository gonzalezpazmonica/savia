---
layer: peripheral
name: reranker
description: Usar cuando se recibe un top-K ruidoso de búsqueda en memoria y se necesita reordenar por relevancia.
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: memory
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: medium
  savia.summary: Capa de reranking cross-encoder sobre top-K de retrieval (cosine). Filtra ruido antes de que el agente gaste tokens leyendo falsos positivos. Fallback automatico si sentence-transformers ausente.
  savia.tags: "reranking, retrieval, memory, cross-encoder, tokens"
  savia.user-invocable: True
---

# Skill: Reranker

> Filtra ruido entre embedding retrieval y agent consumption.
> Ref: SE-032, docs/propuestas/SE-032-reranker-layer.md.

## Cuando usar

- Despues de `memory-recall`, `savia-recall`, `cross-project-search` con top-K grande
- Cuando el agente ha reportado leer multiples resultados antes de encontrar el relevante
- Para evaluar calidad de retrieval actual (JSON `relevance` scores exponen el ruido)

## Cuando NO usar

- Hot-path sensible a latencia (<500ms) — el cross-encoder CPU tarda 1.5-2.5s para 50 pairs
- Retrieval de <5 candidatos (no hay ruido que filtrar)
- Sin sentence-transformers instalado y sin cosine scores en input (fallback identity)

## Invocacion

```bash
# Pipe JSON con query + candidates
echo '{"query":"Q","candidates":[{"id":"a","text":"...","cosine":0.85}]}' \
  | python3 scripts/rerank.py --top-k 5 --json
```

## Input

```json
{
  "query": "natural language question",
  "candidates": [
    {"id": "str", "text": "str", "cosine": 0.85}
  ]
}
```

## Output

```json
{
  "query": "...",
  "reranked": [
    {"id":"a", "text":"...", "cosine":0.85, "relevance":0.92, "rank":1}
  ],
  "backend": "cross-encoder|fallback-cosine|fallback-identity",
  "model": "BAAI/bge-reranker-base|null",
  "latency_ms": 1800
}
```

## Backends

| Backend | Activo cuando | Latencia |
|---|---|---|
| `cross-encoder` | `sentence-transformers` instalado | ~30-50 ms/par |
| `fallback-cosine` | No transformers, pero `cosine` presente | <10 ms |
| `fallback-identity` | No transformers, no cosine | <5 ms |

## Instalacion (opt-in)

```bash
pip install sentence-transformers
# Primera invocacion descarga ~560MB (BAAI/bge-reranker-base)
```

Zero-install default: script funciona con fallback sin instalar nada.

## Integracion con skills de memoria

```bash
# memory-recall devuelve top-50
bash scripts/memory-recall.sh --json "como funciona hook X" | \
  python3 scripts/rerank.py --top-k 5

# savia-recall mismo patron
bash scripts/savia-recall.sh --json --limit 50 "..." | \
  python3 scripts/rerank.py --top-k 10
```

## Threshold interpretation

- `relevance >= 0.7`: alta confianza, el agente deberia leerlo
- `0.4-0.7`: relevancia media, util como contexto
- `< 0.4`: posible ruido, preferible descartar

## Costes

- Model download (una vez): ~560MB (BAAI/bge-reranker-base)
- RAM en uso: ~800MB
- Inference: CPU only, ~30-50ms/par

## Referencias

- Spec: `docs/propuestas/SE-032-reranker-layer.md`
- Script: `scripts/rerank.py`
- Probe: `scripts/reranker-probe.sh`
- Tests: `tests/test-rerank.bats`
