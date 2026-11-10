# SE-515 S0 — Auditoría y línea base (solo lectura)

Spec: `docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md` (APPROVED 2026-11-09, cubre la spec y S0). Punto de partida: `docs/evidence/planning-repriorization-20261109.md` §2–3.

**Commit leído:** `9c3284e9898e880da600c92ae437856f28b5c37f` (`origin/main`, 2026-11-10). Todo lo citado como ruta:línea se leyó en ese árbol. La spec y el informe previo se contrastaron contra `e59b795ee`; entre ambos solo cambió documentación de roadmap.

**Método y límites.** Lectura estática con `grep`, `sed` y `git`. No se ejecutó ningún hook, script de recall ni suite; no se instrumentó nada. Marcas: **O** observado en código o fichero; **I** inferido de lo observado; **NV** no verificado. La cúpula privada SaviaLearning y el log local `output/learning-loop/recall.jsonl` no existen en este árbol (`output/learning-loop/` no existe; `vaults/` tampoco), así que ninguna cifra de ellos se recalcula aquí: las 725 filas del informe previo siguen siendo de segunda mano (**NV** en esta sesión).

**Fixtures.** S0 no crea fixtures ejecutables (prohibido añadir más de un fichero). Los hashes que S1 debe congelar son los de los ficheros citados en la sección 5, a calcular con `git rev-parse <commit>:<ruta>` al abrir S1; aquí solo se fija el commit raíz.

## 1. Matriz de cobertura por clase de efecto (AC-1)

Claude Code = `.claude/settings.json`; los scripts viven en `.opencode/hooks/` salvo los marcados `.claude/hooks/`. OpenCode = `.opencode/plugins/savia-foundation.ts` con `BEFORE_GUARDS` (`:68-92`) y `AFTER_GUARDS` (`:94-104`). `permissions` en settings solo fija `defaultMode: "auto"`, sin listas allow/deny (`.claude/settings.json:1241-1243`, **O**).

Reglas comunes de fallo, **O**:
- Hooks bash PreToolUse: bloquean con `exit 2`. `block-force-push.sh:22-23` sale 2 si no puede extraer el comando; `validate-bash-global.sh` bloquea con «fail-closed» ante un destino de commit dudoso (lo vi en esta sesión). Pero `permission-mode-gate.sh:23,39` sale 0 si el modo no es `read-only` o la entrada está vacía (fail-soft declarado en `:16`).
- Guards TS: bloquean lanzando `Error` (`validate-bash-global.ts:70`). Los guards de después (`runAfterGuards`, `savia-foundation.ts:109-117`) tragan los errores a propósito: no bloquean nunca.
- El perfil `SAVIA_HOOK_PROFILE=minimal` salta todo hook que no sea de nivel `security` (`lib/profile-gate.sh:10,26-29`). Qué hooks declaran `security` y cuáles no: **NV** completo; `block-force-push.sh:5-6` sí.

