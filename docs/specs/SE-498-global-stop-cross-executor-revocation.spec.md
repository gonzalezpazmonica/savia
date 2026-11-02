---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-11-02
author: Savia
phase: B
risk: L4
related_specs: [SE-343, SE-433, SE-445, SE-488, SE-490, SE-493, SE-496]
origin: "Hueco G4 del análisis de arquitectura de control (2026-11-02): Savia tiene cuatro STOP locales que no se hablan; un STOP sin propagación de revocación no es una revocación."
timeline:
  - from: "2026-11-02"
    learned: "2026-11-02"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-498 — STOP global y revocación entre ejecutores

## Problema

Savia orquesta varios ejecutores a la vez: el merge-sprint, los workers de `claude -p`, el bucle nocturno, Yema y Soul. Cada uno tiene su propio freno, o ninguno. Si la operadora dice «para todo», hoy hay que parar cada cosa por separado, con órdenes distintas, y nada comprueba que todas hayan parado. Peor: parar un proceso no revoca lo que ese proceso ya tenía concedido, y un ejecutor que se reconecta puede seguir usando un grant anterior.

Parar, revocar y recuperar son operaciones distintas. Un STOP debe impedir efectos nuevos, cancelar lo cancelable, invalidar delegaciones y dejar un registro conciliable. No puede prometer deshacer lo irreversible.

### Inventario de los cuatro STOP (verificado en origin/main bbe6ebfdb y en el repo de Yema 93d5e6d)

| # | STOP | Dónde | Qué hace | Qué no hace |
|---|---|---|---|---|
| S1 | merge-sprint | `scripts/merge-sprint.sh:23` (`STOPF`), `:312-324` (`halt`, `anomaly`, `stop_gate`), `:349-353` (`sprint_gate`: STOP, TTL, máximo), `:371` (STOP antes de cada merge), `:701` (`stop`), `:702` (`revoke`: mueve el grant) | Fichero STOP en el directorio del sprint. Vacío = STOP manual; con motivo = sprint parado que solo levanta un grant nuevo. `revoke` invalida el grant del sprint. | Solo afecta al merge-sprint. Se comprueba entre pasos: un STOP durante `gh pr merge` (`:383`) no la interrumpe. No avisa a ningún otro ejecutor. |
| S2 | Soul | `projects/soul-continuity/src/core/failsafe.ts:1-9` (contrato), `:33-41` (`stopState`, ilegible = STOP), `:44-48` (`stop`), `:50` (`resume`), `:57` (`assertRunning`); `src/cli/cli.ts:52` (un agente puede `stop`, no `resume`), `:146-147`, `:242-243`, `:430` (exit 5) | STOP durable por directorio de datos, fail-closed, auditado en `failsafe.jsonl`. Solo `resume` lo levanta. | Solo frena las lecturas de Soul en su máquina. No sabe nada de otros ejecutores ni de grants. |
| S3 | Yema | repo de Yema: `nucleo/yema.py:180-197` (`suspender` y `revocar` quitan el puntero `contratos/ACTIVO`), `nucleo/puerta.py:81` (parar no exige terminal), `:118-134` (`activo`: sin puntero, la puerta vuelve a E0); prueba `pruebas/test_puerta.py:306` | Suspender o revocar el contrato activo deja la puerta en E0 al instante. Reactivar exige una persona en terminal. | Solo afecta al contrato de Yema. Savia no puede pedírselo ni saber si ocurrió. |
| S4 | Time-box de autonomous-safety | `docs/rules/domain/autonomous-safety.md:42` (regla), `scripts/overnight-sprint-loop.sh:29` (`TASK_TIMEOUT_MIN`), `:244-246` (aborta tras 3 fallos), `:290-298` (`timeout`), `.claude/hooks/turn-budget-inject.sh:52` (presupuesto visible, opt-in) | Mata la tarea al vencer el tiempo y aborta el bucle tras 3 fallos seguidos. | Sin `timeout` en el sistema, la tarea corre sin límite (`:294-297`): falla abierto. Matar el proceso no clasifica los efectos en vuelo ni revoca nada. No hay orden de parada externa. |

Lo que falta en común:

1. **Ninguna señal compartida.** Cuatro ficheros, cuatro semánticas, ningún lector común.
2. **Ninguna propagación verificable.** Nadie sabe qué ejecutores recibieron la parada.
3. **Ninguna época.** Un grant o un contrato emitido antes de una revocación sigue pareciendo válido para quien no la vio.
4. **Reanudar significa cosas distintas.** Un grant nuevo (S1), una orden de la operadora (S2), una persona en terminal (S3) o nada (S4).
5. **Ningún cierre de lo que estaba en vuelo.** Solo S1 deja rastro (reserva F5), y SE-493 muestra que ese rastro pierde casos ambiguos.

