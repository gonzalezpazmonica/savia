---
id: SE-400
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-09-10
approved: 2026-09-10
approved_by: human-operator
author: agent-team
risk: L2
type: architectural-ablation
working_title: Model-Agnostic Savia Ablation & Minimal Sufficient Kernel
related_specs: [SE-030, SE-037, SE-167, SE-270, SE-348, SE-375, SE-376, SE-380, SE-383, SE-384, SE-387, SE-393, SE-394, SE-396, SE-397]
proposed_future_dependencies: [SE-398, SE-399]
execution_scope: F0_ONLY_PENDING_REVIEW
---

# SE-400 — Model-Agnostic Savia Ablation

## 1. Problema y propósito

Savia tiene una superficie funcional amplia, pero resource count no equivale
a capability count. No existe todavía evidencia suficiente para distinguir de
forma sistemática kernel, mecanismos, projections, aliases, packs, hot-path
controls, generated views, legacy y complejidad físicamente redundante.

El objetivo es descubrir una `MINIMAL_SUFFICIENT_SAVIA`: retirar, fusionar,
generar, empaquetar o sacar del hot path solo complejidad cuya ausencia preserve
el contrato Savia. La meta no es una Savia pequeña, sino sin complejidad no
justificada.

## 2. Baseline y restricciones

Ningún modelo, provider, frontend o nivel de inteligencia es baseline. El
baseline es el contrato Savia: identity integrity, authority/effect correctness,
security floors, Human Gates, policy, evidence/provenance, capability coverage,
failure safety/recovery, portability, context discipline, reproducibility,
observability y maintainability.

Security y authority son floors no compensables. Un modelo que compense una
pieza no prueba redundancia; uno que la necesite no prueba pertenencia al core.
El modelo es variable experimental y la evidencia determinista se obtiene sin
inferencia siempre que sea posible.

## 3. Invariantes y no objetivos

- `RESOURCE != CAPABILITY != IMPLEMENTATION != PROJECTION`.
- Low/high usage no implica valor bajo/core; untested/unused no autoriza delete.
- Similaridad de nombres, intents o prompts no prueba equivalencia contractual.
- Pack, async, generated view y compatibility no significan removed.
- `UNKNOWN != DELETE`; toda recomendación física exige evidencia fresca en HEAD.
- Defense-in-depth se evalúa por independencia de failure modes, no por overlap.
- Cualquier false allow, authority regression, critical security regression o
  external effect no reconciliado aborta el experimento.
- No big-bang, objetivos porcentuales, auto-delete, migración estética ni
  retirada L3/L4 sin Human Gate.

## 4. Solución: taxonomía arquitectónica

SAM distinguirá cuando exista autoridad aprobada: Capability, Component,
Mechanism, Script, Control, Projection, Alias, GeneratedView, DomainPack,
Extension y CompatibilityAsset. SCM conserva la capa de capabilities; no se
reemplaza ni se crea otra fuente de verdad.

Estados de essentiality: `CORE_ESSENTIAL`, `CORE_SUPPORTIVE`, `OPTIONAL_PACK`,
`DOMAIN_PACK`, `EXTENSION`, `RUNTIME_PROJECTION`, `UI_PROJECTION`,
`GENERATED_VIEW`, `IMPLEMENTATION_DETAIL`, `COMPATIBILITY_LEGACY`,
`MERGE_CANDIDATE`, `REDUNDANT_CANDIDATE`, `DEAD` y `UNKNOWN`. Solo los dos
últimos candidatos físicos (`REDUNDANT_CANDIDATE`, `DEAD`) pueden llegar a
retirada, siempre con Human Gate.

Core essential requiere pérdida observable de un contrato único, security,
authority, effect verification, provenance, runtime-neutral execution,
recoverability o architecture truth. Core supportive aporta valor transversal
medido. Capabilities domain/role/toolchain/workflow-specific deben probar si
pertenecen a packs sin degradar discoverability.

## 5. Canonicality y boundaries

