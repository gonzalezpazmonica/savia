---
status: APPROVED
priority: P1
developer_type: agent-single
created: 2026-11-04
author: Savia
phase: A
risk: L3
human_surface: true
related_specs: [SE-253, SE-037, SE-270, SPEC-150, SE-400, SE-397, SE-445, SE-453, SE-077, SE-505, SE-511]
origin: "Análisis comparativo Gentleman frente a Savia (2026-11-04, informe privado en Savia Labs) y decisión de la operadora del mismo día: Savia se especializa en investigación, metaorquestación y gobernanza; la programación se delega en harnesses aparte. Cuatro bloqueos falsos reales del 2026-11-04. Solo spec."
timeline:
  - from: "2026-11-04"
    learned: "2026-11-04"
    value: "PROPOSED"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
---

# SE-510 — Guardas sin bloqueos falsos y un despachador por evento

## Problema (verificado en origin/main be2fca5aa, 2026-11-04)

Las guardas de Savia protegen de verdad (fuerza, `main`, secretos, borrados), pero también bloquean órdenes legítimas, y cuando lo hacen nadie lo cuenta: no hay registro de bloqueos, así que no se puede saber cuántos son falsos. Además cada llamada a una herramienta lanza decenas de procesos sueltos, sin orden garantizado ni un punto único que falle cerrado.

### Medidas recalculadas

| Medida | Valor | Comando |
|---|---|---|
| Registros de hook | **134** (133 `command` + 1 `prompt`) en **17** eventos; el análisis decía 126 en 18: 126 es el número de ficheros `.claude/hooks/*.sh`, no de registros | `python3 -c` sobre `.claude/settings.json` (Apéndice A, orden A1); `ls .claude/hooks/*.sh \| wc -l` → 126 |
| Por llamada a Bash | **24** PreToolUse + **12** PostToolUse | A1 |
| Por llamada a Edit/Write | **29** + **22** | A1 |
| Por llamada a Read | 12 + 10 | A1 |
| UserPromptSubmit | **8** por mensaje | A1 |
| Los 24 hooks PreToolUse de Bash con `ls`, en serie | **0,73–0,74 s** (3 vueltas, 12 núcleos, carga 2,6); el análisis medía ~1,6 s en otra carga | Apéndice A, orden A2 |
| Los mismos 24, en paralelo (como los lanza Claude Code) | **0,14–0,15 s** de pared | Apéndice A, orden A3 |
| Hook más lento de esos 24 | 74 ms (`repeat-tool-guard.sh`) | A2 |

La cifra en serie mide **CPU y procesos**, no la espera de la persona: Claude Code lanza los hooks de un evento en paralelo. Ya lo dejó escrito SE-253 (`scripts/benchmark-hook-dispatch.sh:6-8`: «El dispatcher NO reduce latencia de pared… los haría SECUENCIALES. El valor del dispatcher es trazabilidad y orden garantizado»). Esta spec no repite el error de vender el despachador como ahorro de tiempo de pared: su valor es orden, fallo cerrado, registro y paridad, y el presupuesto de latencia se mide en pared **y** en CPU.

### Los cuatro bloqueos del 2026-11-04 (tres falsos y uno mal explicado)

