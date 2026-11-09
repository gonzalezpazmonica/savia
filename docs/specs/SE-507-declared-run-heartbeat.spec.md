---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L1
human_surface: true
related_specs: [SE-349, SE-229, SE-490, SE-504, SE-505, SE-445]
origin: "Informe de Savia Labs labs/research/20261102-herdr-continuidad.md, §3 y §4: inspirarse en la señal declarada con origen, secuencia y caducidad y en la explicación de la detección; no adoptar Herdr. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
---

# SE-507 — Latido declarado de los runs y un solo registro de ejecuciones

## Problema (verificado en origin/main 3e094038d, 2026-11-03)

1. **Dos registros de ejecuciones con dueños distintos.** El lanzador de workers headless que usa la operadora (fuera del repo) lleva su propio log de arranques y fines; el ledger oficial de runs de SE-349 (`scripts/savia-runs.sh`, `data/agent-runs-ledger.jsonl`) casi no se usa. El informe contó 405 arranques en el primero y 3 filas en el segundo, y ningún script del lanzador llama a `savia-runs.sh`.
2. **Entre el arranque y el fin no se sabe nada.** Un worker `claude -p` sin terminal solo deja «proceso vivo» o «terminó». Si se atasca, nadie lo ve hasta que vence su time-box (horas). `savia-runs.sh state` acepta `spawning|active|waiting_input|blocked|exited` (`scripts/savia-runs.sh:11`), pero nadie lo escribe durante la ejecución y el valor no caduca: un `active` de hace seis horas sigue saliendo como `working` (`scripts/savia-runs.sh:131`).

## Discovery: qué ya existe

| Pieza | Dónde | Qué cubre | Qué no |
|---|---|---|---|
| Ledger de runs con estado derivado en lectura | `scripts/savia-runs.sh:107-133` (`derive(r) -> (status, trace)`) | Una sola definición de precedencias y un `trace` con el motivo | `activity_state` no tiene origen, secuencia ni caducidad |
| Explicación de la derivación | `scripts/savia-runs.sh:582-615` (`show` imprime `trace`) | Equivale a `DetectionExplain` para `show` | `status` y `list` no enseñan el motivo; no dice qué fuente lo decidió ni cuándo caduca |
| Latido de sesiones interactivas | `scripts/session-registry.sh` (SE-229), caducidad 600 s | Sesiones con humano delante | No cubre runs headless ni se cruza con el ledger SE-349 |
| Caducidad de observaciones | `projects/soul-continuity/src/contract/claims.ts` (`observed_at`, `valid_until`, `stale`) | Fuentes de trabajo de la persona | No observa agentes |
| Interrumpido ≠ vivo | Savia Space, `FailCause::Interrupted` (repo privado) | Space marca y no relanza | Fuera de este repo |

Conclusión: no hace falta una ontología nueva ni un multiplexor. Falta que `activity_state` sea una **señal declarada con origen, secuencia y caducidad**, y que la derivación diga por qué.

## Qué decide esta spec