## Qué decide esta spec

Un **plano de control local por instalación** con cinco operaciones (`pause`, `revoke`, `quarantine`, `reconcile`, `resume`) y una **época de revocación** monótona que consultan el kernel de autoridad (SE-496) y el Effect Ledger (SE-493). Los cuatro STOP actuales no desaparecen: pasan a ser **adaptadores** que reciben la orden global y confirman que la aplicaron.

## Alternativas

| Opción | Por qué no |
|---|---|
| Un `pkill` de todo lo que huela a agente | Mata procesos, no revoca grants ni clasifica efectos en vuelo. Un ejecutor que arranca después no se entera. |
| Un fichero STOP global que cada ejecutor lee | Sin época, un grant viejo sigue valiendo tras reanudar. Sin acuses, nadie sabe si todos lo leyeron. |
| Revocar solo en SE-496 (`REVOKED` por nonce) | Revoca contratos uno a uno; no para colas, ni workers, ni Soul, ni Yema. Es una pieza, no el STOP. |
| **Plano de control con época y adaptadores** (elegida) | Una sola orden, una época que invalida todo lo anterior, acuses por ejecutor y reanudación con revalidación. |

## Requisitos

### R1 — Estado del plano de control

`scripts/savia-control.py` (Python stdlib, `python3 -I`) mantiene en `${SAVIA_CONTROL_DIR:-$HOME/.savia/control}`:

- `state.json`: `{mode, epoch, scopes, since, reason}`. `mode` ∈ `RUNNING | PAUSED | REVOKED | QUARANTINED`. `scopes` lista los ámbitos afectados: `global`, `principal:<id>`, `contract:<id>`, `executor:<nombre>`.
- `control.jsonl`: diario de cada orden y cada acuse, con `prev_sha256` encadenado como el audit de SE-496.
- `acks/<executor>.json`: último acuse de cada ejecutor registrado.
- `executors.json`: ejecutores registrados en la instalación, con su adaptador.

Escritura atómica (fichero temporal + `rename` + `fsync`). Fail-closed: un `state.json` ilegible, vacío o con campos desconocidos cuenta como `REVOKED` global, igual que el STOP de Soul.

### R2 — Época de revocación

- `epoch` es un entero que solo crece. Cada `revoke` lo incrementa en 1. `pause` y `quarantine` no lo cambian.
- **Época efectiva** = máximo entre la local (`state.json`), la más alta del diario y `config/control/REVOCATION_EPOCH` en `origin/main`. Bajar el número en un fichero no baja la época efectiva mientras otro de los tres sea mayor.
- Todo grant, contrato de delegación (SE-496), lease y registro del Effect Ledger (SE-493) lleva `issued_epoch`. Vale solo si `issued_epoch` es igual a la época efectiva. Uno con `issued_epoch` mayor que la efectiva se trata como falsificado: se deniega.
- Límite, igual que en SE-496: la copia local la puede escribir el mismo usuario que ejecuta al agente. Contra un agente comprometido, la época autoritativa es la de `origin/main`; la local protege frente a errores y carreras, no frente a sabotaje.

`savia-control.py epoch` imprime la época efectiva y sale 0; si no puede leer alguna fuente local, sale 2 (fail-closed). Sin red, `origin/main` se lee del último `fetch` y el resultado lo dice.

### R3 — Las cinco operaciones

| Operación | Efecto | Quién puede |
|---|---|---|
| `pause [--scope S] --reason R` | Cierra reservas nuevas: el Effect Ledger deja de dar `PROCEED` y el kernel deja de dar `ALLOW` en el ámbito. Lo que ya está en `DISPATCHED` termina su llamada y se registra. Los grants siguen siendo válidos. | Cualquiera, agentes incluidos (parar siempre se permite). |
| `revoke [--scope S] --reason R` | Todo lo de `pause`, más: incrementa la época, invalida grants y contratos emitidos antes, y ordena a cada adaptador su revocación nativa (R4). | Cualquiera. Revocar solo restringe. |
| `quarantine <executor|run> --reason R` | El ejecutor queda aislado: no recibe tareas, sus efectos pendientes pasan a revisión y sus ramas y PR quedan marcadas como no fusionables hasta revisión humana. | Cualquiera. |
| `reconcile` | Recorre lo que estaba en vuelo al parar (R5) y clasifica cada efecto. No ejecuta efectos nuevos. | Cualquiera. Solo lee y clasifica. |
| `resume [--scope S]` | Vuelve a `RUNNING` si se cumplen las condiciones de R6. | Solo la operadora (R6). |

