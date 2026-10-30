---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SE-410, SE-413, SE-481, SE-482, SE-485, SE-331]
origin: investigación externa «Recuperación adaptativa, cuantización de embeddings e inferencia especulativa» (2026-10-30), contrastada por Savia con main c783d6bcf
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-489 — Vaults: banco de evidencias y rutas baratas antes que navegación

## Qué decide esta spec

La investigación propone tres líneas:
- navegación documental por árbol, al estilo PageIndex;
- cuantización binaria/int8 de embeddings;
- inferencia especulativa (DFlash, Weaver, Uzu).

Contrastada con main (c783d6bcf), solo la primera tiene recorrido en Savia, y no empieza por construir un árbol: empieza por **medir dónde falla hoy la recuperación** y por las rutas baratas que la propia investigación pide comparar primero.

| Línea | Verificación en main | Decisión |
|---|---|---|
| Árbol documental y navegación | No existe; `chunker.ts` conserva la ruta de encabezados, pero no hay nodos persistentes | **Condicionada** a lo que diga el banco (R4) |
| Reranker | La skill lo describe como planificado; **ninguna referencia en `projects/savia-vaults/src`** | Medir como ruta M2 (R3) |
| Grafo de vínculos en la recuperación | `vault-graph` y los wikilinks existen; **`src/rag` no los usa** | Medir como ruta M5 solo si el banco lo pide |
| `maxChunksPerDoc` | Fijo en **2** (`types.ts`): puede cortar cadenas cláusula → anexo | Ampliación acotada por documento como ruta M1 (R3) |
| Cuantización binaria/int8 | Vectores: ~90 MB en disco y ~66 MB en RAM entre todas las cúpulas | **No adoptar ahora.** Revisar solo con presión medida (R5) |
| Inferencia especulativa | La inferencia de Savia corre en la nube (Claude); en local solo hay embeddings | **No adoptar.** Fuera de alcance mientras no haya inferencia local de generación |

## Requisitos

### R1 — Banco estratificado con verdad a nivel de evidencia

El banco actual de 36 consultas se conserva íntegro como regresión. Se añade un banco estratificado en `projects/savia-vaults/eval/evidence-bench/`, con seis categorías (≥ 30 consultas cada una en la primera versión; objetivo 50):

| Categoría | Contenido |
|---|---|
| A | Identificadores exactos y negaciones |
| B | Paráfrasis |
| C | Estructura y anexos |
| D | Versiones y tiempo (`as_of`) |
| E | Multidocumento |
| F | Seguridad, abstención y contradicción |

Cada caso declara:
- `required_evidence` (documento, revisión, localizador);
- `forbidden_evidence`;
- `must_abstain`;
- `max_unauthorized_reads: 0`.

Reglas del banco:
- Consultas sobre `savia-docs` y corpus sintético.
- **Ningún contenido privado** de Labs ni de cúpulas N3+ en el repo.
- División `dev`/`test` fija, y un subconjunto oculto fuera del repo.
- El banco no se genera a partir del grafo existente, para no sesgarlo a su favor.

### R2 — Runner con métricas de evidencia

Se reutiliza el runner de `rag eval` (SE-410/SE-331) y se amplía con:
- `EvidenceRecall` (todas las unidades obligatorias);
- `exact-identifier-hit`;
- lecturas no autorizadas (objetivo 0);
- uso de revisiones prohibidas;
- abstención correcta.

Resultados por categoría, con comparación pareada por pregunta e IC 95 % por bootstrap. Latencia p50/p95 y RSS por ruta.

### R3 — Rutas baratas como ablaciones (sin LLM en la ruta)

| Ruta | Configuración |
|---|---|
| M0 | Híbrido actual (baseline) |
| M1 | M0 + ampliación acotada al bloque padre/vecinos del mismo documento, con presupuesto, en lugar de subir `maxChunksPerDoc` globalmente |
| M2 | M0 + reranker cross-encoder local sobre top-N, si hay un modelo local razonable; si no, se documenta y se omite |
| M3 | M0 + selección determinista de sección por encabezados (la ruta de `chunker.ts`) sin índice nuevo persistente |

Todas son opt-in por parámetro de evaluación. **`vault_rag` no cambia de comportamiento por defecto en esta spec.**

### R4 — Informe de decisión y *failure atlas*

`projects/savia-vaults/docs/audits/<fecha>-evidence-bench.md` recoge:
- resultados M0–M3 por categoría;
- un atlas de fallos (qué consultas falla M0, cuáles recupera cada ruta);
- una recomendación explícita sobre:
  - **árbol documental persistente:** solo si M3 no basta en C y E y el atlas muestra fallos que un árbol resolvería;
  - **grafo en la recuperación:** solo si E falla por saltos entre documentos;
  - **qué ruta pasa a defecto,** con no inferioridad en A y B (margen −1 pp, fijado antes de medir).

El árbol y el router (P1-A y P1-B de la investigación) serán **specs propias** si el informe los justifica. Pueden cerrarse como «no adoptar».

### R5 — Cuantización e inferencia: registro de no adopción

En el informe, una sección corta con las cifras medidas de RSS y disco por cúpula y la condición que reabriría cada línea:
- cuantización: vectores > 1 GB residentes, o p95 de búsqueda densa > 200 ms en una cúpula real;
- inferencia especulativa: Savia adopta generación local para un flujo interactivo.

## Criterios de aceptación

- **AC-1:** banco con ≥ 180 casos (6 × 30) que valida contra su esquema (test), más el banco de 36 intacto.
- **AC-2:** `rag eval` produce métricas de evidencia por categoría e IC 95 %. Un caso negativo (lectura no autorizada) hace fallar el gate.
- **AC-3:** M0–M3 se ejecutan sobre el mismo snapshot. Los resultados son reproducibles con la misma semilla y generación.
- **AC-4:** M1 nunca devuelve fragmentos de otro documento ni de una nota fuera de nivel o en cuarentena (test).
- **AC-5:** sin cambios en la respuesta por defecto de `vault_rag` (test de compatibilidad).
- **AC-6:** el informe de decisión existe, cita las cifras y declara para el árbol, el grafo y la ruta por defecto «adoptar», «spec siguiente» o «no adoptar».

## Fuera de alcance

- Árbol persistente (`StructureIndex`), navegación con LLM, router adaptativo y `EvidenceBundle` (el contrato de evidencia vive en SE-482 F2/F3).
- Cuantización binaria/int8, ANN, Milvus.
- DFlash, Weaver, Uzu y cualquier cambio de proveedor de inferencia.

## Rollback

Todo es opt-in en evaluación: se revierte la PR sin migraciones. El banco y el runner no tocan índices de producción; se ejecutan sobre una `SAVIA_RAG_HOME` temporal.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Runner de evaluación | CLI `savia-vaults rag eval` | la misma CLI |

### Verification protocol

- [ ] Independiente del frontend (CLI y servidor)
- [ ] Sin hooks nuevos

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en la CLI del servidor, independiente del frontend)
