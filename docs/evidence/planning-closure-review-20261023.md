# Conciliación de planning-state con main — 2026-10-23

> Revisión AC por AC de las specs APPROVED e IMPLEMENTING frente a `origin/main` (0dd2ea30b).
> Autoridad según `docs/rules/domain/ac-verifier-authority.md` (SE-444). La autoridad requerida
> se infiere del texto de cada AC (las specs son anteriores a la plantilla con `autoridad_requerida`).
>
> Limitación: este informe lo escribe la autora de la conciliación y el validador solo comprueba que el fichero
> existe. `authority_required` es una propuesta, no un dato verificado. Antes de `human_review`, cotejar en GitHub
> los run IDs citados (SE-426 AC5: 39504031706 y 39903878046; SE-442 AC5: 39498696379, 39903767248, 39903767015).

## Regla que limita el cierre

`scripts/roadmap.sh validate` exige, para todo IMPLEMENTED desde SE-396, `completion.human_review.status == "APPROVED"`
con evidencia. Esa revisión solo la puede dar la operadora (Rule 8: sin autoaprobación). Por eso esta revisión
**no cambia ningún estado**: deja en `planning-state.json` el bloque `completion` (PR fusionada y evidencia AC con
autoridad) de las specs que cumplen todos los AC, sin `human_review`. Graduar es añadir la revisión humana y ejecutar
`spec-lifecycle.sh --status IMPLEMENTED`.

Ejecuciones de esta revisión (árbol de main): `validate-ci-local.sh --quick` 13/13, `capability-entropy.py --check`
PASS (1623 ≤ 1623), `roadmap.sh validate` PASS.

## Specs con todos los AC cubiertos (pendientes solo de revisión humana)

### SE-404 — Proceso proporcional (PR #1170, ampliada en #1336)

| AC | Evidencia | Autoridad (obtenida / requerida) |
|---|---|---|
| AC1 | `tests/structure/test-se404-g13-v2.bats` 1–2 | simulada / simulada |
| AC2 | ídem 3, 6–10 (incluye negativos) | simulada / simulada |
| AC3 | ídem 11 | simulada / simulada |
| AC4 | ídem 12 | simulada / simulada |
| AC5 | ídem 13 | simulada / simulada |
| AC6 | ídem 14 | simulada / simulada |
| AC7 | `tests/test-se404-court-one-fix.bats` 2–3 | estatica / estatica |
| AC8 | ídem 4–6 | simulada / simulada |
| AC9 | 21/21 y 8/8 BATS; auditor 89 y 84 | simulada / simulada |

Matiz: la spec es L3 y pide revisión humana explícita del PR antes del merge (SE-362); #1170 se fusionó sin revisión
registrada. La revisión humana del cierre debe cubrirlo.

### SE-426 — Firma de confidencialidad con HMAC (PRs #1224, #1225, #1337)

| AC | Evidencia | Autoridad |
|---|---|---|
| AC1–AC4 | `tests/scripts/test-confidentiality-sign.bats` 36/36, auditor 85 | simulada / simulada |
| AC5 (rechazo) | Run real 39504031706 (2026-10-20): «Verify Audit Signature» con `CONFIDENTIALITY_REQUIRE_HMAC=1` falla con `ERROR: HMAC mismatch.` | real / real |
| AC5 (re-firmado del bot) | PR #1345, head 1f073ad12 re-firmado por `github-actions[bot]` (auto-rebase 2026-10-23): run 39903878046, `HMAC: VERIFIED`. Igual en #1346 y #1347 | real / real |
| AC6 | 36/36 BATS (≥27), auditor 85 | simulada / simulada |

Era lo único que faltaba según la nota de planning-state («observar el re-firmado del bot»).

### SE-442 — Cadena de suministro de la CI (PR #1332)

| AC | Evidencia | Autoridad |
|---|---|---|
| AC1 | `tests/test-ci-actions-pinned.bats` 1 (10/10) | estatica / estatica |
| AC2 | ídem 2–3, 5 | simulada / simulada |
| AC3 | grep del spec sobre `.github/workflows`: 0 líneas | estatica / estatica |
| AC4 | `.github/dependabot.yml` válido; github-actions, weekly, grupo `*` | estatica / estatica |
| AC5 | YAML válido (test 8–9). CodeQL corrió en la rama del PR (run 39498696379) y en main (39903767248). Scorecard corre en main con «Upload SARIF» (39903767015) | simulada / real (insuficiente: el AC pide Scorecard en el PR) |
| AC6 | `SECURITY.md`: 3 secciones | estatica / estatica |
| AC7 | `validate-ci-local.sh --quick` 13/13 | real / real |
| AC8 | `tests/test-requirements-hashed.bats` 1, 3; lock con hashes | estatica / estatica |
| AC9 | ídem 2, 4 (4/4) | simulada / simulada |

