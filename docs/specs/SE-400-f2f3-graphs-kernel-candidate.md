---
id: SE-400-F2F3
parent: SE-400
status: READY_FOR_HUMAN_REVIEW
created: 2026-10-24
evidence_type: deterministic-repository-inventory + isolated-snapshot-experiment
model_invocations: 0
---

# SE-400 F2 (resto) + F3 — Grafos y kernel candidato aislado

## Qué entrega

| Pieza | Ruta |
|---|---|
| Grafos F2: dependencias tipadas, matriz evento→hook→fallo, enlaces de contrato | `scripts/ablation_graphs.py {generate,check,summary}` |
| Kernel candidato (hipótesis versionada, 0.2.0) | `config/kernel-candidate.json` |
| Golden Kernel Corpus (18 casos deterministas + 5 no verificados) | `config/kernel-corpus.json` |
| Experimento F3 y receipt | `scripts/ablation_kernel.py {plan,run}` |
| Tests | `tests/test_ablation_kernel.py` (fixtures), `tests/test-se400-ablation-f2f3.bats` (repo real) |
| Informes regenerables (no versionados) | `output/ablation/f2-graphs.{json,md}`, `output/ablation/f3-kernel-receipt.{json,md}` |

## F2 — grafos

Aristas dirigidas que salen de código o de frontmatter declarado, no de
menciones (eso ya lo cubre el grafo de consumidores de F1):

| Relación | Origen | Aristas |
|---|---|---:|
| `SOURCES` | `source`/`.` de bash resuelto contra el árbol | 156 |
| `INVOKES` | `bash|python3 scripts/x`, `.opencode|.claude/hooks/x` | 246 |
| `IMPORTS` | `import`/`from` resuelto a `scripts/x.py` | 47 |
| `DECLARES_SKILL` | `skills:` en agents/commands | 35 |
| `DELEGATES_TO` | `agent:` en commands | 43 |
| `USES_DECISION_TREE` | `decision_tree:` en agents | 9 |
| `REGISTERED_AT` | evento de settings → hook | 129 |

Matriz evento→hook→fallo: 132 registros en 17 eventos; 43 pueden bloquear
(`exit 2` o decisión `deny`/`block`), 42 de ellos son fail-open ante caída o
timeout (semántica del runtime: solo `exit 2` bloquea). Los 9 hooks con
`profile_gate "security"` son la única autoridad en código para enlazar un
control con una dimensión del contrato (`security_floors`); el resto queda sin
enlace en vez de inventarlo.

Hallazgos deterministas (entrada para humanos, no cambios):

1. `agents-md-auto-regenerate.sh` declara `profile_gate "automation"`, un tier
   que `profile-gate.sh` no conoce: en los perfiles `standard`, `ci` y
   `minimal` sale con 0 sin hacer nada. Solo corre en `strict`.
2. `agent-git-discipline.sh` está registrado dos veces en `PreToolUse/Bash`.
3. `/dag-execute` y `/perf-fix` delegan en `agent: developer`, que no existe.
4. Un hook `type: prompt` (commit) depende de modelo: no determinista.
5. Cinco puntos de interceptación con 2–10 hooks bloqueantes compartidos
   (`PreToolUse/Edit|Write` tiene 10, `PreToolUse/Bash` 9). Solape, no redundancia: la independencia de
   modos de fallo se mide con ablación, no con este recuento.

`repeat-tool-guard.sh` sale con `ASYNC_CANNOT_BLOCK` en su registro
`PostToolUse` asíncrono; bloquea en su registro `PreToolUse`, así que no es un
defecto.

## F3 — kernel candidato

`plan` calcula el cierre de dependencias de las semillas sobre las aristas F2
ejecutables y declaradas y marca las dependencias de packs no permitidos.
`run` materializa dos snapshots del mismo árbol en un directorio temporal
fuera del repo (lo rechaza dentro: `DEST_NOT_ISOLATED`), los convierte en
repos git en `agent/kernel-probe`, aísla `HOME`, proyecta `settings.json` del
kernel a sus hooks y despacha cada caso con la semántica de eventos y
matchers de settings. Comparten snapshot, fixtures, entrada y perfil de hooks
(`standard`). Los secretos del corpus son marcadores que se montan en
ejecución: ningún fichero versionado contiene el literal.

Regla de decisión, fijada antes de correr: un `FALSE_ALLOW` aborta
(`ABORT_FALSE_ALLOW`); si el control no cumple lo esperado, `INCONCLUSIVE`;
falso bloqueo o regresión de un `exec`, `KERNEL_INSUFFICIENT`; todo igual,
`KERNEL_PRESERVES_CORPUS`. El runner termina todos los casos tras un falso
allow para conservar el vector: en un snapshot aislado no hay efectos.

### Resultado medido

Árbol `266cd14d9` (rama sobre main `cca5c5771`).

