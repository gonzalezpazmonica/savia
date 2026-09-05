---
layer: peripheral
name: evidence-first-development
description: "Desarrollo evidence-first: rodea la implementación con un SPEC aprobado y un gauntlet de restricciones para que el line-by-line review sea opcional. Usar cuando se pide alta garantía (prove it works, no leeré el código), o en dominios de alto riesgo (dinero, auth, pérdida de datos, concurrencia)."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: sdd-framework
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: high
  savia.maturity: beta
  savia.priority: high
  savia.summary: "SPEC → RED → GREEN → REFACTOR → GAUNTLET → EVIDENCE. Confianza por restricciones ejecutables, no inspección. Ref: old-coder (MIT), pattern-only."
  savia.tags: "evidence-first, gauntlet, mutation, coverage, sdd, anti-gaming"
  savia.trigger_keywords: "evidence-first, gauntlet, prove it works, no leeré el código, high-assurance, reliable"
---

## Subagent Scope Guard

> Si fuiste invocado como subagente con una tarea concreta, ejecuta solo
> esa tarea y reporta DONE / DONE_WITH_CONCERNS / BLOCKED. NO actives el
> workflow completo de esta skill.

# Skill: Evidence-First Development

El humano NO leerá tu implementación. Confianza en dos artefactos: un SPEC
ejecutable aprobado antes del código, y un informe EVIDENCE con números reales
después. La confianza pasa de inspección a restricciones.

Límite honesto: el gauntlet no demuestra que el SPEC cubre todo lo importante,
ni es auto-autenticable. Por eso el SPEC va al humano y EVIDENCE reporta
confianza en capas, nunca prueba absoluta. Ver `DOMAIN.md`.

## Authoritative Paths

> **Lee antes de actuar. NUNCA asumas firmas ni inventes paths.**

| Para | Lee este path |
|---|---|
| Tooling del gauntlet por ecosistema + plantilla EVIDENCE | `references/gauntlet.md` |
| Checkers caseros fail-closed | `docs/rules/domain/checker-fail-closed.md` |
| Cobertura changed-line | `docs/rules/domain/changed-line-coverage.md` |
| Mutation testing | `../mutation-audit/SKILL.md` |
| Aprobación de spec (answer ≠ approval) | `../spec-driven-development/SKILL.md` |

## Cuándo usar / NO usar

- **Usar**: alta garantía explícita ("prove it works", "no leeré el código") · dominios de alto riesgo (dinero, auth, datos, concurrencia, API pública) · review que no escala.
- **NO usar**: cambios triviales (Tier 1) · tests normales sin bucle completo · ya cubierto por `verification-lattice` + Court.

## Decision Checklist

1. ¿Toca dinero/auth/datos/concurrencia/API pública? → Tier 3 (failure model + adversarial pass)
2. ¿Bug fix o feature pequeña? → Tier 2 (bucle completo, RED reproduce el bug)
3. ¿Trivial (typo/comment/config)? → Tier 1 (suite + lint)
4. ¿El humano aprobó el SPEC? → si NO: EVIDENCE registra `spec approval: not obtained` y reclama menos confianza

### Abort Conditions

- SPEC con placeholders (TODO/TBD) → incompleto, no empezar
- Sin test runner/linter/typechecker y el humano prohíbe añadirlos → capas manuales, confianza reducida
- Cualquier capa del gauntlet falla → bloquear "done", reportar verbatim

## Workflow

```
SPEC → (humano aprueba spec, no código) → RED → GREEN → REFACTOR → GAUNTLET → EVIDENCE
                                          ↑_________________________|  repeat per behavior
```

1. **SPEC**: criterios ejecutables (Gherkin o lista de tests con inputs/outputs, edge cases, invariantes que deben sobrevivir) + setup plan (cada dependencia justificada). Path absoluto, aprobación antes de código.
2. **RED→GREEN→REFACTOR**: un behavior por ciclo; **obsérvalo fallar** (si pasa de inmediato, throwaway mutant para probarlo); mínimo código; assertions congeladas.
3. **GAUNTLET→EVIDENCE**: corre cada capa (tabla en `references/gauntlet.md`), nunca saltes en silencio; informe con números de **una ejecución fresca final**, reproducible desde el repo (entry-point + versiones pineadas + source state).

## Anti-gaming rules (absolutas)

Nunca debilitar un test · nunca editar test+impl a la vez · nunca mockear el SUT (mockea fronteras) · nunca perseguir cobertura · nunca reportar una capa no corrida · gauntlet fallando bloquea done.

## Calibración

Tier 1 trivial (suite+lint) · Tier 2 normal (bucle completo, bug fix empieza en RED) · Tier 3 high-stakes (failure model: una capa por modo de daño + adversarial pass). Detalle: `DOMAIN.md`.

## Outputs esperados

- SPEC aprobado (path absoluto, append-only)
- EVIDENCE report (`references/gauntlet.md`) con spec→test mapping y números de ejecución fresca
- Entry-point persistido en repo (`tools/gauntlet.sh`)

## Memory hooks

- Tras éxito: guardar la capa que cazó un bug real → `bash scripts/memory-store.sh save --type pattern --title "gauntlet-catch-<lenguaje>" --content "<capa> cazó <bug>" --source skill:evidence-first-development`

## Related

- Skill: `../mutation-audit/SKILL.md`, `../tdd-vertical-slices/SKILL.md`, `../verification-lattice/SKILL.md`, `../spec-driven-development/SKILL.md`
- Rule: `docs/rules/domain/checker-fail-closed.md`, `docs/rules/domain/changed-line-coverage.md`
- Ref: AmazingAng/old-coder (MIT) — pattern only, prosa propia