| Clase de efecto | Claude Code: control previo (settings:línea) | ¿Falla cerrado? | Rutas que lo esquivan | OpenCode (plugin:línea) | Estado en OpenCode |
|---|---|---|---|---|---|
| Write / Edit | `memory-verified-gate`, `tdd-gate`, `plan-gate` (`:241`), `data-sovereignty-gate`, `block-gitignored-references`, `responsibility-judge`, `blast-radius-hook`, `block-pat-file-write`, `mind-virus-write-gate`, `config-snapshot-hook`; `operator-grant.sh guard` (`:569`); `permission-mode-gate` (`:301`) | Los de seguridad sí (exit 2). `permission-mode-gate` y los hooks con `profile_gate` no (**O**) | Escritura por Bash (`echo >`, `tee`, `sed -i`): los hooks de Edit/Write no ven el comando. `operator-grant.sh guard` sí cubre Bash (`:569`); cuánta escritura cubre: **NV**. `SAVIA_HOOK_PROFILE=minimal` (**O**) | `dataSovereigntyGate`, `blockGitignoredReferences`, `tddGate`, `configSnapshot` (`:72-91`) | Sin par: plan-gate, blast-radius, responsibility-judge, mind-virus, block-pat-file-write, memory-verified-gate (**O**, no están en `BEFORE_GUARDS` ni en `guards/`) |
| Bash | `validate-bash-global` (`:124`), `block-credential-leak`, `block-infra-destructive`, `agent-git-discipline` (`:103,117`), `agent-hook-premerge` (`:313`), `dome-guard` (`:493,497`) | Sí en los de seguridad (**O**) | Orden envuelta en shell no reconocido por la gramática del regex (**I**: ya hay un parche de `bwrap` en `lib/sandbox.ts:15-30`, que cubre un caso y no los demás). Perfil `minimal` | `validateBashGlobal`, `blockCredentialLeak`, `blockInfraDestructive`, `blockBranchSwitchDirty` (`:70-79`) y `runGuardsOnVariants` (`lib/sandbox.ts:32-43`) | Par para casi todos; falta `agent-git-discipline` y `agent-hook-premerge` (**O**) |
| Commit | `block-commit-to-main` (`:155`), `compliance-gate` (`:149`), hook `prompt` semántico de mensaje en `Bash(git commit*)` (`:411-419`), `.githooks/pre-commit` | Hooks bash sí. El hook `prompt` es de calidad, no de seguridad | `git commit --no-verify` (**I**); `core.hooksPath` sin fijar en este worktree: `git config core.hooksPath` salió vacío (**O**), así que `.githooks/pre-commit` solo corre si la instalación lo activa (**NV** en otras máquinas) | `blockCommitToMain` (`:76`) | Par parcial: sin `compliance-gate` ni el hook semántico (**O**) |
| Push | `block-force-push` (`:90`), `agent-git-discipline` (`:103,117`; revisa `push --delete` en `:135-159`) | Sí. No hay `.githooks/pre-push`: `ls .githooks` solo muestra `pre-commit` (**O**) | `git push` directo a una rama `agent/*` sin pasar por `push-pr.sh`: ningún hook lo exige (**I**, no hay regla que lo imponga en lo leído). `scripts/push-pr.sh:82` reintenta con `--force-with-lease` si el push normal falla (**O**) | `blockForcePush` (`:73`) | Par (SE-453 S2 declara paridad, `block-force-push.ts:1-10`; no se re-probó aquí) |
| Crear PR | `pr-summary-gate` (`:72`), `push-pr.sh` (pasos 0–6, `push-pr.sh:40-176`); aviso post-hecho `fronesis-gate-reminder` | `push-pr.sh` sí (`set -euo pipefail`, `:6`; escáner con `SAVIA_GATE_UNKNOWN=block`, `:78`). El aviso post no bloquea | `gh pr create` o `gh api` directo (**I**). Paso 0 se salta con `touch .pr-plan-ok` (`push-pr.sh:43-45`, **O**) | Ninguno específico (**O**: no hay guard de `gh`) | Sin par de `pr-summary-gate` |
| Merge de PR | `push-pr.sh --merge` (`:178-400`): grant firmado para la cabeza (`:344-371`), escáner contra `origin/main` (`:301-304`), `--match-head-commit` (`:397`), sin `--auto` (`:392-395`); `merge-sprint.sh` | Sí: cada rama de error sale 1 (**O**) | `gh pr merge` directo: ningún hook lo bloquea en lo leído (**NV** exhaustivo); `operator-grant.sh guard` en Bash (`:569`) puede cubrirlo, no verificado | Ninguno | Sin par |
| MCP con escritura | **Ninguno previo.** Solo `twin-posttooluse` (PostToolUse `mcp__.*`, `:883-890`, no-op sin `TWIN_HOOK_ENABLED`) | No aplica | Todas las llamadas `mcp__*` (**O**). `savia-budget-guard` (`:426`, matcher `*`) y `repeat-tool-guard` (`.*`) las ven pero son de presupuesto/bucles, no de efecto | Ninguno | Sin par. SE-508 está **APPROVED** (`docs/specs/SE-508-...spec.md:2`), no PROPOSED como decía el informe previo; sigue sin implementar (**O**: no hay matcher `mcp__` PreToolUse) |
| WebFetch | **Ninguno previo.** `context-drop-after-use` y `judge-auto-router` actúan tras la llamada (`:739,893`) | No aplica | Todas | `contextDropAfterUse` solo en After | Sin par |
| Ejecutor externo (Yema, Codex) | `recursion-guard` (`:61`), `agent-dispatch-validate`, `delegation-guard` (`:384`), `protected-job-guard` (`:405`) sobre `Agent\|Task`; `action-review` (`:558`) solo Bash | `action-review.sh:15-16` sale 0 sin doble opt-in (**O**); con opt-in y sin python sale 2 en tiers 3/4 (`:25`) | El ejecutor corre como proceso aparte con sus propios sandbox y hooks: nada del frontend lo intercepta una vez lanzado (**I**). Lanzarlo desde Bash pasa por los hooks de Bash; lanzarlo desde un script, no | `dispatchTrace` y `subagentAudienceFilter` (no bloquean, `:85-88`) | Sin guard bloqueante |