| Candidato | Decisión | Veredictos |
|---|---|---|
| 0.1.0 | `ABORT_FALSE_ALLOW` | 16 MATCH, 1 FALSE_ALLOW (`governed-write-secret`), 1 REGRESSION |
| 0.2.0 (+`data-sovereignty-gate.sh`) | `KERNEL_INSUFFICIENT` | 17 MATCH, 1 REGRESSION (`architecture-query`) |

| Medida (0.2.0) | SAVIA_FULL | KERNEL |
|---|---:|---:|
| Ficheros | 7.411 | 29 |
| Scripts | 1.288 | 7 |
| Registros de hook | 132 | 8 |
| Registros que pueden bloquear | 43 | 8 |
| Procesos de hook en el corpus | 242 | 57 |

Lecturas:

1. **El experimento detecta un falso allow real.** Con solo
   `block-credential-leak.sh`, un secreto escrito con `Write` pasa: ese guard
   mira Bash. El floor de secretos necesita también `data-sovereignty-gate.sh`.
2. **La verdad arquitectónica no cabe en un kernel reducido.** `sam.py query`
   valida la procedencia del modelo contra el árbol entero y falla con
   `INVALID_MODEL` en cuanto falta un command. El SAM es una vista de FULL; un
   kernel necesita un SAM con alcance propio o una consulta que no exija toda
   la procedencia. Decisión humana.
3. **Dependencia accidental de pack.** `autonomous-safety.md` (Human Gates)
   figura en `rule_refs` del pack `pm-sdd-legacy`. O la regla es del kernel y
   el registry está mal, o el kernel depende de un pack legacy.
4. 8 de 132 registros de hook reproducen todos los casos bloqueantes del
   corpus. No prueba que los otros 124 sobren: el corpus es una muestra, y
   cada hook ausente necesita su propia preregistración A0/A2 (F4).

## Acceptance Criteria

| AC | Estado | Verificación |
|---|---|---|
| AC01 baseline sin modelo | Cerrado también en candidato y corpus | `test_corpus_rejects_model_as_baseline`; `model_invocations: 0` |
| AC04 deterministic-first | Cerrado para F3 | cero modelo; hooks `prompt`/async como `NOT_EVALUATED` |
| AC05 preregistro | Parcial | regla de decisión y corpus versionados antes de correr; sin preregistro por unidad (F4) |
| AC06 controles pareados | Cerrado para F3 | mismo snapshot, entrada y perfil; `test_kernel_without_blocker_yields_false_allow_end_to_end` |
| AC07 resultados negativos | Cerrado | 0.1.0 (abort) y 0.2.0 (insuficiente) documentados |
| AC08 evidencia en HEAD | Cerrado para F2/F3 | `f2 check` STALE por contenido; receipt liga contrato, candidato, corpus, superficie, SAM y SCM |
| AC20 kernel sin dependencia accidental de packs | Medido, abierto | `plan` detecta `autonomous-safety.md` → `pm-sdd-legacy`; requiere decisión humana |
| AC31 cero false allows | Cerrado para 0.2.0 sobre el corpus | BATS `zero false allows`; 0.1.0 abortó como debe |
| AC33 Human Gate preservado | Cerrado sobre el corpus | `human-gate-commit-main`, `human-gate-lease-main` MATCH |
| AC34 UNKNOWN nunca delete | Sin cambio | el receipt no clasifica essentiality (`NO_ESSENTIALITY_CLASSIFICATION_FROM_THIS_RECEIPT`) |
| AC36 defense-in-depth medido | Parcial | grupos de interceptación compartida; falta la ablación por modo de fallo |
| AC38 kernel candidate ejecutado | Cerrado | `ablation_kernel.py run` sobre el repo |
| AC39–40 recursos/edges/hooks medidos | Cerrado (estático + corpus) | vector FULL/KERNEL y grafos F2 |
| AC03, AC09–19, AC21–30, AC32, AC35, AC37, AC41–46 | Abiertos o sin cambio | requieren A0–A6 por unidad, panel de modelos, packs o projections (F4+) |

## Limitaciones

- Despachador simulado, no runtime vivo. MCP, adapters, receipts de efectos y
  recuperación tras reinicio quedan `NOT_VERIFIED` en el corpus.
- Aristas estáticas: el dispatch dinámico (rutas construidas en ejecución,
  como la validación de procedencia del SAM) no aparece; el experimento F3 es
  lo que lo destapa.
- `blocking_capable` se lee del código, no se observa.

## Siguiente

Decisiones humanas: (1) SAM con alcance de kernel o consulta sin procedencia
completa, (2) propietario de `autonomous-safety.md` (kernel o pack), (3) tier
`automation` de `agents-md-auto-regenerate.sh`, (4) `agent: developer`.
Después, F4: preregistro A0/A2 por hook del grupo `PreToolUse/Bash`.
