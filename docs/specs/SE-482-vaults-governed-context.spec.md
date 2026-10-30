---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-10-30
author: Savia
phase: D
risk: L3
related_specs: [SE-309, SE-410, SE-413, SE-417, SE-419, SE-420, SE-424, SE-480, SE-481]
origin: propuesta externa «Savia Vaults — del RAG híbrido al contexto gobernado» v0.1 (2026-10-30); análisis de Savia contra HEAD 7b434f9ae
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-482 — Vaults: del RAG híbrido al contexto gobernado (paraguas)

## Qué es

Spec paraguas que ordena el resto de la propuesta, una vez fuera el primer corte P0 (SE-481). No autoriza ninguna implementación. Cada fase se convierte en su propia spec cuando la anterior aporte datos.

Principio que se conserva de la propuesta:

- recuperar no es verdad;
- citar no es autorizar;
- **capacidad ≠ autoridad**.

Vaults aporta evidencia; AEK decide autoridad y efectos; Savia orquesta.

## Verificación AS-IS (HEAD 7b434f9ae)

| Hallazgo | Veredicto | Evidencia | Destino |
|---|---|---|---|
| H1 metadatos malformados | **CONFIRMADO** | `chunker.ts::parseNote` captura el error del YAML; `exceedsDomeLevel` ignora niveles desconocidos | SE-481 |
| H2 negaciones como stopwords | **CONFIRMADO** | `retriever.ts`: `no`, `not`, `ni`, `sin`, `nada` en STOPWORDS | SE-481 |
| H3 procedencia/conflictos fuera del camino RAG | **CONFIRMADO** | `ProvenanceEngine` y `detectConflicts` solo aparecen en `src/knowledge/` y en la CLI, no en `src/rag/` | F2 |
| H4 primera promoción sin baseline | **CONFIRMADO** | `policy.ts::promotionDecision`: `!hasActive → promote` | F5 (perfil por criticidad) |
| H5 `PARTIAL` indexado | **CONFIRMADO** | `files/rag-source.ts`: `INDEXABLE = {READY, PARTIAL}` | F1 |
| H6 revocación temporal | **PARCIAL** | ACL de Savia Files al consultar, sí. El nivel por nota en RAG no se revalida al servir; lo cierra SE-481 R3. Bundles: no existen | SE-481 + F3 |
| H7 evals de extremo a extremo | **CONFIRMADO** | Solo recall/MRR de rutas | F4 |
| H8 búsqueda vectorial exacta | **CONFIRMADO, no es defecto** | `FlatVectorStore.topK` | F6, solo con medición |
| Extra: registro de cúpulas sin recarga | **CONFIRMADO** (incidente 2026-10-21→30) | El MCP leía `enabled:false` tras reactivar | SE-480 |

Hay una auditoría detallada en curso (SVTC-00), con reproducción de cada caso y baseline reproducible. Si contradice esta tabla, la tabla se corrige.

## Fases (cada una se convierte en una spec propia al llegar su turno)

| Fase | Contenido mínimo | Riesgo | Depende de |
|---|---|---|---|
| F1 Admisión y extracción | Estado de admisión separado del estado técnico. `PARTIAL` visible hasta la respuesta. Nunca `ACCEPTED` automático. Reutilizar los campos existentes (`status`, `valid_until`, `superseded_by`) antes de añadir campos | L2-L3 | SE-481 |
| F2 Evidencia y conflictos | `EvidenceRef` (cúpula, documento, revisión, localizador, hash del fragmento). Conectar `ProvenanceEngine` y `detectConflicts` en modo informativo. Conflicto determinista → `CONFLICT`, sin resolverlo por score | L2-L3 | F1 |
| F3 ContextBundle | `vault_context_prepare` opt-in, sin LLM obligatorio. Ligado al principal autenticado, al propósito, con caducidad y revalidación. **Nunca** contiene autoridad | L3 | F2 |
| F4 Evals de respuesta | Polaridad, excepciones, fidelidad de cita, abstención y conflictos. Subconjunto determinista en CI | L2 | crece con cada fase |
| F5 Perfil por criticidad | Gate de primera promoción y perfil `governed`, decididos por política externa y no por el agente | L3 | F4 |
| F6 Recuperación | Reranker, expansión al párrafo vecino y ANN, solo con ablation medida | L2 | F4 |
| F7 Adaptador AEK | Traducción ContextBundle → AEK sin conceder permisos | L4 potencial | F3, F4 y AEK operativo |

## Qué NO hacer

- No crear un `truth-engine`, un `authority-engine` ni un segundo grafo: reutilizar `src/knowledge/`.
- No poner un LLM en el camino de cada consulta.
- No sustituir `FlatVectorStore` sin un corpus real que lo justifique.
- No añadir `authority` a `RagHit` ni a ningún objeto de Vaults.
- No etiquetar en masa el contenido existente como `ACCEPTED`. El contenido sin admisión es `UNREVIEWED`.
- No publicar en el repo corpus con contratos o documentos reales. Los fixtures son sintéticos.

## Preguntas abiertas para la operadora (antes de F1)

1. ¿Quién puede admitir conocimiento (`ACCEPTED`) en cada cúpula, y cómo se separa ese permiso del de escritura?
2. ¿Qué cúpulas se tratarán como críticas (perfil `governed`)?
3. ¿Qué parte de AEK es real hoy y dónde estaría el punto de integración?

## Respuestas de la operadora (2026-10-30)

1. **Admisión:** es un **permiso nuevo, «admitir»**, distinto de «escribir». Por defecto solo lo tiene la propietaria de la cúpula. **Ningún agente lo tiene nunca.**
2. **Cúpulas críticas:** **ninguna por defecto**. El perfil `governed` se activa por cúpula, en su configuración.
3. AEK: sigue sin respuesta. F1 no depende de AEK.

Con las respuestas 1 y 2, F1 se concreta en **SE-486** (PROPOSED).
