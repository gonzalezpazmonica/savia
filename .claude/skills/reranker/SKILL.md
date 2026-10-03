---
layer: peripheral
name: reranker
description: Usar cuando se recibe un top-K ruidoso de búsqueda en memoria y se necesita reordenar por relevancia.
allowed-tools: [Read, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: beta
  savia.category: memory
  savia.context: fork
  savia.disable-model-invocation: false
  savia.priority: medium
  savia.summary: Capa de reranking cross-encoder sobre top-K de retrieval (cosine). Filtra ruido antes de que el agente gaste tokens leyendo falsos positivos. Fallback automatico si sentence-transformers ausente.
  savia.tags: "reranking, retrieval, memory, cross-encoder, tokens"
  savia.user-invocable: True
---

# Skill: Reranker

> Filtra ruido entre embedding retrieval y agent consumption.
> Ref: SE-032, docs/propuestas/SE-032-reranker-layer.md.

## Cuando usar

- Sobre un top-K grande de cualquier busqueda, convertido al JSON de entrada (ver Integracion)
- Cuando el agente ha reportado leer multiples resultados antes de encontrar el relevante
- Para evaluar calidad de retrieval actual (los `relevance` del cross-encoder exponen el ruido)

## Cuando NO usar

- Hot-path sensible a latencia (<500ms) — el cross-encoder CPU tarda 1.5-2.5s para 50 pairs
- Retrieval de <5 candidatos (no hay ruido que filtrar)
- Sin sentence-transformers instalado y sin cosine scores en input (fallback identity: no reordena nada)

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
  "backend": "cross-encoder|fallback-cosine|fallback-identity|empty-input",
  "model": "BAAI/bge-reranker-base|null",
  "latency_ms": 1800
}
```

`relevance` solo tiene valor con `backend: cross-encoder`. En los fallbacks es
`null`: no hay score de relevancia y los umbrales de abajo no aplican. Mira
siempre `backend` antes de fiarte del orden.

## Exit codes y errores

| Codigo | Causa |
|---|---|
| 0 | OK, incluido cualquier fallback (lista vacia -> `empty-input`) |
| 1 | JSON invalido, stdin no UTF-8, raiz no objeto, `query` vacia o no string, candidato sin `id`/`text`, `text` no string, `cosine` no numerico finito |
| 2 | Uso: `--top-k` < 1 o no entero, flag desconocido |

Los errores salen por stderr con prefijo `ERROR:`, sin traceback.

## Backends

| Backend | Activo cuando | Latencia |
|---|---|---|
| `cross-encoder` | `sentence-transformers` instalado y el modelo carga | ~30-50 ms/par (no medido en la calibracion) |
| `fallback-cosine` | Sin cross-encoder y `cosine` en TODOS los candidatos | <10 ms |
| `fallback-identity` | Sin cross-encoder y algun candidato sin `cosine` | <5 ms |

Si el cross-encoder esta instalado pero falla (modelo no descargable, torch
ausente, error de prediccion), el script avisa por stderr
(`rerank: cross-encoder failed (...)`) y cae al fallback; `backend` lo refleja.
Los empates conservan el orden de entrada. `--top-k` mayor que n devuelve n.

## Instalacion (opt-in)

```bash
pip install sentence-transformers
# Primera invocacion descarga ~560MB (BAAI/bge-reranker-base)
```

Zero-install default: script funciona con fallback sin instalar nada.
Con el cross-encoder instalado, la primera ejecucion descarga el modelo del HF
Hub (egress). `HF_HUB_OFFLINE=1` lo impide y fuerza el fallback.

## Integracion con skills de memoria

Ningun script de memoria emite hoy el esquema de entrada: no existen
`memory-recall.sh` ni `savia-recall.sh` con `--json` compatible. El consumidor
construye el JSON y lo pasa por stdin:

```bash
jq -n --arg q "como funciona hook X" --slurpfile c resultados.json \
  '{query:$q, candidates:$c[0]}' | python3 scripts/rerank.py --top-k 5
```

La integracion automatica con memory-recall es el Slice 4 de SE-032 (pendiente).

## Threshold interpretation

Solo con `backend: cross-encoder` (escala de bge-reranker-base con sigmoide;
no verificada en la calibracion, que usa un modelo stub):

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
- Tests: `tests/test-rerank.bats`, `tests/test-reranker.bats`, `tests/test-reranker-probe.bats`
