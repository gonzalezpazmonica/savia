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

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **F6 y parte de F4 pasan a SE-489**, que ya construyó y midió reranker, vecino y banco con abstención y contradicción (M0–M7). Este paraguas deja de listarlas como fases pendientes.
- Quedan aquí F1 (SE-486), F2, F3, F5 y F7.

## Enmienda propuesta 2026-11-25: medir escrituras perdidas antes de añadir control de concurrencia a las notas

> Propuesta. No cambia el estado de esta spec; vale cuando la operadora fusione la PR que la trae.
> Origen: Radar de metaorquestación y factorías (documento de la operadora, 2026-11-25, líneas M01–M15), cruzado con main c7987ac94 por una analista independiente. El inventario completo vive en Savia Labs. Absorbe M04 (memoria transaccional, ramas y fusiones semánticas).

**Lo que hay.** Files ya tiene clave de idempotencia, diario y control optimista de versión de política. Las notas no:
`vault_write` sobrescribe sin revisión base, así que gana la última escritura, y los conflictos semánticos solo avisan.

**Lo que se propone, dentro de F2 y en este orden:**

1. **Medir primero.** Un guion de solo lectura sobre el historial git de cada cúpula en uso que detecte escrituras
   consecutivas sobre la misma nota desde sesiones distintas en poco tiempo, más un test con dos escritores
   concurrentes que muestre si la pérdida es posible hoy.
2. **Solo si hay incidencia real:** un `expectedSha` opcional en `vault_write`, que responde `CONFLICT` cuando la
   nota cambió desde que se leyó. La respuesta `CONFLICT` ya existe en el servidor HTTP.

**Hipótesis refutable.** En las cúpulas en uso hay al menos una sobrescritura en la que el escritor partía de una
revisión que ya no era la vigente.

**Criterio de descarte.** Incidencia real cero: se documenta que gana la última escritura y no se toca nada.

**Fuera.** Ramas por trabajo, fusión de tres vías, CRDT y motores de grafo externos: sin consumidor ni incidencia
medida.