Auditar sources bajo `.claude`, `.opencode` y `.agents` para evolucionar de
truth frontend-specific a definición Savia canónica con projections runtime.
La migración es incremental: primero contrato, generator, parity y rollback.

El kernel candidato puede incluir provisionalmente identity/principles,
canonical effects, authority/risk/policy/Human Gates, execution/runtime-adapter
contracts, evidence/receipts/provenance, SAM/SCM discovery, integrity/doctor,
minimal context y recovery. Memory, planning, PM, engineering, courts, research
y domains quedan por medir; no se clasifican por hipótesis.

Kernel no dependerá accidentalmente de packs ni de `.claude`, `.opencode` o
`.codex` como conceptos canónicos una vez completada la migración. Packs
declaran dependencias y pueden contener commands, agents, skills, rules, tests,
templates y MCP projections.

## 6. Unidades y modos de ablación

Unidades: file/resource/capability/agent/skill/command/hook/script/policy/
validator/court/judge/adapter/MCP/context/memory/cache/router/generated view/
domain/pack/architecture edge/runtime path.

- A0 discovery: quitar de routing/discovery, conservar artefacto.
- A1 context: no cargar la fuente.
- A2 execution: bypass/no-op controlado en sandbox.
- A3 substitution: sustituir por primitive canónica/genérica.
- A4 hot path: mover a async/batch.
- A5 pack: sacar del kernel manteniendo instalación/discovery.
- A6 physical: retirar solo con evidencia y Human Gate.

Cada preregistration fija hypothesis, unit, expected loss/gain, metrics, abort
conditions, corpus y decision rule. Control y ablation comparten snapshot,
policy, runtime contract, fixtures, workspace, input, outputs y decisiones.
Rutas no deterministas usan paired repetitions.

## 7. Vector de evaluación

No hay score único. Medir por dimensión: contract/task deltas, authority,
false allow/block, security, evidence/provenance, human intervention, context,
latency, processes, dependencies, maintenance surface, portability, recovery y
failure detection. Resultados: essential/value confirmed, pack/projection/
async/merge/redundant candidate, negative result, inconclusive o not verified.

Para mecanismos de control, comparar `UNIQUE_FAILURES_CAUGHT`; containment de
coverage solo permite absorción si no se pierde determinism, coste, portability,
explainability ni defense-in-depth independiente.

Para LLM-mediated work, el panel es heterogéneo y model-agnostic. Registrar
model/provider class y capacidades cuando se conozcan. Una degradación en una
clase impide declarar redundancia global y puede revelar
`MODEL_ROBUSTNESS_SUPPORT`.

## 8. Auditorías por familia

- Commands: canonical capability, alias, parameterization, workflow preset,
  domain entrypoint, wrapper, legacy alias o extended discovery.
- Agents: mantener separados por authority/tools/effects/context/decision/eval/
  isolation/failure; expertise declarativa puede ser profile/pack candidate.
- Skills: unique intent/domain knowledge/process/resources/evaluation.
- Scripts: policy engine, validator, generator, adapter, transport, CLI,
  library, migration, maintenance, test support, compatibility, wrapper o
  deprecated. Generator no es capability salvo contrato user-visible.
- Hooks: enforcement, observability, maintenance, advisory o projection;
  construir event→hook matrix antes de A4.
- Courts/judges: failure-class×mechanism matrix, no similitud textual.
- Memory/context: ablar capas y sources por separado.
- Domains/extensions: remover del kernel discovery y reconstruir como pack.
- Docs/compatibility: canonical/generated/historical/user/runtime/domain/
  duplicate; archivar historia y exigir consumer/reason/review/replacement.

Auditar referencias activas `pm-workspace` como historical-valid,
compatibility-required, stale-identity/config/documentation. AGENTS, SKILLS,
README counts/translations, indexes, roadmap y capability views se tratan como
generated views si existe una authority canónica.

## 9. Experimento de kernel

