---
status: APPROVED
priority: P1
developer_type: agent-team
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SE-410, SE-413, SE-481, SE-482, SE-485, SE-331]
origin: investigación externa «Recuperación adaptativa, cuantización de embeddings e inferencia especulativa» (2026-10-30), contrastada por Savia con main c783d6bcf. Aprobada por la operadora en el chat (2026-10-30), con el alcance «construir, probar empíricamente y sacar datos reales contrastados», no solo medir.
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-489 — Vaults: recuperación adaptativa construida y medida (estructura, grafo, reranker, router y cuantización)

## Qué decide esta spec

Se **construyen** las rutas de recuperación que propone la investigación y se comparan **empíricamente** sobre un banco con verdad a nivel de evidencia.

- Todas las rutas son opt-in, por parámetro de `vault_rag` y de `rag eval`.
- `vault_rag` no cambia su comportamiento por defecto hasta que una ruta gane con datos y la operadora lo apruebe en su PR de promoción.

Punto de partida verificado en main (c783d6bcf):
- **Reranker:** no hay ninguno en `projects/savia-vaults/src`.
- **Grafo de vínculos:** existe (`vault-graph`, wikilinks), pero `src/rag` no lo usa.
- **Límite por documento:** `maxChunksPerDoc` vale 2.
- **Índice denso:** vectores de ~90 MB en disco y ~66 MB en RAM, sin ninguna estructura persistente de secciones.

## Arquitectura: rutas intercambiables sobre un contrato común

`src/retrieval/` (nuevo):
- `route.ts` define la interfaz `RetrievalRoute`: entrada con la consulta, las cúpulas autorizadas, `asOf` y el presupuesto; salida con hits, la traza y el presupuesto consumido.
- Cada ruta vive en su propio módulo.
- La autorización (nivel de cúpula y de nota, cuarentena, ACL de Files) se aplica **en el contrato común antes de abrir cada nodo**, no dentro de cada ruta.

Cada ruta reutiliza `RagService` (BM25 + denso + RRF) para los candidatos iniciales.

| Ruta | Qué se construye |
|---|---|
| **M0** | Híbrido actual (baseline, sin cambios). |
| **M1** | Ampliación acotada al padre y a los vecinos del mismo documento, con presupuesto por documento. |
| **M2** | Reranker cross-encoder local sobre top-N. Modelo local por Ollama o ONNX, fijado por digest, sin red. |
| **M3** | `StructureIndex` persistente y determinista: árbol documento → sección → unidad con `nodeId` estable, localizadores y `contentHash`. Se construye en el sync desde `chunker` (Markdown) y desde los localizadores de Savia Files. Proyección derivada de la generación, con el mismo ciclo de vida (sombra/activa/rollback/GC), cifrado y clasificación que la fuente. La navegación es determinista: sección, padre, hermanos. |
| **M4** | Navegación con LLM **local** (Ollama) sobre el `StructureIndex`. Límites de llamadas, nodos y tokens. Solo herramientas de lectura ya autorizadas. El contenido leído es dato, nunca instrucción. |
| **M5** | Grafo de referencias (wikilinks, `supersedes`, `superseded_by`, IDs de spec) en la recuperación: expansión por saltos con `visited`, profundidad máxima y ACL en cada salto. Reutiliza el extractor de vínculos existente, sin grafo nuevo. |
| **M6** | Router determinista y auditable: señales explícitas (IDs exactos, negación, referencias «ver anexo/§», dispersión, confianza) eligen entre M0, M1, M3, M4 y M5 y registran el motivo en la traza. |
| **M7** | Cuantización en sombra: proyección binaria (signo, bitpacking, Hamming con `xor`+`popcount`) e int8, con rescoring en float32. El float32 sigue siendo la fuente de verdad. Proyección ligada por hash a la generación, al modelo y al orden de chunks. Se mide también a escala sintética (10k/100k/1M vectores). |

La inferencia especulativa (DFlash, Weaver, Uzu) queda **fuera**: Savia no genera en local en ningún flujo; la generación va en la nube. Se reabre si se adopta generación local interactiva.

## Banco y evaluación

### R1 — Banco estratificado con verdad a nivel de evidencia

