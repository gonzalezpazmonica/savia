# SE-388 — Savia ↔ Codex Frontend Adapter

**Estado:** APPROVED + P0/P1 implementados (Mónica 2026-09-05: "Los dos últimos specs son accepted, para que los implementes"). Codex=UNKNOWN hasta probe con CLI instalado; P2+ tras aprobación.
**Fecha:** 2026-09-05 · **Prioridad:** P1 · **Predecesora:** SPEC-127 (provider-agnostic compatibility)
**Principio:** ONE SAVIA · MULTIPLE FRONTENDS · ZERO DUPLICATED TRUTH
**Origen:** spec de la operadora (2026-09-05, pedro-aaron/agentic-planning-kit review). ID asignado tras reconciliación §0.

## 0. Reconciliación Savia (§31 ejecutado)

- **ID:** SE-388 libre (verificado contra docs/specs y planning-state; SE-387 ocupado).
- **ALREADY_IMPLEMENTED / EXTEND_EXISTING:** SPEC-127 (detección runtime + reroute), SE-047 (AGENTS.md/SKILLS.md ya son proyecciones generadas — Slice B = extender el generador existente a Codex), `detect-frontend.sh` + `savia-env` (Slice A base), `opencode-parity-audit`/`judge-routing-verify` (paridad como patrón), MCP infra existente (Slice C = facade), SE-375 registry + SE-386 descriptors (capability metadata), SE-387 F5 (exactly-once), release-invariants (generated truth).
- **GAP real:** probes Codex-specific, AGENTS projection por scope, hook portability classifier para Codex, doctor/degradation report, cross-frontend canary, risk→enforcement mapping Codex.
- **CONFLICT:** ninguno detectado. **NOT_FEASIBLE hoy:** validar capacidades reales de Codex sin el CLI instalado (probe = primer entregable; UNKNOWN ≠ soportado).
- **Decisión:** SPEC como EXTEND de SPEC-127/SE-047 — cero segunda infraestructura.

## 1. Objetivo

Que Savia se ejecute sobre Codex como frontend adicional sin romper ni degradar Claude Code ni OpenCode. Codex = adapter del contrato de frontend, nunca fork ni fuente de verdad. El núcleo no depende de nombres, paths, modelos ni primitivas Codex-specific.

## 2. Tesis

SPEC-127 ya exige provider-agnosticism, detección runtime, capability negotiation, reroute y degradación explícita. Unidad de compatibilidad = **contrato observable de Savia**: invariant → negotiation → frontend mechanism → same observable contract.

## 3. Non-goals

No crear `savia-codex` · no duplicar commands/agents/skills/rules · no convertir `.codex/` ni AGENTS.md en verdad normativa · no hardcodear modelos OpenAI · no asumir capabilities sin probe · no rebajar gates · sin branching Codex-specific en core · no mover enforcement a prompts · no usar MCP como solución universal · no declarar parity porque "funciona".

## 4. Phase 0 — Reconciliation & Feasibility Probe

Matriz por capability: `CAPABILITY | SAVIA CONTRACT | CLAUDE | OPENCODE | CODEX` × `MECHANISM | PARITY | REROUTE | DEGRADATION | RISK`. Clasificación: NATIVE, ADAPTABLE, MCP, GIT_GATE, CI_GATE, DEGRADED_EXPLICIT, UNAVAILABLE, UNKNOWN. UNKNOWN nunca = soportado.

## 5. Frontend Capability Contract

Extender SPEC-127: workspace_resolution, hierarchical_project_instructions, generated_instruction_projection, shell_execution, filesystem_access, tool_call_hooks, pre_tool_enforcement, post_tool_receipts, subagent_fan_out, command_discovery, mcp_client, approvals, sandbox, network_policy, credential_policy, external_effect_control, durable_handoff. Cada capability: status, mechanism, enforcement_tier, evidence, limitations.

## 6. Slice A — Codex Capability Probe
Extender detección canónica (savia-env/detect-frontend). Detección explícita; unknown → fail-explicit; Claude/OpenCode sin regresión; cero branching de marca en core.

## 7. Slice B — Canonical Instructions → AGENTS.md Projection
AGENTS.md = vista generada (proyección por scope, precedencia preservada, determinista, idempotente, provenance, drift detectado). Modificación manual de región gestionada → GENERATED_INSTRUCTION_DRIFT.

