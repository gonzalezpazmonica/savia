# Repriorización del 2026-11-09 — evidencia y decisiones pendientes

Base: `main` `e59b795ee`. Método: lectura estática de specs, scripts, hooks y `git log`. No se ejecutó ninguna suite ni script del repo. Cada afirmación va marcada **O** (observado en código o PR), **I** (inferido) o **NV** (no verificado).

Origen: tesis Savia Viva R6 «Aprendizaje exigible por dominio» (original e informe en Savia Labs) y petición de la operadora de repriorizar y podar todo el roadmap.

## 1. Estado de la cola antes del cambio

- 132 iniciativas en la vista: 63 APPROVED, 26 PROPOSED, 17 DEFERRED, 22 IMPLEMENTED y 4 IMPLEMENTING (límite 4). **O**
- 63 iniciativas activas no estaban en ninguna sesión de la cola: todas las SE-455 en adelante, todo Savia Space, SE-490 y SE-504. La última enmienda de la cola era del 2026-10-27. **O**
- Las sesiones S01 y S02 seguían en cola con la acción «Hecho». **O**

## 2. Lo que la tesis afirma y lo que dice el código

| Afirmación de la tesis | Resultado |
|---|---|
| El orquestador pide el recall en modo `shadow` y solo cuenta hits | **O** `scripts/savia-orchestrator.sh:69` |
| Mide `L` con valores fijos si no recibe datos | **O** `scripts/savia-orchestrator.sh:120-125` |
| `--human-trailer` es una cadena libre | **O** `scripts/learning-lifecycle.sh:55,95`; ya lo recogía SE-497 |
| El aprendizaje autorizado no llega a guiar la acción | **Matizado.** El recall efectivo sí está cableado: hook `learning-recall-hook.sh` en UserPromptSubmit y guard `learning-recall-guard.ts` en OpenCode, hasta tres criterios. Pero solo CRIT-001 es `human_authored`, así que entrega un único principio (**I**: el log guarda el número de hits, no cuál). No hay prueba de entrega ni consulta en el punto de decisión. **O** |
| El simulador previo a la acción usa constantes | **O** `scripts/world-model-simulator.py:30-70,186`. Además nadie lo invoca fuera de sus tests, ni a `actor-pre-action-loop.py`. **O** |

Otros hallazgos:

- Las LP no tienen dominio, tipo de acción ni verificador (`scripts/learning-proposal.sh:158-170`). El campo `enforcement:` de `CRITERIO.md` es texto libre sin consumidor encontrado (**NV** exhaustivo). **O**
- `learning-autonomy.sh` (SCL-006) solo lo consume el orquestador como informe; nadie aplica el nivel. **O**
- `scripts/agent-messaging.sh` (SE-347) escribe ledger e inbox en JSONL separados, sin cerrojo ni transacción. `scripts/lib/task-queue.py` (SE-075) usa SQLite en autocommit; transacción entre admisión y salida **NV**.
- Recuento de `output/learning-loop/recall.jsonl` (725 filas): 487 efectivas con hit, 139 efectivas sin hit, 56 sombra, 43 de formato antiguo. **O**

## 3. Cobertura de rutas de efecto (Claude Code; lectura de `.claude/settings.json`)

| Efecto | Control previo determinista | Rutas sin control |
|---|---|---|
| Write / Edit | Varios hooks en `Edit\|Write` y `operator-grant.sh guard` | Escritura por Bash (**NV** alcance). En OpenCode faltan los pares de plan-gate, blast-radius, responsibility-judge y mind-virus (**O**: listado del directorio) |
| Bash | validate-bash-global, block-credential-leak, block-infra-destructive, agent-git-discipline | — |
| git commit | block-commit-to-main, compliance-gate, `.githooks/pre-commit` | `--no-verify` (**I**) |
| git push | block-force-push, agent-git-discipline, `scripts/push-pr.sh` | No hay hook pre-push; push directo sin `push-pr.sh` (**I**) |
| Crear PR | pr-summary-gate, `push-pr.sh` | `gh api` directo (**I**) |
| Merge de PR | `push-pr.sh --merge` (grant y escáner), `merge-sprint.sh` | Otras formas de merge **NV** |
| MCP con escritura | **Ninguno** | Todas las llamadas `mcp__*` (**O**). Lo cubre SE-508, PROPOSED |
| WebFetch | **Ninguno** | Todas (**O**). SE-508 |
| Ejecutor externo (Yema, Codex) | Guards de `Agent\|Task`; `action-review.sh` es opt-in y sale 0 por defecto | El ejecutor corre fuera de los hooks del frontend (**I**) |

Ningún hook de esta tabla consulta lecciones ni criterios (**O** por nombres; **NV** en el cuerpo de `require-criterion-cite.ts`).

## 4. Podas aplicadas en esta PR

