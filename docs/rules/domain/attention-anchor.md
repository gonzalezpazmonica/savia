---
context_tier: L3
token_budget: 1185
---

# Regla: Attention-anchor vocabulary

> Nombres canónicos para 4 patterns que pm-workspace ya implementa, alineados con el catálogo Genesis (`danielmeppiel/genesis`). Adopción 100% vocabulary, 0 código nuevo. Vigente desde SE-080.

## Why

Cuando integramos con OpenCode (SE-077), Codex u otros frontends que adopten el catálogo Genesis, nuestros primitives quedan "anónimos" — el otro lado no reconoce que ya cumplimos los patterns. Friction de interoperabilidad. Esta doc cierra ese gap nombrando los 4 patterns que ya implementamos, sin tocar código.

## Pattern map

| Pattern | Genesis ref | pm-workspace implementación |
|---|---|---|
| **B8 ATTENTION ANCHOR** | `skills/genesis/assets/design-patterns.md` | Re-inyección del goal en cada worker spawn (`SPEC_WORKER_ID` + `Spec ref:` line en `.pr-summary.md`) |
| **B9 GOAL STEWARD** | `skills/genesis/assets/design-patterns.md` | `radical-honesty.md` Rule #24 + G13 scope-trace gate (SE-079) |
| **A7 ADVERSARIAL REVIEW** | `skills/genesis/assets/architectural-patterns.md` | Code Review Court — 5 jueces consensus (SPEC-124) |
| **A9 SUPERVISED EXECUTION** | `skills/genesis/assets/architectural-patterns.md` | `autonomous-safety.md` — revisión humana, draft PRs, agent/* branches |

## B8 — ATTENTION ANCHOR

Re-inyectar el goal/constraint del request original en sesiones largas para mitigar drift. Nuestra implementación:

- **Orchestrator**: `parallel-specs-orchestrator.sh` exporta `SPEC_WORKER_ID` y la cadena de spec ref a cada worker subshell, anclando el goal en el entorno
- **PR**: `.pr-summary.md` (G11) obliga a un párrafo en lenguaje no técnico con la spec ref — anchor textual
- **Gate**: G13 (`g13_scope_trace`) verifica que los archivos cambiados traceen al spec — anchor estructural
- **Output**: G13 emite `B8 attention-anchor present (<spec_id>)` cuando pasa, dando feedback explícito

## B9 — GOAL STEWARD

Defender el alcance del request frente a refactors colaterales y feature creep. Nuestra implementación:

- **Política**: `radical-honesty.md` Rule #24 — "don't add features beyond what the task requires"
- **Gate**: G13 fuerza la política con un check determinístico pre-push (no LLM, target <1s overhead)
- **Override**: `Scope-trace: skip — <reason ≥10 chars>` en `.pr-summary.md` para casos legítimos auditables

## A7 — ADVERSARIAL REVIEW

Panel adversarial pre-merge donde múltiples jueces evalúan independientemente. Nuestra implementación:

- **Court**: 5 jueces deterministas + 1 opcional (qodo PR-agent) — SPEC-124 batch 56
- **Tribunal de la verdad**: 7 jueces para reports/audits — `truth-tribunal-orchestrator`
- **Trigger**: `/court-review` invoca el panel sobre cualquier branch

## A9 — SUPERVISED EXECUTION

Humano siempre en el loop para acciones irreversibles. Nuestra implementación:

- **Política**: `autonomous-safety.md` — `AUTONOMOUS_REVIEWER` distinto si es elegible; operadora única puede revisar sus PRs
- **Boundaries**: NEVER auto-merge, NEVER force-push, NEVER aprobar PR autónomamente
- **Branches**: agentes operan SOLO en `agent/*` — main/develop intocables
- **PRs**: SIEMPRE Draft; reviewer distinto elegible u operadora única, merge con grant expreso y gates

## Adopciones futuras

Esta regla NO porta el resto del catálogo Genesis (R-tier refactors, A1-A6 architectural, B1-B7/B10 design). Cualquier adopción adicional requiere spec separado.

Lo que está deliberadamente FUERA de scope:

- `apm`/`npx skills add` distribution → bypasa hooks, anti-pattern bajo autonomous-safety
- Agente "genesis-architect" → duplicaría `spec-driven-development` skill
- `common.md` + per-harness adapter pattern → conflicto con bet AGENTS.md (SE-078)

## Citations

- Genesis upstream: `danielmeppiel/genesis` (review sub-agent 2026-04-26 — https://github.com/danielmeppiel/genesis)
- `skills/genesis/assets/design-patterns.md` — definición original de B-tier
- `skills/genesis/assets/architectural-patterns.md` — definición original de A-tier

## Vocabulario relacionado

- `docs/rules/domain/architectural-vocabulary.md` (SE-082) — Module/Interface/Seam/Adapter/Depth/Locality. Vocabulario obligatorio para outputs de `architect` y `architecture-judge`. Implementa B8 ATTENTION ANCHOR sobre vocabulario arquitectónico.

## Referencias

- SE-080 spec — `docs/propuestas/SE-080-attention-anchor-vocabulary.md`
- SE-082 spec — `docs/propuestas/SE-082-architectural-vocabulary-discipline.md`
- SE-079 spec — `docs/propuestas/SE-079-pr-plan-scope-trace-gate.md` (G13 emite B8)
- `docs/rules/domain/radical-honesty.md` — Rule #24 (B9)
- `docs/rules/domain/autonomous-safety.md` — gates (A9)
- `docs/rules/domain/code-review-court.md` — Court (A7) si existe
- SE-074 — orchestrator (B8 vía `SPEC_WORKER_ID`)