**NV cerrados leyendo código:**
- «SE-508 PROPOSED» → es APPROVED (O).
- «Hay hook pre-push» → no existe (`.githooks` solo tiene `pre-commit`) (O).
- «`require-criterion-cite.ts` consulta lecciones» → **NV sigue abierto**: el fichero existe en `.opencode/plugins/guards/` pero no está en `BEFORE_GUARDS`, y no lo leí entero. No afecta a las conclusiones: si no está registrado, no corre.
- «`enforcement:` sin consumidor» → matiz: `scripts/corporate-adopt.sh:117,126` lo lee y lo imprime; no lo evalúa (O). Sigue sin ser un control.

**NV que quedan abiertos:** alcance real de escritura por Bash; `gh pr merge` directo; qué hooks son de nivel `security`; comportamiento real de cada hook con entrada vacía o con herramienta ausente (solo se leyó `block-force-push.sh`, `action-review.sh`, `permission-mode-gate.sh`).

**Conclusión de la matriz (I):** ningún efecto tiene hoy un control previo que consulte lecciones. Las dos clases sin control previo alguno (MCP, WebFetch) son exactamente las que SE-508 cubrirá; el resto tiene control, con rutas de rodeo conocidas.

## 2. Recall: qué registra hoy y por qué no se desglosa por criterio

**Cadena (O):**
1. `learning-recall-hook.sh` (UserPromptSubmit, `settings.json:1047`, timeout 5000) o `learning-recall-guard.ts` (`chat.message`, `savia-foundation.ts:189-195`; en V2, evento `prompt` de sesión, `:155-161`) llaman a `scripts/learning-recall.sh --mode effective --top 3 --min-score 10 --json`.
2. El script busca en la cúpula con el CLI de vaults, lee cada nota candidata y lee `CRITERIO.md` (`learning-recall.sh:46,54,107-178`). Una nota es elegible solo si `target=criterio`, `lifecycle=active`, `provenance=human_authored` y su `criterion_id` existe con la misma procedencia (`:163`).
3. Escribe una fila en `output/learning-loop/recall.jsonl` (`:183-189`) con: `ts`, `query_hash`, `mode`, `effective_hits` (número), `shadow_hits` (número), `rejected_hits` (número) y `proposal_ids` (lista).
4. El hook y el guard inyectan `## Criterios humanos aplicables` con hasta tres criterios (`hook:35-45`; `guard:93-107`).