1. **Subcomando `savia-runs.sh beat <run_id> --seq N|auto --phase TEXTO --ttl SEGUNDOS --source hook|launcher|manual`.** Guarda `last_beat = {source, seq, phase, at, valid_until}` en el registro del run. Validación de entrada (rechazo con exit 2 sin tocar el ledger): `run_id` debe casar `^[A-Za-z0-9_-]{1,64}$`; `phase` debe casar `^[A-Za-z0-9 ._:/-]{1,200}$` (sin saltos de línea, caracteres de control, comillas ni signos de puntuación libres) y se trunca a 80 caracteres; el juego de caracteres reducido deja la frase corta como etiqueta, no como instrucción, y el gemelo la muestra entre comillas como dato; `ttl` entero en `[10, 86400]`; `source` de la lista cerrada.
2. **`seq` estrictamente creciente por run.** Un latido con `seq` numérico menor o igual que el último se rechaza (exit 1) y no cambia nada. `--seq auto` asigna `último + 1` **dentro del cerrojo del ledger**, de modo que dos hooks concurrentes del mismo run no se pisan: es la forma que usa el hook. El número explícito queda para el lanzador y los tests. Un latido aceptado sobre un run en `spawning` lo pasa a `active` (el primer latido es la prueba de que arrancó). Sobre un run en `waiting_input` o `blocked` el latido se acepta, actualiza `last_beat` y **conserva** el estado: pedir algo a la persona no lo deshace un latido.
3. **Sin latido vigente no hay `working`.** La derivación devuelve `unknown` cuando `activity_state=active` y `last_beat.valid_until` ya pasó, con `trace` «heartbeat expired at <hora> (source=<origen>, seq=<n>)». Un run arrancado con `start --heartbeat-ttl SEGUNDOS` declara que va a latir: si no llega ningún latido antes de `started_at + ttl`, también es `unknown` («no heartbeat since start»), tanto en `spawning` como en `active`. Solo los runs que no declaran latido ni han latido nunca siguen la regla actual, para no romper los usos existentes. La caducidad solo aplica a `spawning` y `active`: un run en `exited` declaró que salió, deja de deber latidos y se deriva `idle` como hoy, tenga o no `heartbeat_ttl` (lo cubre AC-5).
   - **Precedencia en `derive()`** (`scripts/savia-runs.sh:112-133`), de arriba abajo: (a) `is_terminated` → `failed` si `outcome=failed`, si no `merged`/`terminated` como hoy; (b) `outcome=failed` sin terminar (punto 4) → `failed`; (c) `waiting_input`/`blocked` → `needs_input`, como hoy (ya pide a la persona; el latido no cambia eso); (d) **`activity_state` en `spawning|active` con latido caducado o ausente desde el arranque → `unknown`, antes del bloque `pr`**; (e) bloque `pr` como hoy; (f) `active` → `working`. La regla (d) va antes del PR porque los workers nocturnos abren PR: si fuera después, un worker atascado con PR draft saldría como `draft` y el atasco no se vería nunca. El `trace` de (d) añade el estado del PR si lo hay («…; pr.state=draft»).
   - **Reloj:** `_now` (`scripts/savia-runs.sh:27`) devuelve `SAVIA_RUNS_NOW` solo si además `SAVIA_RUNS_TEST=1` y `BATS_TEST_FILENAME` no está vacía; en cualquier otro caso la ignora y avisa por stderr. Así un entorno de producción con la variable olvidada no congela el reloj y un latido no deja de caducar. No es una frontera de seguridad y no se presenta como tal: la derivación se calcula en el proceso que **lee** (gemelo, tablero), con su propio entorno; un worker que fije las tres variables solo altera su propia lectura, no la del gemelo.
   - **TTL recomendado:** el hook late en `PostToolUse`, así que una sola tool larga (una suite de 20 min) no late mientras corre. El lanzador usa `--heartbeat-ttl` ≥ el time-box de la tool más larga que admite (por defecto 1800 s); un TTL menor da `unknown` falsos y es error de configuración, no del latido.