| Spec | Cambio | Motivo |
|---|---|---|
| SE-406 | DEFERRED → SUPERSEDED | Su propia cabecera dice que el Relay va por la app de Space (SE-431 D3, SE-430). Sin dependientes |
| SE-381 | DEFERRED → SUPERSEDED | Matriz de solo informe en main (#1084); el gate de bloqueo pendiente es el objeto de SE-468 |
| SE-475 | PROPOSED → SUPERSEDED | SE-510 D2 registra cada bloqueo de los mismos hooks; la clase FORMA o POLÍTICA pasa a ser un campo suyo |

Enmiendas propuestas, sin cambio de estado, al final de cada spec: SE-386, SE-395, SE-401, SE-409, SE-459, SE-460, SE-468, SE-472, SE-473, SE-482, SE-497, SE-507, SE-510, SE-512, SCL-003, SCL-006 y SCL-011. La más importante: SE-473 y SE-497 R7 pedían casi los mismos campos de lección con nombres distintos y no se citaban; SE-473 queda como dueña del esquema.

## 5. Candidatas a graduación (sesión S27)

Artefactos y PRs presentes en main. Evidencia de existencia, no de cada AC: la graduación exige revisión humana.

| Spec | Evidencia | Nota |
|---|---|---|
| SE-442 | 0 de 77 `uses:` sin SHA; dependabot, codeql, scorecard, tests | AC5 y AC8 **NV** |
| SE-444 | #1334; regla, tests y «Cobertura no verificada» en validate-ci-local | — |
| SE-445 | Tres hooks, política y cuatro tests | AC1–AC9 **NV** |
| SE-451 | Workflow y test de DCO, CONTRIBUTING | S4 (REUSE) **NV** |
| SE-453 | #1333, #1348, #1355, #1374, #1385; evidencia S0 y S4 | Slice abierto **NV** |
| SE-433 | `merge-sprint.sh` y tests (#1289) | Lo abierto es SE-500 |
| SE-403, SE-404 | #1171; #1170 y #1336 | Solo falta revisión humana |
| SE-455, SE-457 | #1358; #1361 | — |
| SE-456 | #1350 | S5 es cola de reparación (**I**) |
| SE-468 | #1397 | S3 (sabotaje) **NV** |
| SE-471 | #1486, script y tests | — |
| SE-480, SE-481, SE-485 | #1418, #1419, #1427 | — |
| SE-483, SE-484, SE-487 | #1425; #1424; #1428 y #1429 | — |
| SE-395 | #1122, #1131, #1372, #1382 | Lo pendiente pasa a SE-489 |
| SE-378, SE-387 | #1085; #1099 y #1104 | Paraguas con cierre humano pendiente |

Parciales que siguen abiertas (sesión S32): SE-489 (M0–M7, #1432–#1439), SE-500 (S1–S2), SE-501, SE-470 (S2), SE-490 (#1440–#1447).

## 6. Decisiones de la operadora (2026-11-09, preguntas interactivas)

Todas por pregunta interactiva en la sesión de la orquestadora; las respuestas literales están en cada spec y en `LOG.d/`. Se formalizan al fusionar la PR (SE-488).

**Aprobadas**, alcance elegido «Savia Viva + tokens y efectos»:

| Spec | Escenas | Nota |
|---|---|---|
| SE-513, SE-514 | Confirmadas | Prototipo S0 pendiente antes de S1 |
| SE-515 | No aplica (`human_surface: false`, sale como DECLARED-FALSE para la revisora) | Cada slice desde S1 se aprueba aparte, según la spec |
| SE-508, SE-510 | Confirmadas | Prototipo S0 pendiente; SE-508 arranca en observación |
| SE-511 | Confirmadas | Recorte condicionado: la medición empieza ya, el recorte espera a la validación con el método de EXP-509, que se cortó por cuota sin resultados |
| SE-493, SE-496, SE-498 | Redactadas hoy y confirmadas | No declaraban `human_surface`; tienen momentos en que la persona actúa (resolver un efecto dudoso, firmar un contrato, parar y reanudar), así que se declaró `true` y se le enseñaron escenas en vez de autoexentarlas |

En «Palabras de la persona» se citan frases del mensaje de la operadora del 2026-11-09 o su respuesta de alcance; en SE-510 se dice expresamente que la cita trata de tokens, no de guardas.

**Podas aplicadas:**

| Spec | Cambio | Motivo |
|---|---|---|
| SE-377 | SUPERSEDED | Gate pendiente a SE-453 y SE-454 (**I**) |
| SE-386 | SUPERSEDED | F5 a SE-496; F1–F2 en main (#1090); F3–F4 se abandonan |
| SE-390 | SUPERSEDED | Identidad y documentación en SE-483 y SE-484 (**I**) |
| SE-394 | SUPERSEDED | Sin entregables propios ni dependientes |
| SE-502 | DEFERRED | Hasta tener SE-493, SE-496 y SE-498 implementadas y la herramienta de modelado |
| SE-506 | DEFERRED | Sin dependientes; depende de SE-449 sin implementar |
| SE-472 | Condicionada en la cola | Se retira si `overnight-sprint-loop.sh` ya no se usa (**NV**) |

**Siguen abiertas, sin decisión:** SE-389 y SE-385 (aparcadas, nadie depende de ellas), SE-397 (graduar F1–F5A y abrir F6–F10), SE-388 (comprobar si su P3 ya lo cubre SE-392 S3), retirar o etiquetar `world-model-simulator.py` y `actor-pre-action-loop.py` (se decide en SE-515 S0), SE-512 (aprobar por el camino de SE-488).

## 7. Límites de este informe

- Nada se ejecutó: los recuentos salen de `grep`, `jq` y `git log`.
- No se leyó el repo privado de Space; lo que se dice de SE-428 a SE-439, SE-490 y SE-504 sale de sus specs y de PRs de este repo.
- El estado por ciclo de vida de las 47 LP de la cúpula de aprendizaje no se desglosó.
- Las sondas P0–P15 de la tesis no se han diseñado; son el slice S0 de SE-513, SE-514 y SE-515.
