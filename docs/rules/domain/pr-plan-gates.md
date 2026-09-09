---
context_tier: L3
token_budget: 1200
---

# pr-plan Gates Reference

> Gates executed by scripts/pr-plan.sh (sourced from scripts/pr-plan-gates.sh).
> Each gate is registered with gate "GXX" "Name" function_name.
> FAIL stops the run; WARN is recorded but does not block.

## Gate Summary

| ID | Name | Function | Severity | Since |
|---|---|---|---|---|
| G0 | Previous failure | g0 | FAIL | era 180 |
| G1 | Feature branch | g1 | FAIL | era 180 |
| G2 | Clean working tree | g2 | FAIL | era 180 |
| G3 | No merge conflicts | g3 | FAIL | era 180 |
| G4 | Rebase/merge main | g4 | FAIL | era 180 |
| G5 | CHANGELOG updated | g5 | FAIL | era 180 |
| G5b | Extended CI checks | g5b | FAIL | era 190 |
| G6 | Tests pass | g6 | FAIL | era 180 |
| G6b | Test quality quality gate | g6b | FAIL | era 195 |
| G7 | Confidentiality scan | g7 | FAIL | era 185 |
| G8 | README updated | g8 | WARN | era 185 |
| G9 | Private data leak | g9 | FAIL | era 186 |
| G10 | CI local validation | g10 | FAIL | era 187 |
| G11 | PR size review level | g11 | WARN | era 189 |
| G_SUMMARY | PR natural-language summary | g_summary | FAIL | era 190 |
| G_OPENCODE_PLAN | OpenCode Implementation Plan | g_opencode_plan | FAIL | era 195 |
| G13 | Scope-trace audit | g13_scope_trace | WARN | era 199 |
| G14 | Skill catalog audit | g14_skill_catalog | FAIL/WARN | era 200 |

## G6 — changed BATS suites, fail closed

G6 ejecuta los ficheros `.bats` añadidos o modificados respecto a
`PR_PLAN_BASE_REF` (por defecto `origin/main`). Un flujo apilado debe declarar
su rama base mediante esa variable. El gate exige simultáneamente:

- código de salida 0;
- plan TAP de finalización;
- terminación antes de 300 segundos.

Timeout, crash y salida incompleta son `FAIL`. Si no hay tests BATS modificados,
G6 emite `WARN` y delega la selección por impacto al job BATS de CI. Para tests
aislados del propio gate, `PR_PLAN_BATS_FILES` permite inyectar una lista
explícita sin alterar el comportamiento de producción.

## G13 -- Scope-trace audit (SE-079)

Pattern: Genesis B9 GOAL STEWARD + B8 ATTENTION ANCHOR
(docs/rules/domain/attention-anchor.md, SE-080)

Purpose: Verify that every changed file in the PR traces to the spec or task
declared in .pr-summary.md, commit messages, or branch name. Prevents
silent scope-creep -- refactors, comments, or edits in files the spec does not
mention.

Severity: WARN (never FAIL). Advisory in first iteration; escalation to
hard-fail after 2 sprints of telemetry (per SE-079 spec).

Matching rules (in priority order):

1. Whitelist -- always in-scope: CHANGELOG.md, CHANGELOG.d/*, .scm/*,
   .confidentiality-signature, .pr-summary.md
2. Spec self-reference -- the file IS the spec (docs/propuestas/{SE-XXX}-*.md)
3. Path hint match -- the file basename appears in an explicit path mention
   within the spec body
4. Token overlap -- the file basename (without extension, split on - and _)
   shares at least 1 token of length >= 4 with the AC lines of the spec

Override: add a line "Scope-trace: skip -- <reason of 10+ chars>" in
.pr-summary.md. The override is recorded in the gate output.

Multi-spec PRs: G13 collects ALL spec IDs from .pr-summary.md, commit
messages, and branch name. A file matches if it traces to ANY referenced spec.

Standalone runner: scripts/scope-trace-gate.sh exposes the same logic for
use outside of pr-plan. Output is always JSON with fields:
gate, passed, spec_id, files_in_scope, files_outside_scope, verdict.

References:
- Spec: docs/propuestas/SE-079-pr-plan-scope-trace-gate.md
- Pattern doc: docs/rules/domain/attention-anchor.md
- Standalone: scripts/scope-trace-gate.sh
- Tests: tests/bats/test-se-079-scope-gate.bats