4. **El fin solo lo acredita la marca de fin.** `savia-runs.sh finish <run_id> --rc N [--done-file RUTA]`; un latido nunca termina un run. Hoy `cmd_finish` (`scripts/savia-runs.sh:324-389`) solo acepta `--force` y el registro no tiene campo de resultado, así que esto es un cambio de esquema y de contrato, y se fija así:
   - **Campo nuevo `outcome`** con valores `ok|failed|null`; `rc` y `done_file` se guardan junto a él.
   - **`schema_version` sigue a los campos, no al comando.** `start` sin `--heartbeat-ttl` escribe `"1"`, exactamente como hoy (`scripts/savia-runs.sh:186`, `:204`), de modo que `tests/test-se-349-agent-runs-ledger.bats:69` sigue pasando sin tocarlo. Un registro pasa a `"2"` la primera vez que recibe un campo nuevo: `heartbeat_ttl` (en `start --heartbeat-ttl`), `last_beat`, `beat_errors` u `outcome` (en `finish --rc`). Los lectores aceptan `"1"` y `"2"`; los campos que falten en un `"1"` valen `null`. Ningún registro se reescribe solo para subir la versión.
   - **Regla:** `--rc 0` y `--done-file` existente y no vacío → `ok`; `--rc ≠ 0`, o `--rc 0` con marca ausente o vacía → `failed`. `--done-file` solo se acepta si su ruta real está bajo `SAVIA_RUNS_DONE_ROOT` (por defecto `~/.savia`), y se comprueba y se lee sobre el **mismo descriptor**, abierto con `O_NOFOLLOW` (sin hueco entre comprobar y leer). Con `--rc 0`, una ruta fuera de la raíz → exit 2 sin terminar. Con `--rc ≠ 0` la marca no hace falta para decidir: una ruta inválida se ignora, se anota `done_file_rejected: true`, se registra `failed` igual y se avisa por stderr; el fallo del worker nunca se pierde por una ruta mal escrita.
   - **Qué prueba `ok`:** que el worker salió con 0 y escribió su marca. Es una afirmación del worker, no una verificación de su trabajo (el worker puede escribir en `~/.savia`); la verificación sigue siendo la revisión de su PR.
   - **Sin `--rc` (uso actual):** comportamiento idéntico al de hoy, `outcome: null`. No se infiere fallo, para no romper a los llamadores ni `tests/test-se-349-agent-runs-ledger.bats`.
   - **Orden respecto al guardrail de PR vivo** (`:351-373`): con `--rc ≠ 0` el resultado `failed` se registra **siempre**, también si el run posee un PR open/draft; en ese caso el run **no** se termina (`is_terminated` sigue `false`, el PR lo mantiene vivo) y `finish` sale con 1 avisando del PR, como hoy. Así un worker que falla con PR abierto deja constancia del fallo sin necesitar `--force`. Con `--rc 0` o sin `--rc`, el guardrail actúa como hoy antes de escribir nada.
   - **El primer resultado manda, termine o no el run.** Si el registro ya tiene `outcome` no nulo (terminado o no), un `finish --rc` que daría otro `outcome` distinto sale con 1 sin cambiar nada; corregirlo es una decisión humana, no de un segundo worker. Uno que daría el mismo `outcome` no cambia nada y sale con 0 si el run ya está terminado, o con 1 y el aviso del PR vivo si el guardrail sigue impidiendo terminarlo (el aviso manda sobre el no-op, para que el llamador sepa que el run sigue abierto). `--force` conserva su significado actual (saltar el guardrail de PR vivo): con `--rc` registra el `outcome` calculado y termina el run; nunca sobrescribe un `outcome` ya registrado. Un `finish` sin `--rc` sobre un run con `outcome: failed` y sin terminar lo termina cuando el guardrail lo permite (el PR ya no está vivo) y conserva `failed`. Sobre un run ya terminado, `finish` sin `--rc` sigue siendo no-op con 0.
   - **Columnas del tablero:** `_RUN_COLUMNS` gana `unknown` y `failed`; un run con `outcome: failed`, terminado o con su PR aún vivo, se deriva como `failed` (precedencia del punto 3), no como `terminated` ni como el estado de su PR; el `trace` cita el PR si sigue vivo.
5. **Un latido tras `exited` o tras `finish` se rechaza** (exit 1, registro sin cambios) y no reabre el run. Son dos casos distintos: `finish` pone `is_terminated=true`; `state exited` solo cambia `activity_state` (`scripts/savia-runs.sh:211-240`) y deja `is_terminated=false`. `beat` rechaza si `is_terminated=true` **o** `activity_state=exited`.
6. **Hook opcional de latido** `.claude/hooks/run-heartbeat.sh` (`PostToolUse`): lee el JSON de stdin y solo actúa si el entorno trae `SAVIA_RUN_ID` (validado con el mismo patrón que `beat`). Sin esa variable sale con 0 sin escribir. Nunca bloquea una tool. Usa `beat --seq auto`. Si no consigue escribir (stdin malformado, cerrojo vencido, ledger ilegible), sale con 0 y anota el fallo en el registro del run como `beat_errors = {count, last_at, last_reason}` cuando el ledger es escribible. `last_reason` sale de una lista cerrada (`stdin_empty|json_invalid|lock_timeout|ledger_unreadable|beat_rejected|other`), nunca de texto de la entrada: el `trace` lo lee el gemelo, que es un LLM, y un motivo libre sería una vía de inyección; si ni eso puede, no escribe nada. La derivación usa ese dato en el `trace`: «heartbeat expired … (hook failed N times, last: <motivo>)» frente a «heartbeat expired … (no hook errors recorded)», para que la persona distinga un hook roto de un worker atascado.
7. **El lanzador de workers** registra cada worker con `start --heartbeat-ttl`, exporta `SAVIA_RUN_ID` y lo cierra con `finish --rc --done-file`. Su log propio queda como traza, no como fuente de verdad. El lanzador vive fuera del repo; esta spec define el contrato y un ejemplo en `docs/`.
8. **`status` y `list` enseñan el motivo** (`trace`) con `--explain`, igual que `show`.
9. **Gemelo (SE-504, dependencia no resuelta: la spec aún no existe en `docs/specs/`; S3 no empieza hasta que exista y esté aprobada).** El gemelo lee el estado derivado, no el log, y solo avisa a la persona de runs en `unknown` o `needs_input`, dentro del presupuesto de avisos de SE-490. No relanza nada: relanzar un run interrumpido es una decisión de la persona.

