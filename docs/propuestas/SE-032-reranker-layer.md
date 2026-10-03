---
id: SE-032
title: Reranker layer — cross-encoder sobre memory/knowledge-graph/savia-recall
status: IMPLEMENTED
origin: Convergencia independiente Hands-On LLM cap.8 + Dify api/core/rag (research 2026-04-18)
author: Savia
related: knowledge-graph skill, memory-recall skill, cross-project-search command, savia-recall skill, savia-memory store
approved_at: "2026-04-22"
applied_at: "2026-04-22"
batches: [19]
expires: "2026-05-16"   # 2 sprints tras approved; si no se implementa → re-review
---

# SE-032 — Reranker layer para memoria y busqueda semantica

## Purpose

Si NO hacemos esto: cada `memory-recall`, `savia-recall`, `cross-project-search` y consulta al knowledge-graph sigue devolviendo top-K por similitud coseno de embeddings. Ese top-K tiene ruido conocido — los embeddings son asimetricos (query corta vs doc largo), confunden sinonimos con paraphrases, y no miden intencion. Resultado practico: el agente termina leyendo 5-10 fragmentos para encontrar el relevante, gastando tokens que no educan.

Cost of inaction: estimamos ~15-30% de los tokens que el agente consume en exploracion de memoria son "falsos positivos de recall" que tiene que filtrar leyendo. Con 100 turnos/dia × 500 tokens medios gastados en filtrar recall ruidoso = ~50k tokens/dia × 30 dias = **1.5M tokens/mes de ruido**.

Post-mortem reference: este ruido es el mismo patron "sin semaphore" que vimos en Bluesky — N fijo aparenta OK pero N "relevantes reales" < N pedidos. El reranker es el semaphore que filtra antes de llegar al agente.

## Objective

**Unico y medible**: introducir una capa de reranking cross-encoder entre el retrieval por embeddings y el consumo del agente, tal que top-5 post-rerank tenga >= 80% de precision humanamente validada sobre 20 queries de referencia (vs baseline actual estimado 40-60%).

NO es: reescribir embeddings, cambiar store, mover a vector DB externo, o fine-tunear modelo. SOLO: una funcion `rerank(query, top-K) -> top-K'` interpuesta.

## Design

### Arquitectura

```
Hoy:
  query → embedding → top-K cosine → agente lee los K
            (mucho ruido)

Despues:
  query → embedding → top-50 cosine → CROSS-ENCODER rerank → top-5 → agente
                                      (BAAI/bge-reranker-base CPU)
```

Cross-encoder: modelo pequeno (~560 MB) que toma `(query, candidate)` y devuelve relevance score [0,1]. Latencia CPU: ~30-50 ms por par, ~1.5-2.5 s para 50 candidatos. Aceptable para recall (no hot-path).

### Implementacion

`scripts/rerank.py` — wrapper stdin→stdout en Python:

```python
# Input JSON: {"query": str, "candidates": [{"id": str, "text": str, "cosine": float}]}
# Output JSON: {"reranked": [{"id": str, "text": str, "cosine": float, "rerank_score": float}]}
```

Integracion con skills existentes: cada skill que haga recall anade un paso opcional `--rerank`:

```bash
# knowledge-graph query actual:
bash scripts/knowledge-graph-query.sh "retros con patron postmortem" --top 10

# Con reranker:
bash scripts/knowledge-graph-query.sh "retros con patron postmortem" --top 50 --rerank-top 5
```

Flag `--rerank-top N` dispara el script; sin flag, comportamiento actual (backward compatible).

### Modelo elegido

`BAAI/bge-reranker-base` — 278M params, CPU viable, top en MTEB reranking 2024. Alternativa: `BAAI/bge-reranker-v2-m3` (multilingual, nuestra memoria tiene ES+EN). Elegir v2-m3 salvo que v1-base sea suficiente en Feasibility Probe.

### Dependencias nuevas

- `sentence-transformers` (pypi) + `torch` CPU-only. Modelo se descarga on-demand al primer uso, cacheado en `~/.cache/huggingface/`.
- Primer uso: ~500 MB download + warm-up ~10 s.
- Runs offline tras el primer warm-up — zero-egress compatible.

## Slicing

### Slice 1 — Feasibility Probe (OBLIGATORIO, 2h, blocking)

**Entregable**: informe `output/se-032-probe-{date}.md` con:
- 20 queries reales extraidas de `session-actions.jsonl` de las ultimas 2 semanas
- Para cada una: top-10 actual (embeddings cosine) vs top-5 post-rerank manual (etiquetado por Savia)
- Precision@5 baseline vs rerank
- Latencia media CPU
- Decision: continue / pivot (si precision@5 no supera baseline por >=20pp)

Sin probe con precision >=80%, el spec **NO avanza a approved**.

### Slice 2 — `scripts/rerank.py` + tests (1 sprint)

- Script stdin→stdout
- Tests bats >25 (SPEC-055 >=80 auditor score)
- Doc `docs/rules/domain/reranker-protocol.md`
- Integracion opt-in en 1 skill piloto: `memory-recall` (zero-risk, cae al comportamiento actual si el flag no esta)

### Slice 3 — Integracion en resto de recall (1 sprint)

- `knowledge-graph`, `savia-recall`, `cross-project-search`, `entity-recall` anaden `--rerank-top N`
- Metricas en `output/rerank-metrics.jsonl`: query, top-K pre, top-K post, latencia, rerank-diff (cuantos items reordenados)
- Ablation study comparando con/sin reranker sobre queries de slice 1 → informe cerrado

