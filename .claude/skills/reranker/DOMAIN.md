# Domain: Reranker

> Filter noise between embedding retrieval and agent consumption.
> Spec: SE-032 — `docs/propuestas/SE-032-reranker-layer.md`

## Problema

Embeddings cosine similarity devuelve top-K ruidoso:
- Query corta vs doc largo produce embeddings asimétricos
- Sinónimos y parafraseos confunden al modelo de embedding
- No mide intención ni contexto de uso
- ~15-30% de tokens de recall se gastan leyendo falsos positivos

Proyección: 100 turnos/día × 500 tokens/turno en filtrado = 1.5M tokens/mes de ruido.

## Solución

Capa cross-encoder interpuesta entre retrieval y consumption:

```
query + embedding → top-50 cosine → CROSS-ENCODER → top-5 relevantes → agente
```

Cross-encoder: modelo pequeño (~560MB) que evalúa cada par `(query, candidate)` con scoring [0,1] de relevancia real.

## Metric

- **Precision@5**: fracción de top-5 humanamente validados como relevantes
- Baseline actual: 40-60% (cosine only)
- Objetivo SE-032: >= 80%

## Arquitectura

| Componente | Responsabilidad |
|---|---|
| `scripts/rerank.py` | Wrapper stdin→stdout, handles ImportError gracefully |
| `BAAI/bge-reranker-base` | Cross-encoder model (HF, Apache 2.0) |
| `sentence-transformers` | Python lib para cross-encoder API |
| `reranker-probe.sh` | Viability check pre-instalación |

## Integracion downstream

| Consumer | Caso | Top-K |
|---|---|---|
| memory-recall | Busqueda en engrams recientes | 50 → 5 |
| savia-recall | Busqueda historica profunda | 100 → 10 |
| cross-project-search | Busqueda cross-repo | 50 → 5 |
| knowledge-graph query | Retrieval de nodos relacionados | 50 → 10 |

Estado: planificada (Slice 4). Ningun consumer emite hoy el JSON de entrada de
`rerank.py`; hay que construirlo (ver SKILL.md, Integracion).

## Tradeoffs

**Pros**:
- Filtra ruido cuantitativamente
- Zero-install default (fallback identity/cosine)
- Zero egress una vez modelo descargado (`HF_HUB_OFFLINE=1` lo garantiza)
- Score 0-1 expone calidad de retrieval (observability)

**Contras**:
- Latencia 1.5-2.5s en top-50 CPU (no hot-path)
- Model +560MB en disco
- RAM +800MB en uso activo
- Primera invocación descarga el modelo

## No reemplaza

- Embedding store (sigue siendo retrieval base)
- Knowledge graph structure
- Query expansion (otra capa ortogonal)
- Citation tracking

## Roadmap futuro

- Slice 2 (done): wrapper Python + skill
- Slice 3 (post-adoption): benchmark empírico sobre 20 queries de referencia
- Slice 4: integración automática en memory-recall si threshold consistente
- Slice 5: cache de scores por (query_hash, candidate_hash) para reuso