`pause` sin `--scope` equivale a `global`. Un ámbito más estrecho nunca levanta uno más amplio: `resume --scope executor:x` con un `revoke` global vigente no hace nada y lo dice.

### R4 — Propagación con acuse

Cada ejecutor registrado tiene un adaptador con dos funciones: `halt(epoch, mode, reason)` y `status()`. El plano de control llama a todos los adaptadores en cada `pause`, `revoke` o `quarantine`, y registra el acuse que devuelven: `{executor, epoch, native_state, at}`.

| Ejecutor | `halt` en `pause` | `halt` en `revoke` |
|---|---|---|
| merge-sprint (S1) | `merge-sprint.sh stop` | `stop` + `revoke` (mueve el grant) |
| Soul (S2), misma máquina | `soul stop "<motivo>"` | ídem: Soul no tiene grants que revocar |
| Yema (S3) | `yema suspender <activo> --por savia --motivo …` | `yema revocar <activo> --por savia --motivo …` |
| Bucle nocturno (S4) | no lanza la tarea siguiente; consulta antes de cada una | ídem, y mata la tarea en curso |
| Workers `claude -p` / OpenCode | el gate de R7 deniega herramientas con efecto | ídem |

Reglas:

- `savia-control.py status` sale 0 solo si todos los ejecutores registrados acusaron la época y el modo vigentes. Si falta alguno, sale 3 con `PROPAGATION_INCOMPLETE` y la lista.
- Un adaptador que falla o no responde en `SAVIA_CONTROL_ACK_TIMEOUT_S` (por defecto 10) queda sin acuse. No se reintenta en silencio: se reintenta una vez y queda en el diario.
- Cada adaptador comprueba además la época en su propio bucle, antes de cada efecto. El acuse dice que la orden llegó; la comprobación local es la que impide el efecto aunque la orden no llegara.
- Un ejecutor que arranca o se reconecta lee la época efectiva antes de su primer efecto. Si su grant es de una época anterior, no lo usa.

### R5 — Clasificación de lo que estaba en vuelo

`reconcile` lee el Effect Ledger (SE-493) y deja cada efecto abierto en una de cuatro clases:

| Clase | Estado de SE-493 | Significado |
|---|---|---|
| `CONFIRMED` | `SUCCEEDED` con recibo | El efecto ocurrió. |
| `REJECTED` | `FAILED` con sonda `ABSENT` definitiva | El efecto no ocurrió. |
| `COMPENSATED` | `SUCCEEDED` + efecto compensatorio `SUCCEEDED` enlazado | Ocurrió y se deshizo por un mecanismo real. |
| `INDETERMINATE` | `DISPATCHED`, `NEEDS_REVIEW`, `IN_FLIGHT` | No se sabe. Nunca se informa como «no ocurrió». |

`reconcile` usa las sondas de SE-493; no inventa una propia. Un efecto `INDETERMINATE` queda así hasta que una sonda o una persona lo resuelva con evidencia (`effect-ledger.py resolve`). El informe dice, para cada efecto irreversible, qué no se puede deshacer.

### R6 — Reanudar

`resume` solo procede si:

1. Lo ordena la operadora: aprobación por fusión de PR (SE-488) o, mientras SE-488 no exista, una terminal interactiva con confirmación del texto del ámbito. Un agente que invoca `resume` recibe exit 4 y nada cambia.
2. `reconcile` corrió después del último `pause` o `revoke` y no queda ningún efecto `INDETERMINATE` en el ámbito, o la operadora los acepta uno a uno por su `effect_id`.
3. Tras un `revoke`: cada ejecutor vuelve con grants emitidos en la época nueva. Los anteriores siguen inválidos; reanudar no los resucita.
4. Tras un `pause`: cada ejecutor revalida su grant con el kernel (`recheck` de SE-496) antes de su primer efecto. Que el proceso vuelva a arrancar no basta.

Los reintentos tras reanudar tienen presupuesto: los efectos que volvieron a `FAILED` por la parada se reintentan como `attempt+1` de SE-493, como mucho `AGENT_MAX_CONSECUTIVE_FAILURES` veces, nunca en bucle.

### R7 — Gate por frontend

Un hook `PreToolUse` (`.claude/hooks/control-plane-gate.sh`) y su port de OpenCode leen el estado con `savia-control.py check --executor <id>` y, si el modo no es `RUNNING` para ese ejecutor, deniegan `Bash`, `Edit`, `Write` y herramientas MCP con efecto. Quedan permitidas las lecturas y las órdenes del propio plano de control (`status`, `reconcile`, `epoch`). La entrada del hook llega por stdin (JSON). Si `savia-control.py` no responde o falta `python3`, el gate deniega (fail-closed).

