# SE-390 — Savia Documentation & Identity Evolution

**Estado:** APPROVED + IMPLEMENTING (Mónica 2026-09-05: "Añade spec, e implementa... pr y merge")
**Prioridad:** P1 · **Tipo:** Documentation Architecture / Product Identity / Migration
**Repo canónico:** `gonzalezpazmonica/savia` · **Identidad legacy:** "PM-Workspace / pm-workspace" (HISTORICAL/COMPATIBILITY)
**Principio:** ONE SAVIA · ZERO DUPLICATED TRUTH · «Se delega la ejecución, nunca el criterio.»

## 0. Reconciliación
- Repo ya renombrado a `gonzalezpazmonica/savia` (redirect GitHub activo — no depender de él).
- AGENTS.md/CLAUDE.md/SKILLS.md ya son proyecciones generadas (SE-047) — la identidad fluye desde fuentes canónicas existentes.
- Hallazgos v1 (inventory): README primero como PM-tool, contadores ok (post #1100), referencias legacy concentradas en README históricas + nombres técnicos compat.

## 1. Definición canónica

**Larga:** «Savia es un sistema agéntico soberano para gobernar y ejecutar trabajo asistido por IA. Integra agentes, memoria, seguridad, políticas ejecutables, trazabilidad, evaluación y dominios especializados sobre una arquitectura independiente de modelo, proveedor y frontend. La IA puede asumir progresivamente más ejecución sin apropiarse de la autoridad: se delega la ejecución, nunca el criterio.»

**Corta:** «Sistema agéntico soberano para gobernar y ejecutar trabajo con IA, independiente de modelo, proveedor y frontend, con criterio humano por diseño.»

## 2. Invariantes de identidad

PROJECT_NAME=Savia · REPOSITORY_NAME=savia · CANONICAL_REPOSITORY=gonzalezpazmonica/savia.
"PM-Workspace/pm-workspace" = HISTORICAL_IDENTITY / LEGACY_TECHNICAL_IDENTIFIER / COMPATIBILITY_IDENTIFIER según contexto. Nunca identidad actual paralela.

## 3. Posicionamiento (§5)
Savia NO se define como: PM tool · colección de prompts/agentes · AI assistant · CLI · wrapper de LLM/frontend. Son partes o perspectivas.

## 4. Modelo conceptual (§6)
HUMAN (criterio/autoridad) → SAVIA → Governance (Policy/Risk/Gates) + Execution (Agents/Skills/Tools) + Memory (Context/Knowledge/History) → Evidence/Evals → Frontends + Providers.

## 5. Propiedades documentadas
- **Human authority:** execution authority ≠ decision authority. Materializada vía risk levels, human gates, contracts, receipts, provenance, policy enforcement.
- **Sovereignty:** significado técnico (model/provider/frontend independence, data boundaries, portable execution, inspectable policies, recoverable context). Sin afirmar dimensiones no demostrables.
- **Independence:** Savia ≠ OpenCode/Codex/Claude Code/ChatGPT/LLM concreto. Capability over vendor.
- **Domains:** Savia Core (Governance/Execution/Memory/Safety/Policy/Evidence/Evaluation) + domain capabilities (Project Management = ORIGIN DOMAIN + CURRENT SPECIALIZED DOMAIN; Software Engineering; ...). Lista real deriva del registry.
- **Evidence over claims:** afirmaciones fuertes enlazan a contract/matrix/canaries/adapter.
- **Supported vs compatible:** SUPPORTED/DEGRADED_SAFE/EXPERIMENTAL/UNKNOWN/UNSUPPORTED (consistente con parity rules SE-388).
- **Policy-as-code:** document → machine-readable → runtime enforcement → evidence. Sin afirmar traducción automática universal.
- **Compliance:** regulatory source ≠ human interpretation ≠ executable policy ≠ runtime fact ≠ evidence. Jamás "Savia garantiza legal compliance" sin evidencia.
- **Memory:** infraestructura gobernada (provenance/trust/temporality/retrieval/scope/retention). Sin antropomorfismos.
- **Autonomy:** graduada y gobernada (capability+authority+risk+context+gates). Más autonomía de ejecución ≠ más autoridad decisoria.
- **Evolution:** proposal/spec → implementation → evaluation → evidence → enforcement.

## 6. Jerarquía documental (§13)
L0 Identity · L1 Principles · L2 Architecture · L3 Capabilities · L4 Domains · L5 Operations · L6 Governance.

## 7. README (§14/§15)
Rediseñado desde identidad actual: SAVIA → definición → why → principles → what → architecture → domains → how it works → frontends → governance/safety → quick start → docs → contributing → origin/history. First-screen invariant: qué es/diferencia/uso sin conocer "pm-workspace".

## 8. Legacy references (§29-30)
Clasificación: CURRENT_IDENTITY/HISTORICAL/TECHNICAL_IDENTIFIER/COMPATIBILITY/URL/GENERATED/TEST/EXTERNAL. Sin search-replace global. Identificadores técnicos (mcp/pm-workspace-server.json, "name":"pm-workspace", PM_WORKSPACE_*): clasificar RENAME/ALIAS_AND_DEPRECATE/KEEP_FOR_COMPATIBILITY/UNKNOWN_REQUIRES_INVESTIGATION — el cambio documental no rompe interfaces.

## 9. Machine-readable identity (§17)
CLAUDE.md/AGENTS.md/llms.txt/generated context reciben identidad Savia. Runtime identity override stale context (SE-388 C: savia_frontend runtime precedence).

## 10. Drift gate (§34)
`scripts/docs-identity-check.sh`: identidad legacy accidental · URLs legacy nuevas · definiciones canónicas divergentes · generated stale · Savia reducida a PM · vendor como identidad. Allowlist razonada (historia/compatibilidad). Tests semánticos mínimos (§35): README expresa Savia/agentic/human authority/independencia.

## 11. Implementación (slices executed)
- S1 inventory → output/savia-documentation-inventory.md
- S2/S3: README.md rediseñado (identidad + first-screen invariant + origin/history)
- S6: CLAUDE.md/AGENTS.md línea de identidad + llms.txt
- S7: traducciones README.* actualizadas equivalente
- S8: clasificación legacy identifiers (sin renombrar consumidores)
- S9: gh repo description/topics
- S10: docs-identity-check.sh + bats

## 12. Acceptance (§41)
Savia única identidad actual · README describe Savia actual · PM=dominio/origen · independencia explicada · criterio humano propiedad arquitectónica · soberanía técnica · agents/LLMs reciben identidad correcta · URLs savia · legacy clasificado · sin contratos rotos · generated truth reconciliada · drift gate existe.

## 13. Cierre (§42) — NO alcanzado aún
Requiere: zero accidental legacy identity en TODO el repo, zero UNKNOWN consumers, benchmark canaries parity. Queda abierto tras el MVP.

## Referencias
spec operadora 2026-09-05 · SE-047 (generated truth) · SE-388 (parity/ceiling) · SE-379 (release invariants)
