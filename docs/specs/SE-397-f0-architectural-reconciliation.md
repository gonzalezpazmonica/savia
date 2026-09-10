---
id: SE-397-F0
parent: SE-397
status: APPROVED
created: 2026-09-08
evidence_type: static-reconciliation
head: 0120cfbce9adaa9f4ab9cab1f6efdc4425229908
---

# SE-397 F0 — Architectural Reconciliation

## Estado

`APPROVED_WITH_CONCERNS` por la operadora el 2026-09-09. F0 es inventario y
reconciliación estática. No se ha implementado SAM ni ninguna fase F1–F10.
Las fases siguientes quedan autorizadas, pero conservan sus gates y límites.

| Campo | Valor |
|---|---|
| HEAD inspeccionado | `0120cfbce9adaa9f4ab9cab1f6efdc4425229908` |
| ID | `SE-397`, libre antes de persistir la spec |
| Spec | `docs/specs/SE-397-savia-architectural-self-knowledge.spec.md` |
| Método | búsquedas deterministas, lectura de specs/código y checks locales |
| Limitación | sin evidencia operacional nueva; outputs locales ausentes no son FAIL |

## Reconciliación de specs

| Spec | Estado y activos reutilizables | Clasificación / gap para SAM |
|---|---|---|
| SE-037 | `IMPLEMENTED`; benchmark p50/p95/p99, audit y ratchet de hooks | `EXISTING_BUT_INCOMPLETE`: no mide operación end-to-end. Conflicto: el scanner de `.opencode/hooks` no sigue el symlink y puede acreditar un PASS vacío; falta el SLA citado por AC-05. |
| SE-280 | `PARTIAL`; core Vaults, seguridad, storage/search y servidor evolucionaron después vía SE-286 | `EXISTING_BUT_INCOMPLETE`: Vaults es fuente de conocimiento reutilizable, no modelo SAM ni autoridad arquitectónica. |
| SE-282 | `PARTIAL`; registry, A2A client, búsqueda federada, cache y circuit breaker | `EXISTING_BUT_INCOMPLETE`: federación reutilizable; no prueba aislamiento, provenance ni freshness suficientes para SAM. |
| SE-309 | ID histórico duplicado entre anti-sycophancy y Knowledge Governance | `CONFLICT`: nunca resolver por orden del filesystem. La capa Vaults de decision/provenance/conflicts es reutilizable, pero no sustituye policy ni approval. |
| SE-378 | spec `APPROVED`, planning `IMPLEMENTING`; planning-state + LOG + CLI | `EXISTING_AND_SUFFICIENT` como planning de era reciente; `INCOMPLETE` globalmente. El validator no detecta specs omitidas y aún acredita PASS. |
| SE-388 | `IMPLEMENTING`; probe/risk map/canaries y bridge Codex | `EXISTING_BUT_INCOMPLETE`: vocabulary de adapter/risk/degradation útil; receipts y canaries sobredeclaran evidencia, L3/L4 y MCP siguen parciales. |
| SE-390 | `APPROVED + IMPLEMENTING`; identidad y checker documental | `EXISTING_AND_SUFFICIENT` para Foundation intent; `INCOMPLETE` para drift. El checker PASS no detecta conteos divergentes con critical facts. |
| SE-391 | `IMPLEMENTING`; autonomy policy/doctor/config y tests | `EXISTING_BUT_INCOMPLETE`: techo L2 y fail-safe reutilizables; no operational graduation. Su “canonical policy” debe ser proyección/enforcement, no competir con reglas humanas. |
| SE-393 | `IMPLEMENTING`; contracts/runtime/state/policy/preflight/domain packs | `EXISTING_BUT_INCOMPLETE`: núcleo común reutilizable, pero el servidor no cablea adapters reales y carece de ruta causal completa. |
| SE-394 | `IMPLEMENTING`; validación/CI/manifests/evidence parcial | `CONFLICT`: commits y texto declaran implementación, mientras AC operacionales siguen abiertos; CI verde no equivale a graduación. |
| SE-395 | `PROPOSED`; no existe router adaptativo implementado | `NEW_GAP`: no activar. Reutilizar Vaults federation/knowledge sin confundir señales de usage con authority. |
| SE-396 | `PROPOSED` con I01 y Shield HTTP ya mergeados | `EXISTING_BUT_INCOMPLETE`: prerequisito crítico. H02–H12, adapters reales, recovery, exactly-once externo y aislamiento Vaults siguen abiertos. |