### R8 — Consultas desde SE-496 y SE-493

Esta spec define la interfaz; las enmiendas de texto en SE-496 y SE-493 se hacen en sus propias PR.

- **Kernel de autoridad (SE-496).** Dos comprobaciones `forbid` nuevas tras la de `REVOKED` (paso 5): `HALTED` si el modo del ámbito no es `RUNNING`, y `EPOCH_REVOKED` si `issued_epoch` del contrato no es la época efectiva. La época efectiva entra en `state_digest`, de modo que un `revoke` entre `evaluate` y `recheck` cambia el digest y bloquea la ejecución.
- **Effect Ledger (SE-493).** `prepare` y `dispatch` consultan el plano de control. Con el ámbito parado, `prepare` devuelve un exit nuevo, `HALTED` (7), y no reclama la clave. `dispatch` comprueba la época dentro de la misma transacción del write-ahead: si cambió desde `prepare`, no pasa a `DISPATCHED`. Cada registro guarda `epoch`.
- Ni el kernel ni el ledger cachean la época. Cada consulta la lee.

## Criterios de aceptación

Tests BATS con un remoto simulado que cuenta peticiones de efecto (el stub de `gh` de SE-493), un `SAVIA_CONTROL_DIR` temporal por test y adaptadores de prueba que registran sus llamadas. Cada test debe fallar contra el código de main o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes y después.

- **AC-1 — ADV-09: STOP durante una llamada remota.** El stub de `gh pr merge` se bloquea en una FIFO. Con la llamada en vuelo se ejecuta `pause` y después `revoke`. Al liberar la FIFO:
  - el efecto en vuelo queda `CONFIRMED` o `INDETERMINATE`, nunca ausente del informe de `reconcile`;
  - el siguiente efecto de la cola no se despacha: el contador del stub sigue en 1;
  - con `revoke` entre `prepare` y `dispatch`, `dispatch` no escribe `DISPATCHED` y el contador sigue en 0.
  - Negativo: sin la parada, el segundo efecto se despacha (contador 2).
- **AC-2 — ADV-10: revocación durante un flujo paralelo.** Tres ejecutores de prueba (merge-sprint con stub, Yema con su CLI en un directorio temporal, un worker con el gate de R7) corren en paralelo. Tras `revoke`:
  - los tres acusan la época nueva y `status` sale 0;
  - cualquier intento de efecto posterior de los tres es denegado: el contador del stub no crece y el marcador del worker no se crea;
  - un ejecutor que se reconecta con un grant de la época anterior es denegado con `EPOCH_REVOKED`.
  - Negativo: con el adaptador de uno de los tres roto, `status` sale 3 con `PROPAGATION_INCOMPLETE` y lo nombra, y ese ejecutor tampoco produce efectos, porque comprueba la época en su bucle.
- **AC-3 — ADV-18: cambio de permisos con el servicio en marcha.** Con un bucle de efectos en marcha, se cambia la configuración de permisos (el ámbito del contrato de SE-496 o el grant del merge-sprint):
  - el siguiente efecto se revalida y se deniega o pide aprobación, sin reiniciar el servicio;
  - reiniciar el servicio no lo evita: tras el reinicio, el efecto sigue denegado;
  - bajar a mano la época en `state.json` con una época mayor en el diario o en `origin/main` no cambia la época efectiva.
  - Negativo: un cambio en configuración que ninguna precondición referencia no deniega el efecto (sin falsos bloqueos).
- **AC-4 — Reanudar exige revalidar.** Tras `revoke` + `reconcile` limpio + `resume`, un grant emitido antes del `revoke` sigue denegado; uno emitido en la época nueva pasa. Tras `pause` + `resume`, el ejecutor llama a `recheck` antes del primer efecto (el registro de llamadas lo muestra).
- **AC-5 — Ningún efecto incierto se informa como ausente.** Con un efecto en `NEEDS_REVIEW`, `reconcile` lo clasifica `INDETERMINATE` y `resume` sale con error mientras no se resuelva o la operadora lo acepte por su `effect_id`.
- **AC-6 — Solo la operadora reanuda.** `resume` sin terminal interactiva ni aprobación SE-488 sale 4 y `state.json` no cambia. `pause`, `revoke` y `quarantine` funcionan sin terminal.
- **AC-7 — Fail-closed.** `state.json` corrupto, vacío o ausente con diario presente: `check` deniega y `status` lo informa. Sin `python3` en `PATH`, el gate de R7 deniega.
- **AC-8 — Época monótona.** `revoke` dos veces da épocas E+1 y E+2. Un grant con `issued_epoch` mayor que la efectiva es denegado.
- **AC-9 — Ámbitos.** `pause --scope executor:a` frena a `a` y no a `b`. `resume --scope executor:a` con un `revoke` global vigente no cambia nada y lo dice.
- **AC-10 — Time-box sin `timeout`.** El bucle nocturno sin `timeout` en `PATH` no lanza la tarea: sale con error en lugar de correr sin límite (cierra el fallo abierto de S4).