| # | Orden legítima | Guarda | Causa en el código | Reproducción (main be2fca5aa) |
|---|---|---|---|---|
| F1 | `git worktree add -q -b <rama> <ruta> origin/main` | `validate-bash-global.sh` → «destino de git add no reconocido» (`.claude/hooks/validate-bash-global.sh:114`) | El resolvedor `scripts/lib/git_op_targets.py` toma por `git add` real un texto que no lo es. La forma aislada pasa hoy (rc 0); **se reproduce** cuando el texto llega canalizado a un intérprete con fichero de script: `printf %s '<git worktree add …>' \| python3 x.py` → resolvedor devuelve `add` sin destino → exit 2. Pasó en vivo dos veces durante la redacción de esta spec. | Apéndice A, orden A4 |
| F2 | `git checkout --merge -- <ficheros>` | `block-branch-switch-dirty.sh` → «Cambio de rama con cambios sin commitear» | Solo exime la restauración si los argumentos **empiezan** por `--` (`.claude/hooks/block-branch-switch-dirty.sh:42-44`); `--merge -- f` no empieza así y se trata como cambio de rama. | Árbol sucio de prueba: `checkout --merge -- a.txt` → exit 2; `checkout -- a.txt` → exit 0. Orden A5 |
| F3 | `gh pr create` desde un worktree con su `.pr-summary.md` fresco | `pr-summary-gate.sh` → «.pr-summary.md tiene 97h de antigüedad» | Lee el resumen de `$CLAUDE_PROJECT_DIR/.pr-summary.md` (`.claude/hooks/pr-summary-gate.sh:20-21`) y su antigüedad (`:66-71`), no el del árbol donde se ejecuta `gh`. | Lectura del código; el corpus lo convierte en caso ejecutable |
| F4 | `.pr-summary.md` sin el encabezado exigido | `pr-summary-gate.sh:51-62` | El encabezado `## Qué hace este PR (en lenguaje no técnico)` está documentado (`docs/rules/domain/pr-natural-language-summary.md:23`), pero solo se enseña **después** de bloquear. Nada lo anuncia al crear el fichero. **El bloqueo en sí es correcto**: el fallo es de descubribilidad, no de la guarda. Por eso F4 no entra en el corpus ALLOW; lo cubre AC-10 (plantilla y aviso) y su entrada sigue en BLOCK (B4 de D1). | Lectura del código |

### Qué ya existe (no se duplica, se enlaza)