**Qué sabe el log (O):** cuántos aciertos hubo y los ids de las propuestas leídas. **Qué no sabe:**
- `proposal_ids` se rellena con toda nota leída con `id`, antes de filtrar (`:153-154`). Incluye notas rechazadas y de sombra. No dice cuáles se emitieron.
- El `criterion_id` emitido **no se guarda**. Lo único que lo ata a una fila sería cruzar `proposal_ids` con la cúpula (privada), y aun así no distingue la nota emitida de la rechazada. Por eso no se puede desglosar por criterio sin instrumentar (**I**, a partir de `:178,187`).
- El log lo escribe el script, no el hook: si el hook vence su `timeout 4` (`hook:30`) o el script sale ≠0, hay `exit 0` sin fila (**O**).
- Salidas sin fila (**O**): `learning-recall.sh:46` y `:54` salen 3 si falta la cúpula, `CRITERIO.md`, node o el CLI; el hook las convierte en `exit 0` (`hook:30`). En este árbol faltan la cúpula y `output/`, así que aquí cada prompt saldría sin fila ni inyección. El guard TS también traga timeout, error y JSON roto con `resolve([])` (`guard:47,55,60`).
- Un fallo del volcado de la fila no se ve: `2>/dev/null || true` (`:184`).
- La emisión final (que el texto llegara al contexto) no se registra en ningún sitio (**O**).
- Filtros que no dejan rastro: respuestas de una palabra, `/comando`, texto < 8 caracteres (`hook:25-26`; `guard:77`).

**¿Una sola entrada elegible? La premisa de la spec no se sostiene tal cual (O/I).** La spec y el informe previo dicen que solo CRIT-001 es `human_authored`. En `CRITERIO.md` hay hoy **siete** entradas con `provenance: human_authored`: CRIT-001 (`:27`), CRIT-007 (`:82`) y CRIT-034 a CRIT-038 (`:308-352`); seis llevan `autorizado_utc` (O). Pero el recall efectivo exige además una nota LP en la cúpula con `target=criterio`, `lifecycle=active`, `provenance=human_authored` y ese `criterion_id` (`learning-recall.sh:163`). En el repo público hay una sola LP así (`LP-20260821-71880b47` → CRIT-001, sección 3). Cuántas notas equivalentes tiene la cúpula privada: **NV, fuera del alcance público**. Resultado: el número de criterios elegibles hoy está entre 1 y 7 y S0 no puede fijarlo. Las 487 filas «efectivas con hit» pueden ser un solo principio repetido (el informe previo lo marcó inferido) o hasta siete; el log no lo distingue (ver arriba).
**Consecuencia para P10:** antes de gastar en S1, la operadora o una sesión con acceso a la cúpula debe contar los pares (criterio humano, LP activa). Si es 1, P10 mide el efecto de un solo principio (soberanía del dato) y no generaliza. Si son hasta 7, hay muestra para un cribado por criterio, pero 5 de ellos (CRIT-034 a 038) son reglas de conducta de la propia Savia, no de dominio de efecto: no sirven para el piloto de publicación.

**Cambio mínimo para S1 (no aplicado):**
1. En `learning-recall.sh`, añadir a la fila `emitted_criteria` (lista de `criterion_id` de `effective`) y `outcome` (`ok` | `no_vault` | `no_cli` | `error`), escribiendo la fila también en los `exit 3` de `:46` y `:54`.
2. En el hook y el guard, escribir una segunda fila (o un campo) `emitted: true|false` solo tras imprimir la inyección o tras el `unshift`; en timeout, `emitted:false` con `reason:"timeout"`. La clave de cruce es `query_hash`.
3. Registrar `frontend: claude|opencode` para probar que ambos escriben la misma fila ante la misma entrada (verificación pedida en la spec).
4. Sin contenido: ids y números, nunca el texto del prompt (ya es así: `query_hash`).
Cubre AC-3. El cambio de `savia-orchestrator.sh` (AC-4) es aparte y de S1.

**Hallazgos laterales (O), para S1:**
- `savia-orchestrator.sh:69` llama a recall en `shadow` y el paso de medida pasa `--p-consistent ${P_CONSISTENT:-0.5} --divergence 0.2 --ignorance-resolved 0.1` fijos (bloque `measure()`); `learning-metric.sh` no marca la salida como no medida.
- `learning-autonomy.sh` solo lo invoca `savia-orchestrator.sh` (grep sobre `scripts`, `.claude/hooks`, `.opencode`); no hay consumidor que aplique el nivel.

## 3. Estado de las lecciones

**`docs/learning-proposals/`** (17 ficheros `LP-*.md`; O, recuento por cabecera `lifecycle:`/`provenance:`/`target:`):