## Lo que he entendido

### Escenas
1. Son las 23:40. Tienes cuatro workers nocturnos en marcha. Uno lleva 25 minutos sin hacer nada porque espera un permiso que nadie ve. A los 15 minutos de su último latido, el gemelo te escribe: «El worker de specs no da señales desde las 23:15. Última fase: "tests". No lo reinicio; dime si lo paro.»
2. Por la mañana abres el tablero de runs y ves dos en `unknown`. Al lado de cada uno, una línea en llano: «sin latido desde las 3:02 (el hook dejó de escribir)». No tienes que abrir ningún log.
3. Un worker termina con error y sin marca de fin. El tablero lo muestra como «falló», no como «terminado», y el gemelo te lo cuenta en el resumen del día, no a las 4 de la madrugada.

### Palabras de la persona
> «Justo lo que necesito es que el gemelo operativo sea Soul hablando activamente con el operador» — 2026-11-03

Esa frase es sobre el gemelo, no sobre el latido. La operadora no ha pedido el latido con sus palabras: la propuesta sale del informe (su decisión 2, aún sin respuesta). Por eso la confirmación está pendiente.

### Qué SÍ será
- Un estado por run que caduca si el worker deja de dar señales, con el motivo escrito.
- Avisos del gemelo solo cuando un run se queda sin señales o pide algo, respetando el presupuesto de avisos.

### Qué NO será
- No relanza workers ni repite órdenes.
- No lee pantallas de terminal ni instala nada.
- No sustituye la marca de fin como prueba de que un worker terminó.

### Confirmación
- fecha: pendiente
- respuesta: pendiente. Las escenas no se han enseñado a la operadora. La orquestadora debe preguntarlas antes de aprobar la spec. El requisito de «Lo que he entendido» y de esta confirmación viene de SE-505, que todavía no está en `docs/specs/` (dependencia no resuelta; mientras tanto rige la decisión de la operadora del 2026-11-03 sobre la puerta de comprensión).

## Slice S0 — Prototipo navegable
- prototipo: salida de `savia-runs.sh list --explain` con un ledger de ejemplo (un run `working`, uno `unknown` por latido caducado, uno `failed` sin marca) y el texto exacto del aviso del gemelo en el móvil.

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Criterios de aceptación