| Pieza | Dónde | Qué cubre | Qué le falta para este problema |
|---|---|---|---|
| Despachador SE-253 | `hooks/dispatchers/dispatch-pretooluse.sh`, `dispatch-posttooluse.sh`, tablas `hooks/routing-pretooluse.tsv` (57 líneas) y `routing-posttooluse.tsv` (42) | Un punto de entrada por evento, orden explícito | **No está registrado** en `.claude/settings.json`; **falla abierto**: sin tabla sale 0 (`dispatch-pretooluse.sh:31-34`), hook inexistente se salta (`:51-55`), un exit distinto de 2 se ignora (`:69-71`); la tabla dice «26 entradas» frente a las 57 registradas hoy; su documento de diseño (`docs/rules/domain/se-253-dispatcher-design.md`, citado en `:10`) no existe. |
| Corredor TS de OpenCode | `.opencode/plugins/savia-foundation.ts:68-93` (`BEFORE_GUARDS`), `:111` (`runGuardsOnVariants`), 28 ficheros en `.opencode/plugins/guards/` | Ya es «un proceso por evento» en OpenCode, con orden fijo | Paridad no comprobada con la misma entrada; dos huecos solo en TS en el pasado (PR #1237, #1238). `scripts/opencode-parity-audit.sh` mide registros que faltan, no veredictos distintos. |
| Corpus de ablación | `config/kernel-corpus.json` (18 casos: 8 BLOCK, 5 ALLOW), `config/ablation-f4-corpus.json` (14: 11 BLOCK, 3 ALLOW); runner `scripts/ablation_units.py` (SE-400 F4, READY_FOR_HUMAN_REVIEW) | Casos de entrada con veredicto esperado, por evento y herramienta | Casi todo es BLOCK: **8 ALLOW** entre los dos. Ninguno de los cuatro casos reales. Mide hooks quitados, no falsos positivos de guardas activas. |
| Línea base FP/FN | `scripts/hook-multihandler-baseline.sh` (SPEC-150, IMPLEMENTED), `tests/evals/hook-baselines/` | FP/FN de 6 hooks con 20 entradas sintéticas cada uno | Sintético, puntual (junio de 2026), 6 hooks; SPEC-150 cerró sus slices 3-6 por «FP=0» con criterio de reapertura FP ≥ 2 %. Los cuatro casos reales muestran que el corpus sintético no ve el problema. |
| Perfiles de hooks | `scripts/hook-profile.sh`, `/hook-profile` (`.claude/commands/hook-profile.md:11-25`), `.claude/hooks/lib/profile-gate.sh:9-33` (minimal/standard/strict/ci) | Cuántas guardas corren | Bajar de perfil quita protección; no corrige un falso bloqueo. Esta spec no los toca. |
| Presupuestos por hook | SE-037 (`docs/propuestas/SE-037-hook-latency-audit.md:27`, < 20 ms p50 críticos), SE-270 S5 (`scripts/hook-latency-budget.sh`, 100 ms), `scripts/hook-latency-audit.sh`, `hook-bench-all.sh` | Latencia de cada hook suelto | No hay presupuesto **por llamada** (suma del evento) ni en CPU. |
| Salida rápida por relevancia | SE-397 F5A (`docs/specs/SE-397-f5a-hot-path-relevance.spec.md:50`, DEFERRED) | Hook que sale antes si la orden no le concierne | Complementaria; el despachador puede aplicar el mismo filtro por matcher una vez. |
| Contrato de resultado | SE-453, `.claude/hooks/lib/gate-result.sh:1-41`, `output/unmeasured-gates.jsonl` | Registra gates **no medidos** | No registra bloqueos. El registro nuevo copia su patrón (JSONL en `output/`, fuera del repo). |
| Repetición bloqueante | SE-445, `repeat-tool-guard.sh` | Tercera llamada idéntica → exit 2 | Su bloqueo es legítimo y debe entrar en el registro con su motivo; también obliga a que los bancos de latencia varíen la entrada. |

## Lo que he entendido

### Escenas

1. Son las 23:40. Una worker abre su worktree con `git worktree add -q -b agent/… <ruta> origin/main`. Hoy una guarda la para diciendo que no sabe adónde va un `git add` que no existe. Con esta spec la orden pasa y, si una guarda se equivoca otra vez, el bloqueo queda en el registro con la orden exacta, y esa orden entra en el corpus.
2. Resuelves un conflicto con `git checkout --merge -- fichero`. Hoy te dicen que estás cambiando de rama. Con esta spec pasa, y `git checkout main` con cambios sin guardar sigue bloqueado.
3. Abres una PR desde un worktree. Hoy te rechaza un `.pr-summary.md` viejo de otra carpeta. Con esta spec se mira el resumen del árbol donde ejecutas `gh`, y al crear el fichero ya sabes qué encabezado lleva.
4. Un lunes miras `bash scripts/guard-blocks.sh report` y ves cuántos bloqueos hubo la semana pasada, cuántos marcaste como falsos y en qué guarda. La cifra sale de datos, no de impresión.
5. El despachador de un evento casca. La herramienta no se ejecuta; el mensaje dice qué falló. Nunca pasa una orden porque la guarda no llegó a correr.

### Palabras de la persona
«Luego usaremos yema con codex y savia con sonnet para implementar y optimizar el uso de tokens.» — 2026-11-09, mensaje de la operadora que encarga la repriorización tras Savia Viva R6. Sobre tokens en general, no sobre guardas; el alcance de aprobación: «Savia Viva + tokens y efectos» — 2026-11-09, respuesta de la operadora a la pregunta interactiva sobre qué specs aprobar.

### Qué SÍ será

- Un corpus versionado de órdenes legítimas que ninguna guarda puede bloquear, ejecutado en CI contra los hooks bash **y** contra los guards TS.
- Un registro local de cada bloqueo, y una tasa de falsos positivos que se calcula con una orden.
- Un despachador por evento que falla cerrado, con orden fijo y presupuesto de latencia medido.

### Qué NO será

- No baja el perfil de hooks ni quita guardas para ir más rápido.
- No relaja ninguna guarda de seguridad: cada exención nueva lleva al lado su caso negativo.
- No promete menos espera de pared por sí solo (ver SE-253).
- No sube el registro a ningún sitio: se queda en `output/` de la máquina.

### Confirmación
- fecha: 2026-11-09
- respuesta: «Confirmo las escenas». Opción elegida por la operadora en la pregunta interactiva del 2026-11-09 en la que se le enseñaron estas escenas literalmente.

## Slice S0 — Prototipo navegable
- prototipo: los mensajes que ve la persona en las escenas 1, 2, 3 y 5, antes y después del cambio, con su clase FORMA o POLÍTICA, y la salida de `scripts/guard-blocks.sh report` sobre un registro de ejemplo de una semana.

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Qué decide esta spec

### D1 — Corpus de órdenes legítimas (`config/guard-allow-corpus.json`)

- Mismo esquema que `config/kernel-corpus.json` (`id`, `category`, `event`, `tool`, `input`, `expect`), con `expect: ALLOW` obligatorio y campos `origin` (`real:<fecha>` o `sintético`), `guard` (la que falló, si es real) y `fixture` (árbol limpio, sucio, worktree con resumen fresco…).
- Semilla obligatoria. Una entrada tiene **un solo** veredicto esperado: ninguna aparece a la vez como ALLOW y como BLOCK. Cada ALLOW apunta a su **par peligroso**, que es una variante mínima de la misma forma (mismo `event`, misma `tool`, misma orden base) con el destino o el estado peligroso, y debe seguir dando BLOCK.

| id | expect | Entrada (forma) | par |
|---|---|---|---|
| F1a | ALLOW | `git worktree add -q -b <rama> <ruta> origin/main`, aislada | B1 |
| F1b | ALLOW | el mismo texto canalizado a un intérprete con fichero de script (`printf %s '<…>' \| python3 x.py`) | B1b |
| F2 | ALLOW | `git checkout --merge -- <fichero>` con árbol sucio | B2 |
| F3 | ALLOW | `gh pr create` desde un worktree con `.pr-summary.md` fresco y con encabezado | B3 |
| B1 | BLOCK | `git add <ruta>` con destino no resoluble | — |
| B1b | BLOCK | `printf 'git add -A' \| bash` (un `git add` real canalizado a un intérprete) | — |
| B2 | BLOCK | `git checkout <rama>` con árbol sucio | — |
| B3 | BLOCK | `gh pr create` desde un worktree sin resumen, o con resumen viejo, en su propio árbol | — |
| B4 | BLOCK | `gh pr create` con `.pr-summary.md` fresco pero sin el encabezado exigido (F4) | — |

- F4 no es un falso positivo (ver la tabla del problema): su entrada es B4 y sigue en BLOCK; su arreglo es AC-10.
- El arreglo de F1 no exime la forma «texto canalizado a un intérprete»: un `git add` real dentro de un script canalizado se sigue evaluando (B1b), y un destino que no se puede resolver sigue fallando cerrado.
- Las órdenes se guardan **literales**, como llegaron. F1 ya enseña que la forma simplificada no reproduce el fallo.
- Un bloqueo que la persona marca como falso (D2) entra en el corpus por PR, con su par peligroso. Sin par, no entra. Todo cambio en `config/guard-allow-corpus.json` es **tier 3** (revisión humana explícita, SE-362): S1 lo añade a CODEOWNERS y a la clasificación de riesgo, para que el corpus no se convierta en una vía de exenciones incrementales.
- Ejecutor: amplía `scripts/ablation_units.py` o el runner del corpus kernel. No se escribe un tercer runner.

### D2 — Registro de bloqueos y tasa de falsos positivos

- Toda guarda que sale con exit 2 (o el despachador en su nombre) añade una línea a `output/guard-blocks.jsonl`: `ts`, `event`, `tool`, `guard`, `reason` (primera línea del mensaje), `cmd_hmac` y, solo si `SAVIA_GUARD_LOG_INPUT=1`, la orden **tras pasar la redacción de secretos** (`docs/rules/domain/secret-redaction-policy.md`). Por defecto la orden **no** se guarda: puede llevar un secreto, que es justo lo que algunas guardas bloquean. `cmd_hmac` es HMAC-SHA256 con una clave local de la máquina (fuera del repo, `0600`, generada al primer uso), no un hash sin sal: un hash simple de una orden de baja entropía con un token corto se confirma por diccionario. Sin clave legible, el campo queda vacío y el registro lo dice; nunca se cae a un hash sin clave. El patrón es el de `gate_unmeasured_record` (`.claude/hooks/lib/gate-result.sh:31-41`).
- `scripts/guard-blocks.sh mark <id> false-positive|true-positive` etiqueta. `report [--since]` da por guarda: bloqueos, etiquetados, FP, tasa FP = FP / etiquetados, y «sin etiquetar» aparte. Con 0 etiquetados la tasa es `UNKNOWN`, nunca 0 %.
- La tasa del corpus (D1) se calcula en CI: falsos bloqueos / casos ALLOW. **Umbral: 0.** Cualquier caso ALLOW bloqueado rompe la CI.

### D3 — Un despachador por evento

- Reutiliza `hooks/dispatchers/` de SE-253; no se escribe otro. Cambios:
  1. **Fallo cerrado** en PreToolUse: tabla ausente o ilegible, hook registrado que falta, exit distinto de 0/2 en un hook bloqueante, tiempo agotado o error del propio despachador → exit 2 con el motivo. PostToolUse mantiene «no bloquea», pero registra el fallo.
  2. **La tabla se genera** desde `.claude/settings.json` y un test exige que coincidan: no puede volver a pasar lo de «26 entradas» frente a 57.
  3. **Orden fijo**: bloqueantes baratos primero (como `BEFORE_GUARDS`, `savia-foundation.ts:69-70`); el primer exit 2 corta y se registra.
  4. **JSON una vez**: el despachador parsea stdin una vez y pasa la misma entrada a cada guarda por stdin; no se pasa por variables de entorno.
  5. **Paridad TS/bash**: el corpus D1 y el de bloqueos corren contra los hooks bash y contra `BEFORE_GUARDS` con la misma entrada. Un veredicto distinto falla. Amplía `scripts/opencode-parity-audit.sh` de «registro ausente» a «veredicto distinto».
- Registro en `settings.json` en **sombra** primero (S3): corre al lado de los hooks sueltos y compara veredictos durante una semana de uso. Solo con 0 discrepancias se sustituyen los registros sueltos por el despachador (S4).
- **Discrepancias esperadas por exit 1.** Claude Code trata el exit 1 de un hook suelto como no bloqueante; el despachador, por fallo cerrado, lo convierte en exit 2. Esa diferencia es buscada, no un error, pero no puede quedar sin resolver. S3 empieza con un inventario: cada hook PreToolUse que hoy sale 1 (por el registro de sombra y por una pasada del corpus) queda listado con su motivo. El registro de sombra clasifica cada discrepancia como `esperada-exit1` (el hook suelto salió 1 y el despachador bloqueó) o `inesperada` (cualquier otra). Antes de S4, cada hook del inventario se resuelve de una de dos formas: se corrige para que no salga 1 por error interno, o se declara no bloqueante en la tabla (corre después de los bloqueantes y su fallo se registra sin bloquear). AC-9 exige 0 `inesperada` y 0 `esperada-exit1` de hooks sin resolver.
- Se documenta la decisión que faltaba: `docs/rules/domain/se-253-dispatcher-design.md`, ahora con el contrato de fallo cerrado.

### D4 — Presupuesto de latencia por llamada

- Medido con `scripts/hook-dispatch-bench.sh` (evolución de `benchmark-hook-dispatch.sh`), entrada variada en cada vuelta (si no, `repeat-tool-guard` bloquea la tercera) y `HOME` aislado:
  - **Pared**, p95 por llamada a Bash y a Edit: ≤ **150 ms**, no peor que la línea base en paralelo (0,14–0,15 s en esta máquina) en más de un 10 %.
  - **CPU** por llamada a Bash: −50 % frente a la línea base en serie (0,73 s). CPU es user + sys de los procesos hijos del evento (`getrusage(RUSAGE_CHILDREN)` o `os.wait4`), nunca tiempo de pared.
- **Por qué los dos objetivos no son el mismo.** Los bloqueantes corren en serie dentro del despachador (orden fijo, el primer exit 2 corta), así que su pared es ≈ su CPU. Con solo −50 % de CPU (≈ 0,365 s) la pared quedaría muy por encima de 150 ms. El objetivo vinculante es el de pared, y para alcanzarlo hay que **recortar trabajo**, no solo juntar procesos: filtro por matcher una sola vez, salida temprana por relevancia (SE-397 F5A) y comprobaciones baratas sin lanzar procesos. Los hooks no bloqueantes (registro, telemetría) sí pueden lanzarse en paralelo al terminar los bloqueantes. Si la pared no baja de 150 ms, S4 no sustituye los registros (AC-8); el −50 % de CPU es una condición necesaria, no suficiente.
- El presupuesto lo lee el bench de un fichero (`config/hook-call-budget.json`); cambiarlo exige otra medición y una enmienda.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | `config/guard-allow-corpus.json` contiene F1a, F1b, F2 y F3 con `origin: real:2026-11-04`, y ninguna entrada con F4; con main be2fca5aa al menos F1b y F2 dan BLOCK (el test falla antes del arreglo). | positivo |
| AC-2 | Tras S2, los casos ALLOW del corpus dan 0 bloqueos en los hooks bash y en los guards TS. | positivo |
| AC-3 | Cada caso ALLOW tiene su par peligroso (B1, B1b, B2, B3), que sigue en BLOCK, y B4 (F4) sigue en BLOCK; además `git push --force` a `main` sigue en BLOCK. La validación del corpus falla si un caso ALLOW no tiene par, si el par no comparte `event`, `tool` y orden base con su ALLOW, o si la misma entrada aparece con dos veredictos. | negativo |
| AC-4 | Un exit 2 de cualquier guarda deja una línea en `output/guard-blocks.jsonl` sin la orden en claro (salvo opt-in); `report` sin etiquetas da tasa `UNKNOWN`. | positivo / negativo |
| AC-5 | Despachador PreToolUse con tabla ausente, hook ausente, hook que sale 1, hook que excede el tiempo o JSON malformado → exit 2 y motivo. Ninguno de esos casos deja pasar la orden. | negativo |
| AC-6 | Una tabla de despacho que no coincide con `settings.json` falla su test. | negativo |
| AC-7 | Paridad: para todo caso de los dos corpus, veredicto bash = veredicto TS. Un guard TS que se desvía (mutación en el test) hace fallar el auditor. | negativo |
| AC-8 | El bench da p95 de pared ≤ 150 ms y CPU −50 % por llamada a Bash, con las cifras de antes y después en el body de la PR de S4. Si no se cumple, S4 no sustituye los registros. | positivo / negativo |
| AC-9 | El modo sombra (S3) registra cada discrepancia de veredicto entre despachador y hooks sueltos, clasificada `inesperada` o `esperada-exit1`, y el inventario de hooks que salen 1 existe; con alguna `inesperada` o alguna `esperada-exit1` de un hook sin resolver, S4 no arranca. | negativo |
| AC-10 | `.pr-summary.md`: el encabezado exigido sale en la plantilla y en el aviso de `pr-plan` antes de `gh pr create` (test: `pr-plan` sin resumen imprime el encabezado literal); el gate lee el resumen del árbol donde se ejecuta `gh` (`-C`, `cwd` de la entrada), y B4 sigue en BLOCK. | positivo / negativo |

## Fuera de alcance

- Cambiar qué protege cada guarda o bajar perfiles (`/hook-profile`).
- Los hooks de otros eventos que no sean PreToolUse/PostToolUse (SessionStart, Stop, UserPromptSubmit): el despachador empieza por los dos calientes; UserPromptSubmit lo mide SE-511 como contexto.
- Reescribir los guards TS: solo se comparan.
- Subir el registro de bloqueos fuera de la máquina.

## Riesgos

- **Fallo cerrado = más bloqueos al principio.** Un despachador roto bloquea todo. Por eso S3 en sombra y AC-9 antes de sustituir.
- **Un solo proceso, un solo punto de fallo.** Mitigación: tiempo por guarda dentro del despachador y fallo cerrado con motivo, no un cuelgue.
- **Exenciones que abren huecos.** Cada caso ALLOW necesita su par BLOCK (AC-3); la revisión humana de la PR es tier 3 (guardas de seguridad, SE-362).
- **Paralelo frente a serie.** En Claude Code el despachador serializa: la pared puede empeorar. AC-8 lo mide y lo frena.

## Plan por slices

0. **S0** — Prototipo de los mensajes y del informe, confirmado por la persona (SE-505).
1. **S1** — Corpus D1 con la semilla F1a–F3, sus pares B1, B1b, B2 y B3, y B4, runner sobre el existente, CI en rojo con main (AC-1, AC-3).
2. **S2** — Arreglos de F1–F3 en bash y TS, y plantilla y aviso de F4; registro de bloqueos y `guard-blocks.sh` (AC-2, AC-4, AC-7, AC-10).
3. **S3** — Despachador con fallo cerrado, tabla generada, en sombra (AC-5, AC-6, AC-9).
4. **S4** — Sustitución de registros sueltos si sombra y presupuesto pasan (AC-8).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Corpus y runner | `config/guard-allow-corpus.json`, `scripts/ablation_units.py` | Los mismos, contra `BEFORE_GUARDS` |
| Arreglos F1–F3 y aviso F4 | `.claude/hooks/validate-bash-global.sh`, `scripts/lib/git_op_targets.py`, `block-branch-switch-dirty.sh`, `pr-summary-gate.sh` | `.opencode/plugins/guards/validate-bash-global.ts`, `block-branch-switch-dirty.ts`; el gate de resumen se expone como guard o se marca `NOT_EXPOSED` con motivo |
| Despachador | `hooks/dispatchers/dispatch-*.sh` registrado en `.claude/settings.json` | Ya es un corredor por evento (`savia-foundation.ts:111`); se le añade el registro de bloqueos |
| Registro | `output/guard-blocks.jsonl`, `scripts/guard-blocks.sh` | El mismo fichero, escrito desde el corredor TS |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los dos corpus corren contra los guards TS
- [ ] Tests BATS y de TS cubren cada caso y su par
- [ ] Hooks nuevos o cambiados registrados en el plugin `savia-gates`

### Portability classification

- [x] **DUAL_BINDING**: el corpus y la comparación de veredictos exigen los dos motores desde S1.

## Apéndice A — Órdenes de medida

- A1 (recuentos): `python3` que carga `.claude/settings.json`, suma `len(g['hooks'])` por evento y, para Bash/Edit/Write/Read, los grupos cuyo `matcher` vacío, `*` o `re.fullmatch(matcher, tool)`.
- A2 (serie): los 24 `command` PreToolUse de Bash, uno tras otro con `subprocess.run(shell=True)`, entrada `{"tool_name":"Bash","tool_input":{"command":"ls"}}` y `CLAUDE_PROJECT_DIR` del worktree; 3 vueltas.
- A3 (paralelo): los mismos con `subprocess.Popen` a la vez, entrada distinta por vuelta; 3 vueltas.
- A4 (F1): `printf %s '<texto con git worktree add>' | python3 x.py` como `tool_input.command`, por `scripts/lib/git_op_targets.py <repo>` → `add` sin destino → `validate-bash-global.sh` exit 2.
- A5 (F2): repo temporal con `a.txt` modificado; `block-branch-switch-dirty.sh` con `checkout --merge -- a.txt` → 2, `checkout -- a.txt` → 0, `checkout other` → 2.

S1 versiona estas órdenes como `scripts/hook-dispatch-bench.sh` y casos del corpus; esta spec solo las describe.

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). Absorbe SE-475 (clase FORMA o POLÍTICA del bloqueo).

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Absorbe SE-475**: la clase del bloqueo (`FORMA` o `POLÍTICA`) es un campo de `output/guard-blocks.jsonl` (D2) y un prefijo del mensaje del hook, con la biblioteca común bash y TS. Las dos specs tocaban los mismos hooks y guards. SE-475 pasa a SUPERSEDED.