Se conserva el banco de 36 consultas como regresión. Se añade `projects/savia-vaults/eval/evidence-bench/`, con ≥ 50 consultas por categoría:

| Categoría | Contenido |
|---|---|
| A | Identificadores exactos y negaciones |
| B | Paráfrasis |
| C | Estructura y anexos |
| D | Versiones y tiempo (`as_of`) |
| E | Multidocumento |
| F | Seguridad, abstención y contradicción |

Cada caso declara `required_evidence` (documento, revisión, localizador), `forbidden_evidence`, `must_abstain` y `max_unauthorized_reads: 0`.

Origen de los casos:
- **corpus real:** `savia-docs` (público);
- **corpus sintético:** contratos, normas con anexos y revisiones, para la categoría C/D.

Reglas del banco:
- Ningún contenido privado en el repo.
- División `dev`/`test` fija y un subconjunto oculto fuera del repo.
- El banco no se deriva del grafo existente.

### R2 — Runner y métricas

`rag eval --route <M0..M7>` (se amplía el runner de SE-410/SE-331) calcula:
- recuperación: Recall@5/10/20, MRR, nDCG@10, `EvidenceRecall`, `exact-identifier-hit`;
- gobernanza: lecturas no autorizadas, uso de revisiones prohibidas, abstención correcta;
- coste: llamadas a LLM y tokens (M4);
- operación: latencia p50/p95 por fase y RSS pico.

Análisis por categoría, pareado por pregunta, con IC 95 % por bootstrap.

**Dos fases:** recuperación sola, y la misma evidencia entregada a un mismo generador (más la condición *oracle evidence*). Así se separa recuperar de leer.

### R3 — Datos reales y contrastados

Cada cifra del informe lleva la columna «medición propia / afirmación de terceros / hipótesis». Ninguna decisión de promoción se apoya en una cifra que no sea medición propia sobre este banco.

## Criterios de aceptación

- **AC-1:** banco con ≥ 300 casos (6 × 50) que valida contra su esquema, más los 36 intactos.
- **AC-2:** M1–M7 construidas, con tests unitarios y de integración. Cada una pasa la batería negativa de seguridad:
  - una cúpula denegada no revela título, árbol ni existencia;
  - el prompt injection en el contenido no ejecuta nada;
  - los ciclos del grafo terminan;
  - tras borrar o reclasificar, ninguna proyección sirve contenido invalidado.

  Objetivo: **0** violaciones.
- **AC-3:** el `StructureIndex` y la proyección de M7 siguen el ciclo de vida de la generación. Un test de rollback y otro de GC demuestran que no quedan proyecciones obsoletas.
- **AC-4:** `vault_rag` sin `route` responde igual que en main (test de compatibilidad).
- **AC-5:** informe `projects/savia-vaults/docs/audits/<fecha>-se489-resultados.md` con las métricas por ruta y categoría, IC 95 %, atlas de fallos (qué recupera cada ruta que M0 no), coste y latencia, y M7 a 10k/100k/1M.
- **AC-6:** el informe termina con una decisión por ruta («promover a defecto», «opt-in por cohorte» o «descartar»). Reglas: no inferioridad en A/B (−1 pp, fijado antes de medir) y una ganancia en C/D/E con IC que excluya 0.
- **AC-7:** M4 nunca se activa por defecto ni por el router sin que el presupuesto esté declarado en la petición.

## Promoción

Este trabajo no cambia el comportamiento por defecto. Si el informe recomienda promover una ruta (p. ej. M6 por defecto), va en una PR aparte que cita el informe y que la operadora fusiona.

## Rollback

Rutas opt-in: el revert de la PR o el parámetro `route` ausente devuelven el comportamiento de main. El `StructureIndex` y las proyecciones de M7 son derivadas y se regeneran o borran sin tocar la fuente de verdad.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor savia-vaults (MCP `vault_rag` con `route`) | stdio MCP | stdio MCP, mismo binario |
| Runner de evaluación | CLI `savia-vaults rag eval` | la misma CLI |

### Verification protocol

- [ ] Independiente del frontend
- [ ] Sin hooks nuevos

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en el servidor y su CLI, independiente del frontend)