## Acceptance Criteria

- [ ] AC-01 Feasibility Probe emitida con precision@5 >= 80% sobre 20 queries ref
- [ ] AC-02 `scripts/rerank.py` implementado y 25+ bats tests pass (score >=80)
- [ ] AC-03 Un skill (memory-recall) integra `--rerank-top N` opt-in, backward compatible
- [ ] AC-04 `docs/rules/domain/reranker-protocol.md` documenta: cuando usar reranker, coste tokens/latencia, como extender a nuevo skill
- [ ] AC-05 CHANGELOG entries por slice
- [ ] AC-06 Todos los skills de recall integran `--rerank-top N` (slice 3)
- [ ] AC-07 Ablation report comparando recall pre/post

## Agent Assignment

- Slice 1 Feasibility Probe: python-developer + business-analyst (para evaluar relevance manual)
- Slice 2: python-developer + test-engineer
- Slice 3: python-developer

## Feasibility Probe (detalle)

Time-box: 2 horas estrictas. Script aparte (no en este PR).

```bash
# probe.sh pseudocodigo
for query in 20_real_queries.txt:
  top10 = embeddings_search(query, k=10)
  top5_reranked = cross_encoder_rerank(query, top10, k=5)
  # Savia (yo) etiqueta manualmente relevance [0=no, 1=marginal, 2=si]
  precision_baseline = mean(labels[top5_embeddings])
  precision_rerank = mean(labels[top5_reranked])
  write_row(query, p_base, p_rerank, latency_ms)
```

Decision gate: si `mean(precision_rerank - precision_baseline) < 0.20`, **abort spec**. Razon honesta: el coste (560 MB modelo + latencia 1.5-2.5 s + dep torch) solo justifica si el delta es grande.

## Riesgos

| Riesgo | Prob | Impacto | Mitigacion |
|---|---|---|---|
| Feasibility Probe devuelve precision_rerank <= precision_baseline | Baja | Alto (spec abort) | Probe ANTES de commit — si falla, documentamos y cerramos el spec con lesson learned |
| torch CPU en Docker CI de GitHub Actions lento (>5min por test suite) | Media | Medio | Test suite usa mock del reranker; solo el probe usa el real. CI green sin torch |
| Modelo bge-reranker-base no funciona en ES | Media | Alto | Alternativa v2-m3 multilingual probada en probe |
| Descarga on-demand de 560 MB bloquea primer uso >30s | Alta | Bajo | Cacheado en HOME/.cache, primer uso one-time. Documentado |
| Opt-in no se adopta y seguimos con ruido | Media | Medio | Slice 3 lo integra en TODOS los recall skills, no solo 1 |

## Metricas exito

- Precision@5 >= 80% en las 20 queries ref (baseline ~40-60%)
- Token saving medible: >=15% reduccion en tokens gastados en filtrar recall (medido en session-actions.jsonl antes/despues, sobre 7 dias)
- Latencia <=3s para rerank top-50
- Cero regresiones en tests existentes (backward compatible)

## Aplicacion de principios Spec Ops (McRaven)

Este spec esta escrito aplicando las lecciones del research Spec Ops (2026-04-18):

- **Simplicity**: un unico objetivo medible (precision@5 >= 80%). Si el Objective necesita "y", refactorizar.
- **Purpose separado de Objective**: la seccion `Purpose` responde "si NO hacemos esto, ¿que se rompe?" con numero concreto (1.5M tokens/mes de ruido). No descripcion del que.
- **Repetition/Feasibility Probe OBLIGATORIO**: 2h time-boxed, gate blocking. Sin probe verde, no hay approved. Elimina specs zombie.
- **Speed/Slicing**: 3 slices de 1 sprint cada uno. Un spec que tarda >1 sprint en empezar es vulnerable.
- **Theory of Relative Superiority**: campo `expires: 2026-05-16` (2 sprints tras approved). Si no se implementa para esa fecha, re-review automatico. Ningun spec vive "approved" indefinidamente.

## Calibracion 2026-10-03 (SE-376)

Contraste con el codigo real (`tests/test-reranker.bats`). Divergencias que siguen abiertas:

- El campo de salida es `relevance`, no `rerank_score`; en los fallbacks vale `null`.
- La integracion piloto de Slice 2 (`--rerank-top` en memory-recall) no existe, ni `docs/rules/domain/reranker-protocol.md`. Ningun script de recall emite el JSON de entrada; el `status: IMPLEMENTED` cubre solo el wrapper y la skill.
- El modelo por defecto es `BAAI/bge-reranker-base`, no v2-m3.
- La escala [0,1] y la latencia por par no se han medido: la calibracion usa un cross-encoder stub.

## Referencias

- Hands-On Large Language Models cap. 8 (Alammar & Grootendorst, O'Reilly 2024) — Semantic Search + Reranking
- Dify api/core/rag — implementacion production de hybrid + reranker (https://github.com/langgenius/dify/tree/main/api/core/rag)
- MTEB leaderboard: https://huggingface.co/spaces/mteb/leaderboard
- BAAI/bge-reranker-v2-m3: https://huggingface.co/BAAI/bge-reranker-v2-m3
- Research interno: `output/research-coderlm-20260418.md` (antecedente del patron query-tipada — mismo espiritu)
- Spec Ops (McRaven 1995) — ver principios aplicados en seccion anterior