## Activos arquitectónicos existentes

| Área | Autoridad o artefactos | Evaluación F0 |
|---|---|---|
| Capability maps | `.scm/INDEX.scm`, `.scm/registry.json`, `.scm/resources.json`, generador | Fresco y reutilizable como proyección; 1464 recursos. Cero deps/tests poblados y risk solo para 89/1464. |
| Capability contracts | `contracts/capabilities/*.yaml`, `laws/*`, contract/law checks | 12 descriptors y 11 laws verificables; subconjunto, no universo completo. |
| Architecture docs | `docs/ARCHITECTURE.md`, `docs/STRUCTURE.md`, `MAP.md`, SE-390 | Declared intent manual; rutas, comandos y conteos parcialmente stale. |
| Structural maps | `.agent-maps/*.acm`, `.human-maps/*.hcm` | Inputs posibles, pero snapshots raíz de 2026-03 están stale. |
| Data flow | settings/routing TSV, dual-cli, docs de flujo | Fuentes fragmentadas; no existe flow causal sistémico. |
| Context | context-map, context docs y `scripts/context-*` | Reutilizable como declared/context tooling; varios conteos y modelos son legacy. |
| Authority | `CRITERIO.md`, laws, autonomous-safety, risk-tiering, grants, contracts | Debe seguir fuera de SAM. Solo criterio humano activo puede otorgar autoridad. |
| Dependencies | knowledge-graph, impact-analysis, blast-radius, CodeGraph opcional | Motores reutilizables; no cruzan file→flow→authority→evidence. |
| Runtime traces | telemetry schema, OTel, savia-trace, agent trace, dual-cli journal | Primitivas separadas; no hay Operational Trace causal con `architecture_path`. |
| Evidence | receipts, evidence capture, evals, dual-cli observations | Fragmentado; no hay cadena única Claim→Implementation→Test→Graduation. |
| Failure | semantic handlers, failure memory, chaos, typed errors | Parcial. Chaos puede salir 0 con FAIL si existe al menos un PASS; no acredita suite. |
| Diagrams | agent invocation graph, constellation, diagram-generation | Machinery reutilizable; constellation y mapas están stale. |
| Queries | knowledge-graph CLI, graph commands, impact/blast-radius | Parciales. `/architecture show` documentado no existe. |

## Fuentes de verdad

| Dominio | Fuente / regla |
|---|---|
| Identity | SE-390 define producto; README proyecta; perfil Savia define voz; bootstrap define contexto de frontend. No colapsarlas. |
| Policy | `CRITERIO.md`, `docs/rules/domain/*.md` y laws humanas; SAM solo referencia. |
| Authority | human-control, autonomous-safety, approvals/grants y safety descriptors; runtime puede denegar o pedir, no crear criterio. |
| Capabilities | ficheros reales de commands/skills/agents/scripts; `.scm` es proyección derivada. Descriptors son contrato para el subconjunto formalizado. |
| Planning | `docs/propuestas/planning-state.json` + `LOG.md`; roadmaps son vistas/histórico. |
| Evidence | receipts, resultados, baselines, observations y decisiones conservan su autoridad propia; SAM referencia hashes/IDs. |
| Memory | texto local/vaults; SQLite y vectores son caches regenerables. |
| Runtime | código + configuración efectiva por frontend + journal/telemetry observados; settings Claude no gobierna Codex. |

## Gaps consolidados

### Existing and sufficient

- Principios de soberanía y autoridad humana.
- Generación/frescura básica de `.scm` como catálogo de capabilities.
- Planning state para su era reciente y lifecycle append-only.
- Validación de laws y capability contracts formalizados.
- Primitivas locales de trace IDs, receipts y rendering de diagramas.

### Existing but incomplete

- Knowledge graph, dependency/impact tools y mapas estructurales.
- Modelos runtime/authority/evidence de dual-cli y frontends.
- Planning global, lifecycle y freshness.
- Arquitectura/context/data-flow documental.
- Evidence graduation, failure/recovery y observación operacional.

### New gaps

- Schema lógico SAM con provenance y separación declared/discovered/observed.
- Reconciler reproducible, architecture hash/revision y drift report.
- Mapping causal `trace → flow instance → architecture_path`.
- Impact sistémico file/component→flow/authority/evidence/frontend/domain.
- Vistas/queries SAM, graduation/freshness y Fault Matrix/recovery.