| AC | Criterio | Tipo | Test |
|---|---|---|---|
| AC-1 | Run `active` con latido vigente → `working`, `trace` cita `source` y `seq` | estática | `tests/test-se507-run-heartbeat.bats` |
| AC-2 | **Negativo:** run `active` con `valid_until` pasado → `unknown`, nunca `working`. El reloj se inyecta con la variable nueva `SAVIA_RUNS_NOW` (ISO-8601 UTC, resolución de segundo): `_now` la devuelve solo con `SAVIA_RUNS_TEST=1` y `BATS_TEST_FILENAME` no vacía (punto 3, «Reloj»), y el Python de la derivación la recibe por argumento, no la lee por su cuenta | estática | ídem |
| AC-2b | **Negativo (precedencia):** run `active` con PR draft y latido caducado → `unknown` (no `draft`), y el `trace` cita `pr.state=draft`; run `waiting_input` con latido caducado → `needs_input`; run sin `--heartbeat-ttl` que nunca latió, con PR draft → `draft` como hoy | estática | ídem |
| AC-2c | **Negativo (reloj):** `SAVIA_RUNS_NOW` fijada sin `SAVIA_RUNS_TEST=1`, o con ella pero con `BATS_TEST_FILENAME` vacía → se ignora (el latido caducado sale `unknown` con la hora real) y hay aviso en stderr | estática | ídem |
| AC-3 | **Límite:** `valid_until` exactamente igual a la hora actual → `unknown` (caduca en el instante, no un segundo después) | estática | ídem |
| AC-4 | **Negativo:** `beat` con `seq` igual o menor que el último → exit 1 y el registro no cambia (se compara el ledger byte a byte); `beat --seq auto` lanzado 10 veces en paralelo sobre el mismo run → 10 latidos aceptados y `seq` final = 10 | estática | ídem |
| AC-4b | **Negativo (entrada):** `beat` con `run_id` fuera del patrón, `phase` con salto de línea, con comillas o con `;` o `ttl` fuera de rango → exit 2 y ledger sin cambios; `phase` válida de 200 caracteres → se guarda truncada a 80; `beat` sobre un run `spawning` → pasa a `active`; `beat` sobre un run `waiting_input` → aceptado y `activity_state` sigue `waiting_input` | estática | ídem |
| AC-5 | **Negativo:** `beat` tras `finish` → exit 1, `is_terminated` sigue `true` y registro byte a byte igual; `beat` tras `state exited` (sin `finish`) → exit 1, `activity_state` sigue `exited`, `is_terminated` sigue `false` y registro byte a byte igual; run `exited` arrancado con `--heartbeat-ttl 60`, sin latidos y con 61 s → `idle`, no `unknown` | estática | ídem |
| AC-6 | `finish --rc 1` → `outcome: failed`; `finish --rc 0` sin `--done-file` o con marca inexistente o vacía → `outcome: failed`; `--rc 0` con marca no vacía → `outcome: ok`; `finish` **sin** `--rc` → `outcome: null` y mismo resultado que hoy; **negativo:** `--rc 0` con `--done-file` fuera de `SAVIA_RUNS_DONE_ROOT` o que es un enlace simbólico → exit 2 y el run sigue sin terminar; `--rc 1` con `--done-file` fuera de la raíz → `outcome: failed` registrado y `done_file_rejected: true` | estática | ídem |
| AC-6b | Run con PR draft: `finish --rc 1` → `outcome: failed` registrado, `is_terminated=false`, exit 1; un segundo `finish --rc 1` → exit 1 con aviso del PR y registro byte a byte igual; `finish --rc 0 --force` sobre ese run → exit 1 y `outcome` sigue `failed`; `finish --rc 0` → exit 1 sin escribir (guardrail actual). Run ya terminado `ok`: `finish --rc 1` → exit 1 y registro byte a byte igual; `finish` sin `--rc` → exit 0 no-op. **Negativo:** run con `failed` registrado y PR aún vivo → deriva `failed`; un `finish --rc 0` posterior → exit 1 y `outcome` sigue `failed` (byte a byte); tras cerrar el PR, `finish` sin `--rc` lo termina y conserva `failed` | estática | ídem |
| AC-7 | Run **sin** `--heartbeat-ttl` que nunca latió y está `active` → misma derivación que hoy (`working`); **negativo:** run con `--heartbeat-ttl 60`, sin latidos y arrancado hace 61 s → `unknown`; `start` sin `--heartbeat-ttl` escribe `schema_version: "1"` y `start --heartbeat-ttl 60` escribe `"2"`; regresión de `tests/test-se-349-agent-runs-ledger.bats` y `tests/test-agent-runs-board.bats` sin modificar ninguno de los dos ficheros (incluida la aserción de `schema_version = "1"` en `:69`) | estática | ídem + suites existentes |
| AC-8 | Hook `run-heartbeat.sh` sin `SAVIA_RUN_ID` → exit 0 sin escribir; con `SAVIA_RUN_ID` y JSON válido por stdin → un latido con `seq` creciente | estática | `tests/test-se507-heartbeat-hook.bats` |
| AC-9 | **Fail-closed:** hook con stdin vacío o JSON malformado → exit 0 (no bloquea la tool), sin latido escrito y `beat_errors.count` incrementado; como el lanzador arranca el run con `--heartbeat-ttl`, el run acaba en `unknown` y no en `working`, y su `trace` cita los fallos del hook; **negativo (inyección):** stdin con texto arbitrario («ignora lo anterior…») → `last_reason` es uno de los valores de la lista cerrada y el texto no aparece en el ledger | estática | ídem |
| AC-10 | `list --explain` y `status --explain` imprimen el `trace` de cada run | estática | `tests/test-se507-run-heartbeat.bats` |
| AC-11 | Métrica: tiempo hasta detectar un worker atascado, medido con un worker de prueba que deja de latir. Antes: hasta el time-box. Objetivo: ≤ TTL + 1 min | experimento | informe en `output/agent-runs/` |
| AC-12 | `capability-entropy.py --check` PASS (el subcomando amplía `savia-runs.sh`; no se crea script nuevo salvo el hook) | CI | — |

