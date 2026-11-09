# SE-386 — Savia Constitutional Runtime Contracts

**Estado:** SUPERSEDED — decisión de la operadora del 2026-11-09 por pregunta interactiva; absorbida por SE-496 (F5); F1 y F2 en main (#1090), F3 y F4 se abandonan. Estado y aprobación anteriores: Mónica (operadora), 2026-09-05: "aprobada"
**Fecha:** 2026-09-05 · **Prioridad:** P1 · **Developer Type:** agent-team · **Risk:** L3
**Dominio:** Governance/Architecture · **Principios:** CRIT-001, humano decide, soberanía
**Origen:** spec de la operadora (2026-09-05). Renumerada de SE-265 (ocupado: court-model-tiers) a **SE-386** (verificado libre).

## 0. Reconciliación

Jerarquía CRITERIO→LAWS→SPEC→CONTRACTS→IMPLEMENTATION→TESTS compatible con la gobernanza existente. CRITERIO vive en CONSTITUCION/principios (no se duplica). Reutilizar: `.scm/registry.json` (SE-375) como base de capacidades, patrones SE-374/377 (enforcement) y SE-383 (chaos). Nada sustituye la aprobación humana.

## 1. Objetivos
O1 Separar criterio/invariantes/cambios (jerarquía normativa; una impl que contradiga una LAW es incorrecta). O2 Capability Contracts: descriptor canónico proyectable a JSON Schema/CLI/MCP/A2A/docs/fixtures. O3 Safety metadata ejecutable con política mínima. O4 Transport sin policy (dispatcher central). O5 Import-pure. O6 Federación con re-evaluación local (confianza ≠ autorización).

## 2. Architectural Laws
`laws/` → README.md, agents.md, memory.md, execution.md, human-control.md, privacy.md, federation.md, capabilities.md.
Reglas de LAW: MUST observable · MUST/MUST NOT · única obligación · independiente de tecnología · durable · sin framework · sin duplicar CRITERIO · test cuando verificable.
Ejemplos: LAW-HUMAN-001 (no mutación externa irreversible sin decisión humana explícita) · LAW-MEMORY-003 (rechazo de mutación de memoria no altera el estado canónico) · LAW-FED-002 (instancia remota no obtiene capabilities que la local negaría).

## 3. Law Registry
`laws/index.yaml` machine-readable (id/domain/severity/document/testable). El Markdown humano es la fuente normativa.

## 4. Impacto en SPECs
Spec que modifica comportamiento declara `laws: {affected, introduced, changed, deprecated}`; ausencia → warning/error en validación.

## 5. Capability Contract
`contracts/capabilities/<id>.yaml`: id, version, description, input (schema), safety (effect/visibility/reversibility/destructive/external_side_effect/human_gate/scope), execution.handler, laws[].

## 6. Single Source of Truth
Del descriptor se generan todas las proyecciones; adaptadores MUST NOT redefinir parámetros/bounds/safety/descripción.

## 7. Transport vs Policy
LAW: transport MUST NOT contener policy de autorización de dominio. Caller→Transport→Dispatcher(schema→policy→CRITERIO→LAW→human gate→observability)→Handler.

## 8. Import-Pure
Importar descriptor sin red/memoria/ficheros/secrets/estado/hooks/telemetría/side effects; handlers solo en precheck/execute.

## 9. Safety Metadata
effect: read|mutation|external_action · visibility: visible|discoverable|silent · reversibility: reversible|compensatable|irreversible · human_gate: none|policy|required · destructive · external_side_effect.
Política: irreversible→human_gate required · silent+mutation→rechazado salvo excepción constitucional · destructive→declara alcance/pérdida/aprobación/auditoría.

## 10. CRITERIO pipeline
Schema→Safety→CRITERIO→LAW→Human gate→Execution. CRITERIO independiente de la interfaz.

## 11. Federation
Anunciar {capability, version, safetyClass, available}; la receptora re-evalúa localmente permisos/CRITERIO/safety/human gates.

## 12. Versionado
Cambios incompatibles → incrementar version.

## 13/14. Generación y CI
`savia contracts generate|check`; check detecta stale/schemas inválidos/IDs duplicados/versiones inconsistentes/safety ausente/LAWs inexistentes. CI: contract-check · law-check · safety-metadata-check (falla en los 7 casos §14).

## 15. Migration
F1 laws+registry+validador+5 leyes. F2 descriptors (3-5 caps representativas). F3 proyecciones. F4 integración superficies. F5 safety→policy engine.

## 16. Non-goals
No sustituir CRITERIO/SDD · no proveedor nuevo · no ACP/Tauri · no leyes para decisiones de producto · no big-bang.

## 17. Acceptance Criteria
Distinción formal capas · laws/README · registry · ≥5 leyes · specs declaran laws · descriptor · import-pure · safety estándar · ≥1 proyección doble · CI stale · CI irreversible+gate · transport/policy separados · federación re-evaluada · cero dep. proveedor.

## 18. Principio
«CRITERIO decide los límites. LAWS preserva las garantías. SPEC decide la evolución. CONTRACTS hacen la intención ejecutable.»

## 19. OpenCode Implementation Plan
### Clasificación
- **Tier:** 2 · **Agent-capable:** yes (F1+F2 MVP)
- **Slices:** S1 laws/+registry+5 leyes+law-check.sh · S2 descriptor+4 caps+contract-check.sh · S3 coherence-gates advisory + validación de specs
- **Depends:** SE-375 (registry) · SE-374/377 (enforcement) · **Feeds:** SE-381

## Referencias
CRITERIO (no duplicado) · SE-365 · SE-375 · SE-374/377/383 · spec operadora 2026-09-05

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **F5 pasa a SE-496**, que convierte los descriptores de esta spec en acciones con precondiciones y efectos. F1 y F2 están en main (#1090); F3 y F4 esperan decisión.