Comparar `SAVIA_FULL` con `SAVIA_KERNEL_CANDIDATE` en aislamiento, nunca con
cleanup destructivo en main. Golden Kernel Corpus: bootstrap, identity,
discovery/context, read/search, governed write, safe exec, blocked dangerous
effect, Human Gate, secrets, MCP cuando aplique, runtime adapter, receipt,
provenance, failure/recovery/restart y architecture query.

Corpora de dominio validan `KERNEL + PACK = FULL_DOMAIN_CAPABILITY`. Surfaces
SE-398 no verificadas permanecen `NOT_VERIFIED`. SE-399 consumirá grupos kernel,
packs, runtimes, surfaces y extensions solo después de evidencia.

## 10. Outputs y evidencia

Outputs futuros: `output/ablation/core-boundary.{json,md}` y
`removal-candidates.{json,md}`. Removal report contiene exclusivamente DEAD o
REDUNDANT_CANDIDATE; pack/merge/projection nunca son deletes.

Cada receipt liga HEAD, SAM/SCM revisions, unit/mode, configs control/ablation,
runtime/surface, model metadata cuando aplique, corpus hash, expected/observed,
vector, invariants, decision, limitations y known unknowns. Negative results
se preservan y expected impact se compara con observed para mejorar SAM.

## 11. Fases y esfuerzo

- F0 fresh inventory/taxonomy, sin mutaciones.
- F1 normalization resource/capability.
- F2 consumer/dependency/contract/failure graphs.
- F3 kernel candidate aislado.
- F4 deterministic A0–A5.
- F5 agent/skill/command panel.
- F6 domain packs.
- F7 runtime projections.
- F8 hot-path A4.
- F9 legacy/docs.
- F10 physical wave pequeña con Human Gate.
- F11 cross-runtime/model longitudinal regression.
- F12 kernel graduation humana.

Estimación inicial: esfuerzo muy alto, experimental y multiphase. F0 es un
slice medio de inventario reproducible; F1 no comienza hasta su revisión.

## 12. Acceptance Criteria

- AC01–AC10 methodology: baseline sin modelo, contrato versionado, model como
  variable, deterministic-first, preregistration, paired controls, negative
  results, evidence-at-HEAD y gates para physical removal.
- AC11–AC20 architecture: Resource/Capability/Projection/implementation/view/
  core/pack separados, truth sources inventariadas, SAM essentiality, SCM
  mantiene intent coverage y kernel sin dependencia accidental de packs.
- AC21–AC30 audits: commands, agents, skills, scripts, hooks, courts, memory,
  context, domains y extensions auditados con criterios contractuales.
- AC31–AC37 safety: cero false allows, authority/security regressions; Human
  Gate y provenance preservados; UNKNOWN nunca delete; defense-in-depth medido.
- AC38–AC46 simplification: kernel candidate ejecutado; recursos/edges/hooks/
  sync surfaces medidos; truth frontend reducida o justificada; cada physical
  removal con evidencia; packs discoverables y projections con origen.

## 13. Instrucción inmediata

Persistir y ejecutar **solo F0**. No delete, move, deprecation, pack migration
ni F1. Entregar superficie física/indexada, SCM hash, resource-vs-capability,
canonicality/debt freshness, candidatos provisionales, backlog de experimentos
y decisiones humanas. Ninguna clasificación provisional autoriza retirada.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode | Codex |
|---|---|---|---|
| F0 | inventario de source/projections | inventario agents/plugins | inventario AGENTS/skills |
| F1+ | projection desde contrato canónico | projection desde contrato canónico | projection según ceiling |

### Verification protocol

- [x] F0 es read-only y liga conteos a HEAD/SCM hash.
- [ ] Ablations futuras ejecutan control/variant y abortan ante floors.
- [ ] Projection changes futuras validan todos los runtimes disponibles.

### Portability classification

- [x] **DUAL_BINDING** ampliado a las tres familias; ningún frontend/modelo se
  convierte en baseline o source of truth por esta F0.
