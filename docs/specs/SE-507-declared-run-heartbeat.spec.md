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

1. **Subcomando `savia-runs.sh beat <run_id> --seq N --phase TEXTO --ttl SEGUNDOS --source hook|launcher|manual`.** Guarda `last_beat = {source, seq, phase, at, valid_until}` en el registro del run.
2. **`seq` estrictamente creciente por run.** Un latido con `seq` menor o igual que el último se rechaza (exit 1) y no cambia nada.
3. **Sin latido vigente no hay `working`.** La derivación devuelve `unknown` cuando `activity_state=active` y `last_beat.valid_until` ya pasó, con `trace` «heartbeat expired at <hora> (source=<origen>, seq=<n>)». Si el run nunca latió, sigue la regla actual: la caducidad solo se aplica a runs que han declarado latido.
4. **El fin solo lo acredita la marca de fin.** `savia-runs.sh finish <run_id> --rc N [--done-file RUTA]`: si `rc≠0` o la marca falta, el run termina con `outcome: FALLO`; un latido nunca termina un run.
5. **Un latido tras `exited` o tras `finish` se rechaza** y no reabre el run.
6. **Hook opcional de latido** `.claude/hooks/run-heartbeat.sh` (`PostToolUse`): lee el JSON de stdin y solo actúa si el entorno trae `SAVIA_RUN_ID`. Sin esa variable sale con 0 sin escribir. Nunca bloquea una tool.
7. **El lanzador de workers** registra cada worker con `start`, exporta `SAVIA_RUN_ID` y lo cierra con `finish --rc --done-file`. Su log propio queda como traza, no como fuente de verdad. El lanzador vive fuera del repo; esta spec define el contrato y un ejemplo en `docs/`.
8. **`status` y `list` enseñan el motivo** (`trace`) con `--explain`, igual que `show`.
9. **Gemelo (SE-504).** El gemelo lee el estado derivado, no el log, y solo avisa a la persona de runs en `unknown` o `needs_input`, dentro del presupuesto de avisos de SE-490. No relanza nada: relanzar un run interrumpido es una decisión de la persona.

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
- respuesta: pendiente. Las escenas no se han enseñado a la operadora. La orquestadora debe preguntarlas antes de aprobar la spec (SE-505).

## Slice S0 — Prototipo navegable
- prototipo: salida de `savia-runs.sh list --explain` con un ledger de ejemplo (un run `working`, uno `unknown` por latido caducado, uno `FALLO` sin marca) y el texto exacto del aviso del gemelo en el móvil.

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Criterios de aceptación

| AC | Criterio | Tipo | Test |
|---|---|---|---|
| AC-1 | Run `active` con latido vigente → `working`, `trace` cita `source` y `seq` | estática | `tests/test-se507-run-heartbeat.bats` |
| AC-2 | **Negativo:** run `active` con `valid_until` pasado (reloj inyectado con `SAVIA_RUNS_NOW`) → `unknown`, nunca `working` | estática | ídem |
| AC-3 | **Límite:** `valid_until` exactamente igual a la hora actual → `unknown` (caduca en el instante, no un segundo después) | estática | ídem |
| AC-4 | **Negativo:** `beat` con `seq` igual o menor que el último → exit 1 y el registro no cambia (se compara el ledger byte a byte) | estática | ídem |
| AC-5 | **Negativo:** `beat` tras `finish` o tras `state exited` → exit 1 y `is_terminated` sigue `true` | estática | ídem |
| AC-6 | `finish --rc 1` → `outcome: FALLO`; `finish --rc 0` sin `--done-file` existente → `outcome: FALLO`; `--rc 0` con marca → `outcome: OK` | estática | ídem |
| AC-7 | Run que nunca latió y está `active` → misma derivación que hoy (`working`); regresión de `tests/test-se-349-agent-runs-ledger.bats` y `tests/test-agent-runs-board.bats` sin cambios | estática | ídem + suites existentes |
| AC-8 | Hook `run-heartbeat.sh` sin `SAVIA_RUN_ID` → exit 0 sin escribir; con `SAVIA_RUN_ID` y JSON válido por stdin → un latido con `seq` creciente | estática | `tests/test-se507-heartbeat-hook.bats` |
| AC-9 | **Fail-closed:** hook con stdin vacío o JSON malformado → exit 0 (no bloquea la tool) y sin latido escrito, de modo que el run acaba en `unknown`, no en `working` | estática | ídem |
| AC-10 | `list --explain` y `status --explain` imprimen el `trace` de cada run | estática | `tests/test-se507-run-heartbeat.bats` |
| AC-11 | Métrica: tiempo hasta detectar un worker atascado, medido con un worker de prueba que deja de latir. Antes: hasta el time-box. Objetivo: ≤ TTL + 1 min | experimento | informe en `output/agent-runs/` |
| AC-12 | `capability-entropy.py --check` PASS (el subcomando amplía `savia-runs.sh`; no se crea script nuevo salvo el hook) | CI | — |

## Plan por slices

| Slice | Entrega |
|---|---|
| S0 | Prototipo de la salida y del aviso, confirmado por la operadora |
| S1 | `beat`, `finish --rc --done-file`, derivación con caducidad y `--explain` en `savia-runs.sh`; AC-1..7, AC-10 |
| S2 | Hook `run-heartbeat.sh` y contrato del lanzador en `docs/`; AC-8, AC-9, AC-11 |
| S3 | Lectura del estado derivado por el gemelo (SE-504), con el presupuesto de avisos de SE-490 |

## Fuera de alcance

- Detección de estado por pantalla (manifiestos de terminal). No hay ningún consumidor con pantalla.
- Relanzamiento automático tras reinicio.
- Cambiar el log propio del lanzador, que vive fuera del repo.

## Riesgos

- **Latido como prueba de avance:** un worker en bucle también late. El latido solo dice «vivo y ejecutando tools»; el bucle lo detecta `repeat-tool-guard.sh` (SE-445).
- **Escrituras concurrentes:** el ledger ya serializa con cerrojo; `beat` usa el mismo.

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