## 8. Slice C — Codex MCP Capability Bridge
Codex → MCP → Savia Capability Facade → canonical capabilities (registry/descriptors SE-375/386). Invariante: **MCP exposure ≤ Savia capability permissions**. Least privilege; gates y receipts preservados.

## 9. Slice D — Risk → Codex Enforcement Mapping
Savia risk/laws → Frontend Enforcement Adapter → sandbox/approvals/network/tool policy de Codex. Si una garantía L3/L4 no se mantiene: ENFORCEMENT_PARITY_LOST → REROUTE, BLOCK o HUMAN_REVIEW. Nunca silencio.

## 10. Slice E — Hook Portability
Classifier SPEC-127 aplicado a Codex: native/adapter, git gate, CI, unavailable. 100% safety-critical clasificados; 0 safety-critical UNKNOWN; hooks L3/L4 no portables impiden parity completa; reroutes probados.

## 11. Slice F — Commands, Skills y Agents
Commands: fuente canónica + discovery generada o launcher fino. Skills: validar dependencias ocultas. Agents: declaran tiers/capabilities, nunca modelo/vendor. Fallback no cambia risk silenciosamente.

## 12. Slice G — Cross-Frontend Contract Tests
Canary mínimo: carga de instrucciones · capability discovery · lectura segura · edición permitida · edición prohibida · credential leak · unsafe shell · L3 human gate · L4 blocked · MCP invocation · receipt · terminal reconciliation · write-scope violation · degraded reporting. Parity: FULL / EQUIVALENT_WITH_DIFFERENT_MECHANISM / DEGRADED_SAFE / UNSAFE / UNKNOWN. L4 UNSAFE/UNKNOWN bloquea claim de soporte.

## 13. Slice H — Frontend Doctor / Degradation Report
Doctor generado desde probes y evidencia (instructions/MCP/shell/sandbox/approvals/hooks/fan-out/L4 enforcement → FULL/DEGRADED_SAFE/UNSUPPORTED). Soporte = garantías verificadas, no "conversar y editar".

## 14. Slice I — Installer / Onboarding
Extender savia-setup con `frontend: codex` (provider como eje independiente). Detectar capabilities, mostrar degradaciones, generar proyecciones, configurar MCP, canary. Idempotente.

## 15. Configuration Boundary
Separar SAVIA POLICY / FRONTEND CAPABILITY / PROVIDER / MODEL / USER PREFERENCE. Codex frontend ≠ OpenAI API provider.

## 16. No-Duplication & Generated Truth
Prohibido `.codex/agents-copy`, skills-copy, rules-copy. Toda superficie Codex = generated projection, adapter, thin launcher o configuration. derived + manual = architecture smell.

## 17. Context Surface
Medir instrucciones, tokens inyectados, normativa duplicada, routing hops y MCP discovery surface. Proyección por scope; prohibido "todas las reglas en AGENTS.md".

## 18. Receipts, Provenance & Exactly-Once
Receipts con frontend: codex, adapter_version, capability, mechanism, risk_level, approval, evidence, effect_id, receipt_id. Reutilizar effect reservation/idempotency SE-387 (reserve → invoke → effect → receipt; retry → ALREADY_EXECUTED).

## 19. Human Gates
Savia requests approval → frontend presents → human decides → Savia records. Nunca traducir L3/L4 a auto-approval.

## 20. Security Acceptance (antes de SUPPORTED)
credential leak protection · unsafe shell policy · filesystem scope · network policy o degradación explícita · prompt-injection controls · L3 gate · L4 block · MCP privilege-escalation negative test · write-scope violation · external effect exactly-once · approval receipt · terminal reconciliation.

## 21. Compatibility Acceptance
Claude Code: suite sin regresión · OpenCode: hooks/slash/provider-agnosticism preservados · Codex: onboarding, projection, probe, canary, mapping, doctor, canary cross-frontend.

## 22. Definition of Supported Frontend
Codex = SUPPORTED solo con: probe determinista · instrucciones canónicas llegan · safety-critical con mecanismo/reroute probado · L4 zero UNKNOWN · human gates · receipts/provenance · exactly-once · terminal reconciliation · doctor = evidencia · Claude/OpenCode sin regresión. Garantías no críticas perdidas → DEGRADED_SAFE. Críticas → UNSUPPORTED.

