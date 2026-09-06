# SE-389 — Regulatory Policy-as-Code & Compliance Context (EU AI Act slice)

**Estado:** APPROVED + MVP IMPLEMENTING (Mónica 2026-09-05: "analiza, adapta, redacta, persiste, mete en el roadmap, implementa, testea, depura, documenta")
**Prioridad:** P1 · **Risk:** L3/L4 cuando afecte capacidades de alto riesgo
**Jurisdicción inicial:** EU · **Framework:** EU AI Act — Regulation (EU) 2024/1689, enmienda (EU) 2026/1744
**Principio:** «Compliance ejecutable, generador de evidencia y gobernado por humanos — no meramente documental.» «Se delega la ejecución, nunca el criterio.»

## 0. Reconciliación (§19 ejecutada)

- **ALREADY_IMPLEMENTED:** capability registry (SE-375), receipts (SE-374/377/387 F5), risk model L0-L4, human gates, frontend parity canaries (SE-388), bitemporalidad (memoria).
- **EXTEND:** el evaluador consume ComplianceContext + riesgo Savia existente (monotónico: sólo añade restricciones).
- **GAP (esta spec):** registry de políticas regulatorias con validación humana, ComplianceContext, evaluador determinista, receipt de compliance, niveles de verdad regulatoria.
- **NO duplicar:** nada de enforcement L3/L4 fuera del pipeline existente.

## 1. Niveles de verdad regulatoria (no colapsables)

SOURCE_TEXT → HUMAN_INTERPRETATION → EXECUTABLE_POLICY → RUNTIME_FACT → SYSTEM_INFERENCE → UNKNOWN.
SYSTEM_INFERENCE jamás asciende silenciosamente a HUMAN_INTERPRETATION.

## 2. ComplianceContext (runtime)

jurisdiction (EU, explicit) · regulatory_frameworks (EU_AI_ACT) · actor.role (provider/deployer/...; UNKNOWN si ambiguo) · system (ai_enabled, model, frontend, capability) · interaction (human_facing, audience, channel) · content (ai_generated, ai_manipulated, public_interest=unknown) · autonomy (level, external_effect) · human_oversight (required, performed) · provenance.available · regulatory_unknowns[].
Cada campo con origen: EXPLICIT | DERIVED | INFERRED | UNKNOWN.

## 3. Registry de políticas

`regulatory/registry/*.yaml` — ciclo de vida: DRAFT → LEGAL_REVIEW_PENDING → HUMAN_VALIDATED → EXECUTABLE → SUPERSEDED.
Savia genera candidatos; **Savia NO promueve DRAFT → HUMAN_VALIDATED** (§18: gate humano). Política ejecutable sin estado EXECUTABLE no se aplica (fail-safe).

### Política inicial (slice Art. 50 — transparencia)

EU-AIA-ART50-HUMAN-INTERACTION: si human_facing ∧ disclosure_required ∧ ¬disclosure_performed → **BLOCK** (determinista, §19: no requiere LLM).
Estado inicial: **LEGAL_REVIEW_PENDING** — requiere validación humana del texto fuente antes de EXECUTABLE.

## 4. Decisiones

ALLOW · ALLOW_WITH_DISCLOSURE · REQUIRE_HUMAN_REVIEW · REQUIRE_HUMAN_APPROVAL · BLOCK · UNKNOWN · NOT_APPLICABLE. Toda decisión con policy id/version, reason, source (regulación/artículo), context_used, unknowns, evidence_required.

## 5. Interacción con riesgo Savia (monotonía)

regulatory_policy puede AÑADIR restricciones; **NUNCA reduce** riesgo/authority existentes. NOT_APPLICABLE regulatorio no rebaja clasificación Savia.

## 6. Receipts y provenance

compliance_receipt: execution_id, policy_versions, context_hash, decisions, human_gates, disclosures, unresolved_unknowns, final_effect(hash), timestamp. Reutiliza infraestructura de receipts existente (SE-374/377/387 F5).

## 7. Slices implementados en este PR (MVP)

S1 ontología (roles, truth levels, unknown taxonomy) · S2 ComplianceContext schema · S3 registry con Art50 en LEGAL_REVIEW_PENDING · S4 evaluador determinista · tests §28 (draft no ejecuta, unknown fail-safe, disclosure missing→BLOCK cuando EXECUTABLE, monotonía) · S6-S12 siguientes PRs.

## 8. Testing (§28 core)

- draft/LEGAL_REVIEW_PENDING no puede enforzar.
- UNKNOWN (actor/rol/jurisdicción) permanece unknown → UNKNOWN.
- disclosure_required sin disclosure → BLOCK (sólo si policy EXECUTABLE).
- policy EXECUTABLE no rebaja riesgo Savia.
- receipt con policy_version + context_hash.

## 9. Documentación

docs/specs/SE-389 (este fichero) + planning-state + roadmap. DoD §35 requiere demostrar cadena completa qué/por qué/quién/evidencia — pendiente validación humana Art50 (P1 siguiente).

## Referencias
EU 2024/1689 Art.50 + enmienda 2026/1744 · SE-375/377/386/387/388 · spec operadora 2026-09-05