Matiz en AC5: el texto pide que ambos jobs se ejecuten «en el PR». Scorecard no corrió en la rama del PR
(la acción solo analiza la rama por defecto); se verificó en main tras el merge. La operadora decide si lo acepta.
#1346 (abierta) triagea alertas de code scanning: mejora posterior, no un AC.

### SE-444 — Autoridad del verificador (PR #1334)

| AC | Evidencia | Autoridad |
|---|---|---|
| AC1 | `docs/rules/domain/ac-verifier-authority.md` | estatica / estatica |
| AC2 | plantilla: `autoridad_requerida` y «Autorizaciones literales»; test 8 | estatica / estatica |
| AC3 | `tests/test-planning-completion-authority.bats` 1–4 | simulada / simulada |
| AC4 | ídem 5 | simulada / simulada |
| AC5 | ídem 6–7; ejecución real: sección impresa y exit 0 | real / real |
| AC6 | `roadmap.sh validate` PASS | real / real |
| AC7 | entropía PASS | real / real |

### SE-445 — Salvaguardas de ejecución autónoma (PR #1335)

| AC | Evidencia | Autoridad |
|---|---|---|
| AC1 | `tests/test-repeat-tool-guard-block.bats` 1–6 (16/16) | simulada / simulada |
| AC2 | ídem 7–9 | simulada / simulada |
| AC3 | `tests/test-turn-budget-inject.bats` 1–4 (7/7) | simulada / simulada |
| AC4 | `tests/test-action-review.bats` 1–3 (26/26) | simulada / simulada |
| AC5 | ídem 4–9 | simulada / simulada |
| AC6 | ídem 10–12 | simulada / simulada |
| AC7 | `tests/test-automation-success-checks.bats` (10/10) | simulada / simulada |
| AC8 | `tests/test-action-review.bats` 13–15 | simulada / simulada |
| AC9 | `validate-ci-local.sh --quick` verde; entropía PASS | real / real |

### SE-451 — DCO (PR #1331)

| AC | Evidencia | Autoridad |
|---|---|---|
| AC1 | `CONTRIBUTING.md` (Signed-off-by y DCO); test 12 | estatica / estatica |
| AC2 | `tests/test-dco-check.bats` 1–9, 13–14 (14/14), extrae el script del YAML | simulada / simulada |
| AC3 | ídem 10; grep sin `actions/checkout` ni `pull_request_target` | estatica / estatica |
| AC4 | ídem 11 | estatica / estatica |
| AC5 | No aplica: D1 = DCO | — |
| AC6 | No aplica: S4 (REUSE) no se hizo y el AC es condicional | — |
| AC7 | `validate-ci-local.sh --quick` verde | real / real |

## Specs con AC sin cubrir (se quedan como están)

| Spec | Qué falta |
|---|---|
| SE-403 | AC4 falla en uso real: `dirty` cuenta `results/` versionado y toda ejecución tras la primera sale sucia, así que nunca entra en la frontera. El arreglo es #1345 (abierta). Los 15 BATS pasan porque usan un repo de fixture. Graduar después de fusionar #1345. |
| SE-453 | AC1–AC10 pasan en main (21/21 y 21/21 BATS), pero el protocolo DUAL_BINDING de S2 (paridad OpenCode de los guards) no estaba hecho y el puerto TS de `block-force-push` diverge en 3 casos. Lo cierra #1348 (abierta). |
| SE-433 | v1/v2/v3 cubren grant, parser, manifiesto, CI roja, desfase y ledger (33 BATS). No hay implementación de: el juez y su prefiltro (AC-11, AC-12), `required_checks` vivos (AC-16), `runner_blob`/`classifier_blob` (AC-17), anomalías de base y repo (AC-18), vuelta a Draft (AC-22), omisión en auto-rebase por etiqueta (AC-23), reservas F5 y recuperación (AC-25, AC-26) ni permisos OpenCode (AC-29). AC-28 (BATS que cubre AC-01..27) no se cumple. |

## Specs no candidatas (el propio registro declara trabajo pendiente)

SE-376 (deuda 121/137), SE-392 (equivalencia y E2E sin demostrar), SE-395 (experimento adaptativo pendiente),
SE-396 (H04 y H09 requieren ejecución real y cotejo humano), SE-398/399/400 (F1+ bloqueadas por revisión de F0),
SE-428/429/430/431/432/434/435/436/439 (Savia Space, en curso o sin empezar). No se revisaron AC por AC.