## Métricas

Se miden en el banco de AC-1 a AC-3, por entorno, sin fijar SLA hasta tener datos:

- tiempo desde `revoke` hasta el último acuse;
- efectos despachados después de `revoke` (objetivo: 0 en el banco);
- efectos en vuelo sin clase tras `reconcile` (objetivo: 0);
- falsos bloqueos en casos benignos;
- coste añadido por efecto (lectura de la época).

## Fuera de alcance

- Propagar entre máquinas. Soul en el portátil de trabajo (SE-490) recibe la parada solo si comparte instalación; el envío por su canal es una spec aparte. Mientras tanto, `status` lo lista como ejecutor remoto sin acuse.
- Deshacer efectos irreversibles. `reconcile` dice qué no se puede deshacer; no lo intenta.
- Sustituir los cuatro STOP nativos. Siguen funcionando solos; el global se apoya en ellos.
- Editar SE-493 y SE-496. R8 define la interfaz; sus enmiendas van en sus PR.
- Revocar credenciales de proveedores externos (tokens de GitHub, de Azure DevOps). El adaptador lo registra como pendiente manual.

## Dependencias

SE-493 (Effect Ledger) y SE-496 (kernel de autoridad) están PROPOSED en PR abiertas (#1455 y #1452). F0 y F1 no dependen de ellas; F3 sí. SE-488 aporta la aprobación de `resume` desde el móvil; hasta entonces, terminal interactiva.

## Plan por slices

| Fase | Contenido | Depende de |
|---|---|---|
| F0 | `savia-control.py` (estado, época, diario, cinco operaciones, `check`, `status`) y tests AC-6 a AC-9 | — |
| F1 | Adaptadores merge-sprint, bucle nocturno (con AC-10), Yema y Soul local; AC-2 con stubs | F0 |
| F2 | Gate de R7 en Claude Code y OpenCode | F0 |
| F3 | Integración con SE-493 y SE-496 (R8), AC-1, AC-3, AC-4, AC-5 | F0, SE-493, SE-496 |
| F4 | Banco ADV completo y métricas medidas | F1–F3 |

El adaptador de Yema se implementa en el repo de Yema con su flujo (rama `agent/*` y PR que fusiona la operadora).

## Riesgos

- **Parada por un agente.** Cualquier agente puede parar todo. Es intencional: parar solo restringe. Queda en el diario con el motivo.
- **Agente comprometido.** Puede reescribir el estado local. La época de `origin/main` y el gate de cada frontend acotan el daño; no lo eliminan.
- **Terminal como prueba de persona.** Un agente puede abrir una pseudo-terminal. Por eso la vía buena para `resume` es SE-488; la terminal es transitoria.
- **Coste por efecto.** Cada efecto lee la época. Se mide en F4.

## Rollback

Revertir la PR deja los cuatro STOP nativos como están hoy. El directorio `~/.savia/control` queda inerte.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Plano de control | `scripts/savia-control.py` | el mismo script |
| Gate de herramientas | `.claude/hooks/control-plane-gate.sh` (PreToolUse Bash, Edit, Write, MCP) | `.opencode/plugins/guards/control-plane-gate.ts` en `tool.execute.before`, que llama a `savia-control.py check` con `execFile` |
| Adaptadores | `scripts/control-adapters/*.sh` | los mismos: no dependen del frontend |
| Comando de operadora | `.claude/commands/stop-all.md` (pause, revoke, status, reconcile) | `.opencode/commands/stop-all.md`, mismo texto |

### Verification protocol

- [ ] Test que da la misma entrada (JSON por stdin) al gate bash y al TS y espera el mismo veredicto en `RUNNING`, `PAUSED`, `REVOKED` y estado corrupto.
- [ ] Ningún port reimplementa la lectura de la época: los dos invocan `savia-control.py` con `python3 -I`.
- [ ] Con el plugin de OpenCode cargado tras `savia-gates`, `bash` con efecto queda denegado en `PAUSED`.

### Portability classification

- [x] **DUAL_BINDING**: la lógica vive en un script común; cada frontend solo registra el gate.