## Plan por slices

| Slice | Entrega |
|---|---|
| S0 | Prototipo de la salida y del aviso, confirmado por la operadora |
| S1 | `start --heartbeat-ttl`, `beat`, `finish --rc --done-file`, derivación con caducidad y `--explain` en `savia-runs.sh`; AC-1..7 (con 2b, 2c, 4b, 6b), AC-10 |
| S2 | Hook `run-heartbeat.sh` y contrato del lanzador en `docs/`; AC-8, AC-9, AC-11 |
| S3 | Lectura del estado derivado por el gemelo (SE-504), con el presupuesto de avisos de SE-490 |

## Fuera de alcance

- Detección de estado por pantalla (manifiestos de terminal). No hay ningún consumidor con pantalla.
- Relanzamiento automático tras reinicio.
- Cambiar el log propio del lanzador, que vive fuera del repo.

## Riesgos

- **Latido como prueba de avance:** un worker en bucle también late. El latido solo dice «vivo y ejecutando tools»; el bucle lo detecta `repeat-tool-guard.sh` (SE-445).
- **Escrituras concurrentes:** el ledger ya serializa con cerrojo; `beat` usa el mismo y `--seq auto` calcula el número dentro de él.
- **Dependencias no resueltas:** SE-504 (gemelo) y SE-505 (puerta de comprensión) no existen todavía en `docs/specs/`. S0–S2 no dependen de ellas; S3 sí.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/savia-runs.sh` (`beat`, `finish`, `--explain`) | Bash + Python stdlib | El mismo |
| `.claude/hooks/run-heartbeat.sh` | Hook `PostToolUse` registrado en `.claude/settings.json` | Plugin `.opencode/plugins/guards/run-heartbeat.ts` en `tool.execute.after`, con el mismo contrato y la misma batería de entradas (los guards TS divergen de los bash si no se prueban igual) |
| Lectura del gemelo (S3) | Soul / Space | Igual |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el plugin emite el mismo latido ante la misma entrada que el hook
- [ ] Tests BATS cubren AC-1..10 con negativos y el caso límite
- [ ] El hook nunca bloquea una tool

### Portability classification

- [x] **HYBRID**: el ledger es bash; el latido necesita un binding por frontend.

## Aprobación

Spec PROPOSED. Requiere la confirmación de escenas de la operadora (SE-505) antes de pasar a APPROVED. Esta PR solo añade documentación; ningún agente la fusiona sin grant.

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Dependencias corregidas**: SE-504 y SE-505 ya existen y están APPROVED. Los párrafos que las dan por inexistentes quedan obsoletos.
- **Slice nuevo propuesto**: el digest de SE-471, ya en main, lee del ledger de runs en lugar de las marcas de fin, con la correspondencia `OK`→`ok`, `FALLO`→`failed` y `PARCIAL`→`ok` con nota. SE-471 dejó ese registro para otra spec: es esta.
- Los avisos de runs del punto 9 entran por la cola única de SE-514.