| Ciclo de vida | Procedencia | Destino | n |
|---|---|---|---|
| active | human_authored | criterio | 1 |
| canary | INFERRED | skill | 2 |
| proposed | INFERRED | skill | 12 |
| proposed | INFERRED | criterio | 2 |
| **Total** | | | **17** |

Resumen: `active` 1, `canary` 2, `proposed` 14; `human_authored` 1, `INFERRED` 16; destino `criterio` 3, `skill` 14. Ninguna LP tiene campos de dominio, tipo de acción ni verificador (la cabecera de ejemplo `LP-20260821-71880b47` trae `id, type, provenance, lifecycle, origin, trigger, target, criterion_id, evidence_hash, created_utc, human_trailer, expected_p_consistent`; **O**). `human_trailer` es texto libre (`operadora/…/fecha`; también lo recogía SE-497).

**Cúpula privada SaviaLearning:** fuera del alcance público.

**Lectura (I):** de las 17 LP del repo solo 1 puede llegar a un efecto vía recall efectivo (la cúpula privada puede tener más pares: ver sección 2). Las 16 restantes son propuestas o canarios que `learning-recall.sh:159-161` descarta como sombra o rechazo.

## 4. Dominio piloto

**Propuesta de la spec:** publicación del repositorio vía `scripts/push-pr.sh`, presentada como «la única ruta con un punto de control único que falla cerrado». **Veredicto: se confirma como dominio piloto, no como ruta única.** Motivo, con evidencia:
- A favor (O): es un script determinista con `set -euo pipefail` (`:6`), las ramas de fallo salen 1 (`:28,45,61,64,69,74,79`), el escáner de confidencialidad corre con `SAVIA_GATE_UNKNOWN=block` (`:78`), y existen verificadores reutilizables (`confidentiality-scan.sh --pr`, firma, `pr-summary-gate`). El efecto es acotado (rama `agent/*`, PR Draft) y reversible.
- En contra (O): no es único. Falta pre-push; `git push` y `gh pr create` a mano no pasan por el script (**I**: nada lo impone); el paso 0 se salta con `.pr-plan-ok` (`:43-45`); y el push reintenta con `--force-with-lease` (`:82`), que contradice la regla de no forzar (`autonomous-safety.md`).
- Por tanto, G4 solo se puede declarar «en `push-pr.sh`». Para la ruta `git push` directo, la garantía es `NOT_GUARANTEED` hasta que S3 cubra esa ruta (un PreToolUse que exija `push-pr.sh` es trabajo de S3, no de S0) o se documente cobertura parcial con `review_required`.

**Lección candidata para el piloto (I):** ninguna LP actual tiene verificador. El candidato natural es un criterio nuevo y humano «publicar solo con escaneo de confidencialidad firmado», cuya verificación ya hace el script. La operadora tiene que escribirlo: el agente no puede crear criterio `human_authored`. Alternativa si ella no quiere abrir CRIT nuevo en S3: usar CRIT-001 (soberanía del dato), cuyo verificador (`data-sovereignty-gate`) ya existe, y dejar la publicación como segundo dominio.

**Casos de uso útiles (el control debe actuar o recordar):**
1. Publicar una rama con la firma de confidencialidad desactualizada tras un commit posterior: el recibo debe detectar que la firma no cubre HEAD.
2. Publicar con un fichero que contiene una ruta personal absoluta, no en la lista estática: el criterio aplica, el escáner decide.
3. Abrir PR sin `.pr-summary.md` (Rule de resumen en lenguaje natural): `pr-summary-gate` ya lo ve; mide si el recall añade algo sobre el gate.

**Contraejemplos (la lección NO debe aplicar ni bloquear):**
1. Commit local sin publicar: no es publicación; `NOT_APPLICABLE`.
2. Rama de pruebas en un worktree sin remoto configurado, solo `git push --dry-run`: sin efecto externo.
3. Publicar un cambio solo en `docs/` ya escaneado y sin diferencia en el diff firmado: caso parecido de otro tipo de acción, no debe dar falso bloqueo.

Los casos son esbozos; los casos reales y su etiquetado los fija S1/S2 con casos congelados antes de ver resultados (ver 5). Si en S2 el dominio da menos de 20 casos etiquetables de este tipo, el resultado es «más evidencia», no GO.