### Conflicts

- IDs duplicados históricos (confirmados SE-260 y SE-309).
- Auto-merge de bajo riesgo documentado en una regla frente a human-control.
- Frontend support heurístico de `.scm` frente a symlinks/compatibilidad real.
- Adapter context-KG probado contra schema distinto del knowledge graph real.
- Planning validator y docs checker producen PASS pese a omisiones/drift.
- Claims de canaries, doctors y receipts superiores a la evidencia operacional.

### Obsolete candidates

- `docs/constellation.mermaid`, mapas raíz y secciones stale de arquitectura,
  data-flow/context. Conservar o regenerar; nunca borrar automáticamente.
- Inventarios y versiones hardcodeadas sin freshness.

## Recomendación SAM

| Decisión | Recomendación |
|---|---|
| Grafo reusable | Extender el motor/traversal de knowledge-graph tras corregir fitness/schema; ingerir `.scm`, `.acm`, planning, laws y contracts por referencia. |
| Modelo lógico | Nodos/edges tipados con `source_kind`, `source_path`, digest, revision, commit, validity/freshness; observations en capa separada. |
| Storage | Mantener fuentes actuales. Generar proyección determinista versionada bajo `.scm/` y SQLite local regenerable para queries. Nunca DB autoritativa. |
| Vistas | `foundation`, `capabilities`, `structural`, `runtime`, `authority`, `evidence`, `failure`, más Mermaid scoped, todas GENERATED FROM SAM. |
| No duplicar | `.scm`, planning/LOG, laws, descriptors, receipts/evals, memory, telemetry/journal, diagrams ni impact tools. |

## F1 mínimo aprobado — pendiente de ejecución

**Slice:** schema/proyección mínima read-only con `SYSTEM`, `SUBSYSTEM`,
`COMPONENT`, `CAPABILITY`, `POLICY`, `ADAPTER`, `FRONTEND`, `STORE`, `EVIDENCE`;
solo `CONTAINS`, `IMPLEMENTS`, `USES`, `DEPENDS_ON`, `ENFORCES`, `PRODUCES`,
`REQUIRES_AUTHORITY` y provenance obligatoria.

**Archivos esperados:** una spec delta aprobada tras este F0; schema bajo
`.scm/`; extractor/generador determinista; fixtures y tests; una vista pequeña
generada. No tocar enforcement ni runtime de authority.

**Tests/evidence:** determinismo, schema, provenance, unknown explícito,
declared/discovered separados, no-copy de policy, corrupción fail-safe y diff
de vista. Complejidad estimada: media-alta, 3–5 slices tras decisión humana.

## Validación ejecutada

```text
generate-capability-map.py --check → FRESH, 1464 resources
roadmap.sh validate               → PASS (con limitación de omisiones)
law-check.sh                      → PASS, 11 laws
contract-check.sh                 → PASS, 12 descriptors
dual-cli unittest                 → 70 OK; 10 NOT_VERIFIED por EPERM Unix socket
```

La ausencia de CodeGraph, DB knowledge graph o telemetry local se registra como
`NOT_AVAILABLE`, no PASS. No se ejecutaron pruebas de producción ni efectos
externos.

## Decisiones humanas requeridas

Decisiones resueltas por aprobación operadora de 2026-09-09:

1. F0 aceptado con sus concerns explícitos.
2. Proyección versionada inicial bajo `.scm/`; SQLite solo cache regenerable.
3. SE-396 H02–H12 mantiene prioridad y puede avanzar en paralelo con slices
   read-only/reversibles de F1.
4. Docs/maps stale se conservan hasta disponer de regeneración verificable.
5. Drift/impact continúan report-only; no se declaran claims `SUPPORTED`.

Pendiente no delegable a automatización: canonicalidad/renumeración de IDs
históricos duplicados SE-260 y SE-309. Los resolvers deben fallar closed.

## Veredicto

`GO_WITH_CONCERNS`. Existe base reutilizable suficiente para ejecutar F1,
pero no existe hoy SAM ni evidencia operacional sistémica. La arquitectura
correcta es una proyección derivada y consultable sobre autoridades existentes,
no una nueva fuente de policy, planning, memory o evidence.