## 23. Adversarial Tests
Missing primitive → reroute/block · AGENTS drift → GENERATED_INSTRUCTION_DRIFT · MCP privilege escalation → BLOCK · shell bypass → enforcement alternativo por tier · lost human gate/auto-approval → BLOCK · duplicate Codex truth → GENERATED_TRUTH_VIOLATION · context explosion → CONTEXT_SURFACE_REGRESSION · retry efecto → ALREADY_EXECUTED.

## 24. Observability
Extender coherence: `frontend_compatibility` (claude_code/opencode/codex) + codex counters (native/rerouted/degraded/unknown/l4_unknown/context_surface/canary_pass_rate) — derivados, no manuales.

## 25. Rollout
P0 reconciliation+probe · P1 detection+AGENTS projection+doctor (sin blockers) · P2 MCP bridge+canary · P3 risk mapping+hook portability (L4 primero) · P4 cross-frontend suite · P5 graduación por evidencia. Nunca soporte por calendario.

## 26. Arquitectura preferida
Frontend-native projections Y capability facade/MCP según seguridad: deterministic local enforcement > native primitive > adapter > MCP > git/CI reroute > degradation > block.

## 27. Riesgos
False parity→contract tests+doctor · third truth→projections · security degradation→L4 zero-UNKNOWN fail-closed · MCP god-interface→least privilege/descriptors · context explosion→scoped projection · coupling→ejes separados · regresión Claude/OpenCode→suite obligatoria.

## 28. Entropy Budget
Delta medido: canonical capabilities, adapters, projections, manual rules, duplicated instructions, vendor conditionals. Objetivo: duplicated truth=0 · vendor branching en core=0.

## 29. Deliverables
Codex descriptor/adapter · probe · AGENTS projection generator · doctor · MCP facade (si necesaria) · risk mapping · hook portability report · cross-frontend tests · onboarding · compatibility report. Integrados en mecanismos existentes.

## 30. Definition of Done
Reconciliada · adapter aislado · AGENTS proyección · negotiation · safety hooks 100% clasificados · L4 zero UNKNOWN · MCP least-privilege probado · risk mapping probado · human gates · exactly-once + terminal reconciliation · Context Surface medido · doctor desde evidencia · canary verde · Claude/OpenCode sin regresión · Codex clasificado honesto · canonical state reconciliado antes de CLOSED.

## 31. Instrucción para Savia
Ejecutado (§0): HEAD/planning leídos, reconciliada con SPEC-127 y posteriores, solapamientos mapeados (ALREADY_IMPLEMENTED/EXTEND vs GAP), rechazadas duplicaciones, mínimo cambio propuesto, PROPOSED, human gates para L3/L4, sin declarar SUPPORTED sin cross-frontend suite, sin rebajar garantías.

## 32. Principio final
"Savia conserva contratos, criterio, seguridad, evidencia y autoridad humana usando Codex como frontend sustituible." ONE SAVIA + MULTIPLE FRONTENDS + CAPABILITY-BASED ADAPTATION + ZERO DUPLICATED TRUTH + ZERO SILENT DEGRADATION = REAL FRONTEND AGNOSTICISM.

## 33. OpenCode Implementation Plan

### Clasificación
- **Tier:** 2 (P1: probes/proyecciones/doctor en scripts+registry; P3 enforcement mapping L4 = revisión humana) · **Agent-capable:** yes (P0-P1)
- **Slices:** S1 Codex probe + capability matrix (P0) · S2 AGENTS projection generator por scope (extiende SE-047) · S3 doctor/degradation report · S4 risk mapping + hook portability report · S5 cross-frontend canary · S6 onboarding
- **Depends:** SPEC-127, SE-047, SE-375, SE-386, SE-387 (F5) · **Bloquea:** soporte Codex (nunca por calendario)
- **Prerequisito:** Codex CLI disponible en el entorno para probe real; sin él, estado = UNKNOWN fail-explicit

## Referencias
SPEC-127 · SE-047 · SE-375 · SE-386 · SE-387 · spec operadora 2026-09-05