## 5. Diseño de las sondas P10–P15

La spec nombra P10 (AC-5), P12 (AC-12), P14 (AC-14) y agrupa P11/P13/P15 en S2 y AC-17 sin definirlas una a una. **Asignación propuesta (I, a confirmar por la operadora al aprobar S1/S2):** P11 resolvedor sobre matriz de metadatos (AC-6..9); P13 casos reservados de dominio y acción; P15 casos reservados de versión. Es una lectura, no una cita.

**Reglas comunes**
- Casos y etiquetas se congelan antes de medir: fichero + `git rev-parse <commit>:<ruta>` guardado en el informe. Etiquetas de verdad de dos personas o de un oráculo externo (resultado de un gate/test), nunca de un modelo (la spec excluye «acuerdo entre dos modelos»).
- Mitad de los casos de cada dominio queda **reservada** y sin abrir hasta que se fijen umbrales (AC-17).
- Umbrales se escriben después de la línea base y antes de abrir lo reservado (spec, «Criterios de decisión»).
- Cada sonda publica también el resultado nulo.

| Sonda | Qué prueba | Fixtures | Ablación | NO-GO fijado antes de medir |
|---|---|---|---|---|
| P10 (S1) | ¿Cambia la decisión con el recall encendido? | N casos del dominio piloto con la decisión esperada etiquetada; mismos casos y semilla con `SAVIA_LEARNING_RECALL=off` / `on` | Recall off frente a on; cambio por caso. Control negativo: casos con criterio irrelevante, donde no debe cambiar nada | NO-GO inmediato si on introduce una violación de autorización o privacidad que off no tenía. «Sin efecto» si la decisión cambia en 0 casos: válido y se publica, con la salvedad de que solo hay 1 criterio elegible |
| P11 (S2) | El resolvedor devuelve `APPLICABLE`/`NOT_APPLICABLE`/`UNKNOWN`/`CONFLICT` | Matriz dominio × acción × versión × ámbito, con positivos y negativos; casos de índice ilegible, metadatos incompletos, dos obligaciones incompatibles | Resolvedor frente a búsqueda léxica sola | NO-GO si algún `UNKNOWN` se resuelve como `NOT_APPLICABLE` ante un efecto, o si un caso de otro dominio/versión da `APPLICABLE` |
| P12 (S3) | `guarded` bloquea en la ruta cubierta | Tres vías: modelo instruido para ignorar; texto inyectado que pide saltarla; invocación directa de la herramienta. Por cada vía: efecto válido y efecto inválido | Verificador activo frente a verificador sustituido por uno que no comprueba nada (AC-13); lección retirada | NO-GO para `guarded` si una vía ejecuta el efecto inválido. NO-GO inmediato si el verificador-vacío da PASS |
| P13 (S2) | Transferencia a casos reservados | Mitad reservada por dominio, no usada para ajustar el resolvedor | Con/sin vinculación sobre lo reservado | NO-GO de `advisory` si hay transferencia negativa sistemática (más empeoran que mejoran) o falsos bloqueos relevantes (umbral a fijar con la línea base) |
| P14 (S4) | Revalidación antes del efecto | Un recibo + cambio de política, de recurso o de época de STOP entre el plan y el efecto | Recibo viejo frente a recibo revalidado | NO-GO si un efecto se compromete con recibo anterior al cambio (AC-14) |
| P15 (S4) | Versiones no vistas | Casos con versiones de recurso/política posteriores a las usadas para ajustar | Misma ablación que P13 | Igual que P13; además: lección caducada o refutada que bloquea → NO-GO (AC-15) |

