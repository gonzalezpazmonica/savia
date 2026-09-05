---
layer: peripheral
name: topic-cluster
description: "Usar cuando se agrupan retros, PBIs o incidentes en topics para detectar patrones transversales."
allowed-tools: [Read, Bash, Glob]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: memory
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: medium
  savia.summary: "Clustering tematico con BERTopic (UMAP+HDBSCAN+c-TF-IDF). Aplica sobre retros, backlogs, incidentes, lessons. Fallback keyword cuando bertopic no esta instalado. Output JSON con labels y keywords."
  savia.tags: "clustering, bertopic, retrospectives, patterns, memory"
  savia.user-invocable: True
---

# Skill: Topic Cluster

> Descubre patrones que cruzan retros, PBIs, incidents, lessons.
> Ref: SE-033, docs/propuestas/SE-033-topic-cluster-skill.md.

## Cuando usar

- Al cierre de sprint: agrupar retros de N proyectos para detectar temas compartidos
- Auditoria periodica de backlog/incidents: detectar duplicados semanticos
- Post-lesson-extract: agrupar lessons cross-project
- Cuando `retro-patterns`, `backlog-patterns`, `lesson-extract` pierden senal

## Cuando NO usar

- Menos de 6 documentos (HDBSCAN no encuentra clusters utiles)
- Documentos muy cortos (<20 palabras) — embeddings poco senal
- Hot-path <500ms — BERTopic tarda 10-30s en ~100 docs

## Invocacion

```bash
# Input via stdin
cat retros.json | python3 scripts/topic-cluster.py --min-cluster-size 3

# Con JSON pretty
cat pbis.json | python3 scripts/topic-cluster.py --json
```

## Input schema

```json
{
  "documents": [
    {"id": "retro-2026-q1-alpha", "text": "Sprint planning took 3x expected time..."}
  ],
  "min_cluster_size": 3,
  "nr_topics": null
}
```

## Output

```json
{
  "topics": [
    {
      "id": 0,
      "label": "sprint planning time",
      "keywords": ["sprint", "planning", "time", "overrun"],
      "size": 7,
      "documents": ["retro-1", "retro-3", "retro-5"]
    }
  ],
  "outliers": ["retro-8"],
  "backend": "bertopic|fallback-keyword",
  "model_info": {"sbert": "all-MiniLM-L6-v2", "docs": 15, "clusters": 3},
  "latency_ms": 12000
}
```

## Backends

| Backend | Cuando | Latencia | Calidad |
|---|---|---|---|
| `bertopic` | bertopic+sentence-transformers instalados | 10-30s / 100 docs | Alta — semantic clusters |
| `fallback-keyword` | Sin deps ML | <1s / 100 docs | Media — surface keywords |

## Instalacion (opt-in)

```bash
pip install bertopic sentence-transformers
# Primera invocacion descarga all-MiniLM-L6-v2 (~80MB)
```

Zero-install default: script funciona con fallback keyword sin instalar nada.

## Casos de uso

### Sprint retro cluster

```bash
bash scripts/collect-retros.sh --sprint 42 --json | \
  python3 scripts/topic-cluster.py --min-cluster-size 3
```

### Backlog pattern detection

```bash
bash scripts/backlog-dump.sh --project alpha --json | \
  python3 scripts/topic-cluster.py --nr-topics auto
```

### Cross-project lessons

```bash
find output/lessons -name "*.json" -exec cat {} \; | \
  jq -s '{documents: .}' | \
  python3 scripts/topic-cluster.py --min-cluster-size 2
```

## Interpretacion

- `clusters >= 3`: patron claro, revisar labels
- `outliers / total > 30%`: corpus heterogeneo, subir `min_cluster_size` o bajar `nr_topics`
- `size` pequeno (2-3): puede ser noise o patron emergente

## Costes

- Sin deps: 0 MB, <1s
- Con BERTopic: ~200MB sbert + deps, ~800MB RAM
- Egress: solo en primera invocacion (download modelo)

## Referencias

- Spec: `docs/propuestas/SE-033-topic-cluster-skill.md`
- Script: `scripts/topic-cluster.py`
- Probe: `scripts/bertopic-probe.sh`
- Tests: `tests/test-topic-cluster.bats`