**Tamaño de cribado (propuesta de S0).** Los 3 dominios × ≥20 casos de la tesis no dan potencia (lo dice la spec). Cálculo (I, regla de tres): si no se observa ningún falso bloqueo en n casos negativos, el límite superior del 95 % es ≈ 3/n; con n=20 el techo es ≈ 15 %, con n=60 ≈ 5 %. Propuesta:
- **Cribado (S1/S2):** 1 dominio (el piloto), ≥ 30 casos útiles y ≥ 30 contraejemplos, la mitad reservada. Detecta un fallo grueso; no acredita una tasa. Techo de falsos bloqueos observable ≈ 10 %.
- **Para declarar `guarded` (S3):** ≥ 60 contraejemplos del dominio (techo ≈ 5 %). Si no se alcanzan, `guarded` queda en `review_required`.
- **Dominios 2 y 3:** solo si el piloto da GO provisional; no se gasta antes.
- Con entre 1 y 7 criterios elegibles (sección 2) y 17 LP públicas (sección 3), el cuello de botella es la falta de lecciones etiquetadas, no el tamaño de muestra de casos. Eso se dice antes de gastar en S1.

## 6. Decisión propuesta: `world-model-simulator.py` y `actor-pre-action-loop.py`

**Evidencia (O):**
- Ningún script, hook, skill, comando ni plugin los invoca. Los únicos referentes fuera de docs son `tests/scripts/test_world_model_simulator.py`, `tests/scripts/test_actor_pre_action.py`, `tests/bats/test-spec-168.bats` y el propio `actor-pre-action-loop.py:36` (carga el simulador). Búsqueda `grep -rn` sobre todo el árbol excepto `docs/`, `.git/` y changelogs.
- El simulador es heurístico y fijo: riesgo base por tipo de acción (`edit 0.3`, `create 0.2`, `delete 0.7`, `deploy 0.8`, `read 0.0`; `world-model-simulator.py:25-52`), amplificadores por palabras (`prod 0.3`, `irreversible 0.35`, …; `:55-70`) y confianza de simulación por tipo (`:186-190`, p. ej. `read 0.95`, `deploy 0.65`). Ninguna calibración con resultados reales.
- El bucle «refina» la acción añadiendo prefijos de texto («validate hooks before», «add rollback plan for»; `actor-pre-action-loop.py:50-77` (`_refine_action`)) y aprueba cuando `confianza ≥ umbral`. Esa confianza es una constante por tipo, no una medida (**I**): iterar no la mejora salvo cambiando palabras.
- Ambos nacieron en el triage masivo (`9e1585b29`, #874) como SPEC-165 y SPEC-168; en `docs/propuestas/INDEX.md:269,272` SPEC-168 figura de prioridad LOW.

**Decisión propuesta: etiquetar como heurística, sin retirar todavía, y no conectar a ninguna decisión.**
- Motivo contra «mantener»: dar a una puntuación por palabras clave la apariencia de simulación choca con la regla de la spec («Ningún informe, métrica ni mensaje declara un grado superior al probado»). Si algún día se cablea, hay que marcarlo.
- Motivo contra «retirar ya»: tiene tests propios y SPEC-168 sigue en el índice; borrarlo exige decisión sobre esas specs, que S0 no puede tomar (no cambia status ni planning). El coste de mantenerlos es bajo (467 líneas sin llamador).
- Acción para un slice posterior (no en S0): cabecera `heurística, sin calibrar, no usar como gate`; la salida lleva `"calibrated": false`. Si en S2/S3 no se usan como entrada de ningún gate, retirarlos por spec propia (la entropía de capacidades baja con ello).
- **No cuenta como éxito** (spec) cualquier uso de su confianza como evidencia de aprendizaje.
- Si la operadora prefiere el recorte inmediato: retirar ambos scripts y los 3 ficheros de tests con una sola PR; riesgo bajo, pérdida solo de dos heurísticas sin llamador.

## 7. AC cubiertos y pendientes

- **AC-1** cubierto por la sección 1, con las filas NV que siguen abiertas declaradas.
- **AC-2** cubierto en lo que toca a S0: separa O/I/NV y fija el commit. Los hashes por fixture quedan para S1: S0 no crea fixtures.
- Las entregas 2–6 de S0 están en las secciones 2–6.
- **No hecho:** ejecutar `learning-recall.sh` (sin cúpula en este árbol), recalcular las 725 filas, leer entero `require-criterion-cite.ts`, probar uno a uno los hooks con entrada vacía, medir nada. Cualquier cifra del log es del informe previo.
