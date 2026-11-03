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

Estado ausente, caso por caso:

| `state.json` | `control.jsonl` | Resultado |
|---|---|---|
| ausente | ausente | Instalación nueva: `RUNNING` con época = época de `origin/main` (0 si el fichero no existe). La primera orden crea ambos ficheros. |
| ausente | presente | Alguien borró el estado: `REVOKED` global hasta `resume`. |
| presente y válido | ausente | Se acepta el estado, `status` avisa `JOURNAL_MISSING` y la siguiente orden crea un diario nuevo cuyo primer registro cita el `state.json` vigente. |

### R2 — Época de revocación

- `epoch` es un entero que solo crece y es **única y global** por instalación. Cada `revoke` la incrementa en 1. `pause` y `quarantine` no la cambian. No hay épocas por ámbito: por eso `revoke` es siempre global (R3).
- **Época efectiva** = máximo entre la local (`state.json`), la más alta del diario y `config/control/REVOCATION_EPOCH` en `origin/main`. Bajar el número en un fichero no baja la época efectiva mientras otro de los tres sea mayor.
- **Lectura de `origin/main`**: `git show origin/main:config/control/REVOCATION_EPOCH`, nunca `source` ni `eval`. El contenido debe casar con `^[0-9]+\n?$`; cualquier otra cosa cuenta como fuente ilegible (exit 2). Fichero ausente en `origin/main` = 0.
- **Quién escribe `REVOCATION_EPOCH` en `origin/main`.** Tras cada `revoke`, `savia-control.py` deja la época nueva pendiente de publicar y `savia-control.py publish-epoch` prepara una rama `agent/control-epoch-<N>` con el fichero subido a `N` y abre una PR. Cualquiera puede abrirla, porque subir la época solo restringe; la fusiona la operadora. Hasta que se fusiona, la época efectiva ya es `N` en esa instalación por la copia local. Un test de CI (`tests/test-control-epoch-monotonic.bats`) rechaza cualquier PR que baje el número o que no sea un entero.
- **Portador de `issued_epoch`.** Todo grant, contrato de delegación (SE-496), lease y registro del Effect Ledger (SE-493) lleva `issued_epoch`. Vale solo si `issued_epoch` es igual a la época efectiva. Uno con `issued_epoch` mayor que la efectiva se trata como falsificado: se deniega. Un grant sin el campo (formatos actuales) vale como `issued_epoch: 0`: sigue funcionando mientras la época efectiva sea 0 y queda inválido tras el primer `revoke`. Los formatos concretos se amplían así:
  - grant de merge-sprint: campo `issued_epoch` en el fichero de grant, escrito por `merge-sprint.sh grant` (F1, en este repo);
  - contrato de SE-496: en su PR (R8);
  - contrato de Yema: en el repo de Yema, con su flujo (F1-Yema). Mientras no exista, el adaptador de Yema solo puede revocar el contrato activo de forma nativa; la comprobación de época en el bucle de Yema y su caso de reconexión quedan en esa PR, no en este repo.
- Límite, igual que en SE-496: la copia local la puede escribir el mismo usuario que ejecuta al agente. Contra un agente comprometido, la época autoritativa es la de `origin/main`; la local protege frente a errores y carreras, no frente a sabotaje.

`savia-control.py epoch` imprime la época efectiva y sale 0; si no puede leer alguna fuente local o el contenido de `origin/main` no es un entero, sale 2 (fail-closed). Sin red, `origin/main` se lee del último `fetch` y el resultado lo dice.

### R3 — Las cinco operaciones

| Operación | Efecto | Quién puede |
|---|---|---|
| `pause [--scope S] --reason R` | Cierra reservas nuevas: el Effect Ledger deja de dar `PROCEED` y el kernel deja de dar `ALLOW` en el ámbito. Lo que ya está en `DISPATCHED` termina su llamada y se registra. Los grants siguen siendo válidos. | Cualquiera, agentes incluidos (parar siempre se permite). |
| `revoke --reason R` | Todo lo de `pause` en ámbito `global`, más: incrementa la época, invalida grants y contratos emitidos antes, y ordena a cada adaptador su revocación nativa (R4). Siempre global: `revoke --scope …` sale 2 sin tocar el estado. Para retirar a un solo ejecutor se usa `quarantine`; para un contrato concreto, el `REVOKED` por nonce de SE-496. | Cualquiera. Revocar solo restringe. |
| `quarantine <executor|run> --reason R` | El ejecutor queda aislado: no recibe tareas, sus efectos pendientes pasan a revisión y sus ramas y PR quedan marcadas como no fusionables hasta revisión humana. | Cualquiera. |
| `reconcile` | Recorre lo que estaba en vuelo al parar (R5) y clasifica cada efecto. No ejecuta efectos nuevos. | Cualquiera. Solo lee y clasifica. |
| `resume [--scope S]` | Vuelve a `RUNNING` si se cumplen las condiciones de R6. | Solo la operadora (R6). |

`pause` sin `--scope` equivale a `global`. Un ámbito más estrecho nunca levanta uno más amplio: `resume --scope executor:x` con un `revoke` global vigente no hace nada y lo dice.

`--reason` es obligatorio en `pause`, `revoke` y `quarantine`: vacío, solo espacios o más de 500 bytes sale 2 sin tocar el estado. El motivo y el actor (`SAVIA_ACTOR` o el usuario del proceso) quedan en el diario. No se limita la frecuencia de las órdenes de parada: un límite podría bloquear justo la parada legítima que hace falta, y el abuso (un agente que pausa sin parar) queda visible en el diario y lo revierte la operadora con `resume`.

**Códigos de salida de `savia-control.py`** (únicos en todo el script):

| Exit | Significado |
|---|---|
| 0 | Éxito; en `check`, el ejecutor puede producir efectos (`RUNNING` en su ámbito y época vigente) |
| 2 | Error de uso o fuente ilegible (fail-closed) |
| 3 | `status`: `PROPAGATION_INCOMPLETE` o `RESUME_INCOMPLETE` |
| 4 | `resume` sin aprobación de la operadora |
| 5 | `resume` con efectos `INDETERMINATE` no aceptados |
| 6 | `check`: ámbito parado (`PAUSED`, `REVOKED` o `QUARANTINED`); imprime modo, ámbito y motivo |

El código 7 (`HALTED`) es del Effect Ledger (R8), no de este script.

### R4 — Propagación con acuse

Cada ejecutor registrado tiene un adaptador con tres funciones: `halt(epoch, mode, reason)`, `resume(epoch)` y `status()`. El plano de control llama a `halt` de todos los adaptadores en cada `pause`, `revoke` o `quarantine`, y a `resume` en cada `resume` que procede (R6). Registra el acuse que devuelven: `{executor, epoch, native_state, at, pending_manual}`. `native_state` ∈ `RUNNING | STOPPED`; `pending_manual` es la orden exacta que una persona tiene que ejecutar cuando el adaptador no puede levantar su STOP nativo.

| Ejecutor | `halt` en `pause` | `halt` en `revoke` | `resume` |
|---|---|---|---|
| merge-sprint (S1) | `merge-sprint.sh stop` | `stop` + `revoke` (mueve el grant) | No levanta nada: el STOP con motivo de S1 solo lo levanta un grant nuevo, que emite la operadora en la época vigente. Devuelve `STOPPED` con `pending_manual: "merge-sprint.sh grant …"`. |
| Soul (S2), misma máquina | `soul stop "<motivo>"` | ídem: Soul no tiene grants que revocar | No puede: un agente no reanuda Soul (`cli.ts:52`). Devuelve `STOPPED` con `pending_manual: "soul resume"`. |
| Yema (S3) | `yema suspender <activo> --por savia --motivo …` | `yema revocar <activo> --por savia --motivo …` | No puede: reactivar exige persona en terminal (inventario S3). Devuelve `STOPPED` con `pending_manual` = la orden de reactivación de Yema. |
| Bucle nocturno (S4) | no lanza la tarea siguiente; consulta antes de cada una | ídem, y mata la tarea en curso | Nada que levantar: vuelve a lanzar tareas porque `check` sale 0. Devuelve `RUNNING`. |
| Workers `claude -p` / OpenCode | el gate de R7 deniega herramientas con efecto | ídem | Nada que levantar: el gate vuelve a permitir. Devuelve `RUNNING`. |

El plano de control no intenta saltarse los STOP nativos que exigen persona: eso rompería las garantías de S1, S2 y S3. Reanudar el plano y reanudar cada ejecutor son pasos distintos, y `status` dice cuál falta.

Reglas:

- `savia-control.py status` sale 0 solo si todos los ejecutores registrados acusaron la época y el modo vigentes **y** su `native_state` coincide con el modo (`STOPPED` si está parado, `RUNNING` si está en marcha). Si falta algún acuse tras una parada, sale 3 con `PROPAGATION_INCOMPLETE` y la lista. Si tras un `resume` algún ejecutor sigue `STOPPED`, sale 3 con `RESUME_INCOMPLETE`, la lista y la orden `pending_manual` de cada uno. Cada `status` vuelve a llamar a `status()` del adaptador, de modo que cuando la persona ejecuta `soul resume` el siguiente `status` lo refleja.
- Un adaptador que falla o no responde en `SAVIA_CONTROL_ACK_TIMEOUT_S` (por defecto 10) queda sin acuse. No se reintenta en silencio: se reintenta una vez y queda en el diario.
- Cada adaptador comprueba además la época en su propio bucle, antes de cada efecto. El acuse dice que la orden llegó; la comprobación local es la que impide el efecto aunque la orden no llegara.
- Un ejecutor que arranca o se reconecta lee la época efectiva antes de su primer efecto. Si su grant es de una época anterior, no lo usa.

### R5 — Clasificación de lo que estaba en vuelo

`reconcile` lee el Effect Ledger (SE-493) y deja cada efecto abierto en una de cuatro clases. La clasificación es total: lo que no casa con una fila concreta es `INDETERMINATE`.

| Clase | Estado de SE-493 | Significado |
|---|---|---|
| `CONFIRMED` | `SUCCEEDED` con recibo | El efecto ocurrió. |
| `REJECTED` | `FAILED` con sonda `ABSENT` definitiva, o `PREPARED` que nunca pasó a `DISPATCHED` con su ámbito parado al clasificar | El efecto no ocurrió ni puede ocurrir. Lo garantiza el write-ahead de R8: `DISPATCHED` se escribe antes de la llamada remota, y `dispatch` no lo escribe con el ámbito parado. Un `PREPARED` cuyo ámbito ya no está parado es `INDETERMINATE`, porque podría despacharse después de clasificarlo. |
| `COMPENSATED` | `SUCCEEDED` + efecto compensatorio `SUCCEEDED` enlazado | Ocurrió y se deshizo por un mecanismo real. |
| `INDETERMINATE` | `DISPATCHED`, `NEEDS_REVIEW`, `IN_FLIGHT`, `SUCCEEDED` sin recibo, `FAILED` sin sonda definitiva, y cualquier estado o combinación no listada arriba | No se sabe. Nunca se informa como «no ocurrió». |

`reconcile` usa las sondas de SE-493; no inventa una propia. Un efecto `INDETERMINATE` queda así hasta que una sonda o una persona lo resuelva con evidencia (`effect-ledger.py resolve`). El informe dice, para cada efecto irreversible, qué no se puede deshacer.

### R6 — Reanudar

`resume` solo procede si:

1. Lo ordena la operadora, por una de dos vías:
   - **Fusión de PR.** La PR añade `config/control/resume/<epoch>-<ámbito>.json` con `{epoch, scope, reason}`. `savia-control.py resume --via-pr` hace `git fetch`, lee el fichero con `git show origin/main:<ruta>` y comprueba que `epoch` es la época efectiva y `scope` el pedido. Un fichero de una época anterior no sirve (no se reutiliza). La prueba de que fue la operadora es que solo ella fusiona en `main`. `savia-control.py` lo comprueba en cada `resume --via-pr` consultando con `gh api` las reglas de `main` (PR obligatoria, sin bypass para otros actores) y que el autor de la fusión del commit que añadió el fichero es la operadora configurada (`AUTONOMOUS_REVIEWER`/perfil local). Si la consulta falla, no hay red, falta `gh` o la regla no está activa, sale 4 (fail-closed). Con SE-488 esta vía pasa a ser su aprobación firmada.
   - **Terminal interactiva**, mientras SE-488 no exista: `stdin` y `stdout` son TTY y la persona teclea el texto exacto del ámbito.
   
   Un agente que invoca `resume` sin ninguna de las dos recibe exit 4 y nada cambia.
2. `reconcile` corrió después del último `pause` o `revoke` y no queda ningún efecto `INDETERMINATE` en el ámbito, o la operadora los acepta uno a uno por su `effect_id`.
3. Tras un `revoke`: cada ejecutor vuelve con grants emitidos en la época nueva. Los anteriores siguen inválidos; reanudar no los resucita.
4. Tras un `pause`: cada ejecutor revalida su grant con el kernel (`recheck` de SE-496) antes de su primer efecto. Que el proceso vuelva a arrancar no basta.
5. Con el modo ya en `RUNNING`, el plano llama a `resume(epoch)` de cada adaptador (R4). Los que no pueden levantar su STOP nativo dejan su `pending_manual` y `status` sale 3 con `RESUME_INCOMPLETE` hasta que la persona los levanta. `resume` informa de esa lista al terminar; no la oculta tras un exit 0 del plano.

Los reintentos tras reanudar tienen presupuesto: los efectos que volvieron a `FAILED` por la parada se reintentan como `attempt+1` de SE-493, como mucho `AGENT_MAX_CONSECUTIVE_FAILURES` veces, nunca en bucle.

### R7 — Gate por frontend

Un hook `PreToolUse` (`.claude/hooks/control-plane-gate.sh`) y su port de OpenCode leen el estado con `savia-control.py check --executor <id>`. Con exit 0 permiten; con cualquier otro código deniegan `Bash`, `Edit`, `Write` y herramientas MCP con efecto. El mensaje distingue «ámbito parado» (exit 6, con modo y motivo) de «error del plano de control» (cualquier otro código, con el código). Si `savia-control.py` no responde o falta `python3`, el gate deniega (fail-closed). La entrada del hook llega por stdin (JSON).

Quedan permitidas las lecturas (`Read`, `Glob`, `Grep`) y las órdenes del propio plano de control (`status`, `reconcile`, `epoch`, `pause`, `revoke`, `quarantine`). Una orden `Bash` solo cuenta como del plano de control si es **exactamente** una invocación `python3 -I scripts/savia-control.py <subcomando> [argumentos]`, sin ninguno de estos caracteres en todo el comando: `; | & $ \` < > ( )` ni saltos de línea. Cualquier otra forma, incluida `savia-control.py status; <orden>` o una sustitución `$(…)`, se deniega. La comparación es por tokens con `shlex`, no por prefijo de texto.

### R8 — Consultas desde SE-496 y SE-493

Esta spec define la interfaz; las enmiendas de texto en SE-496 y SE-493 se hacen en sus propias PR.

- **Kernel de autoridad (SE-496).** Dos comprobaciones `forbid` nuevas tras la de `REVOKED` (paso 5): `HALTED` si el modo del ámbito no es `RUNNING`, y `EPOCH_REVOKED` si `issued_epoch` del contrato no es la época efectiva. La época efectiva entra en `state_digest`, de modo que un `revoke` entre `evaluate` y `recheck` cambia el digest y bloquea la ejecución.
- **Effect Ledger (SE-493).** `prepare` y `dispatch` consultan el plano de control. Con el ámbito parado, `prepare` devuelve un exit nuevo, `HALTED` (7), y no reclama la clave. `dispatch` comprueba modo y época dentro de la misma transacción del write-ahead: si el ámbito está parado o la época cambió desde `prepare`, no pasa a `DISPATCHED`. Cada registro guarda `epoch`.
- Ni el kernel ni el ledger cachean la época. Cada consulta la lee.

## Criterios de aceptación

Tests BATS con un remoto simulado que cuenta peticiones de efecto (el stub de `gh` de SE-493), un `SAVIA_CONTROL_DIR` temporal por test y adaptadores de prueba que registran sus llamadas. Cada test debe fallar contra el código de main o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes y después.

- **AC-1 — ADV-09: STOP durante una llamada remota.** El stub de `gh pr merge` se bloquea en una FIFO. Con la llamada en vuelo se ejecuta `pause` y después `revoke`. Al liberar la FIFO:
  - si el stub devuelve éxito con recibo, el efecto en vuelo queda `CONFIRMED`; en la variante en que el stub muere sin responder, queda `INDETERMINATE`. Cada variante afirma su clase exacta, y en ninguna el efecto falta del informe de `reconcile`;
  - el siguiente efecto de la cola no se despacha: el contador del stub sigue en 1;
  - con `revoke` entre `prepare` y `dispatch`, `dispatch` no escribe `DISPATCHED` y el contador sigue en 0.
  - Negativo: sin la parada, el segundo efecto se despacha (contador 2).
- **AC-2 — ADV-10: revocación durante un flujo paralelo.** Tres ejecutores de prueba (merge-sprint con stub, Yema con su CLI en un directorio temporal, un worker con el gate de R7) corren en paralelo. Tras `revoke`:
  - los tres acusan la época nueva y `status` sale 0;
  - cualquier intento de efecto posterior de los tres es denegado: el contador del stub no crece y el marcador del worker no se crea;
  - el merge-sprint y el worker, al reconectarse con un grant de la época anterior (`issued_epoch` = E), son denegados con `EPOCH_REVOKED`; un grant de la época nueva pasa. El caso equivalente de Yema (comprobación de época en su bucle) se prueba en la PR de Yema (R2), no aquí;
  - Negativo: con el adaptador del merge-sprint o del worker roto, `status` sale 3 con `PROPAGATION_INCOMPLETE` y lo nombra, y ese ejecutor tampoco produce efectos, porque comprueba la época en su bucle.
- **AC-3 — ADV-18: cambio de permisos con el servicio en marcha.** Con un bucle de efectos en marcha, se cambia la configuración de permisos (el ámbito del contrato de SE-496 o el grant del merge-sprint):
  - el siguiente efecto se revalida y se deniega o pide aprobación, sin reiniciar el servicio;
  - reiniciar el servicio no lo evita: tras el reinicio, el efecto sigue denegado;
  - bajar a mano la época en `state.json` con una época mayor en el diario o en `origin/main` no cambia la época efectiva.
  - Negativo: un cambio en configuración que ninguna precondición referencia no deniega el efecto (sin falsos bloqueos).
- **AC-4 — Reanudar exige revalidar.** Tras `revoke` + `reconcile` limpio + `resume`, un grant emitido antes del `revoke` sigue denegado; uno emitido en la época nueva pasa. Tras `pause` + `resume`, el ejecutor llama a `recheck` antes del primer efecto (el registro de llamadas lo muestra).
- **AC-5 — Ningún efecto incierto se informa como ausente.** Con un efecto en `NEEDS_REVIEW`, `reconcile` lo clasifica `INDETERMINATE` y `resume` sale 5 mientras no se resuelva o la operadora lo acepte por su `effect_id`. Con un registro en un estado que la tabla de R5 no lista (`SUCCEEDED` sin recibo, o un estado inventado en el fixture), la clase es `INDETERMINATE`. Con `PREPARED` sin `DISPATCHED` y el ámbito parado, la clase es `REJECTED` y un `dispatch` posterior no escribe `DISPATCHED` (contador del stub en 0); con el ámbito ya en `RUNNING`, la clase es `INDETERMINATE`.
- **AC-6 — Solo la operadora reanuda.** `resume` sin terminal interactiva ni aprobación por PR sale 4 y `state.json` no cambia. `resume --via-pr` con un fichero `config/control/resume/` de una época anterior, de otro ámbito o ausente en `origin/main` (remoto simulado) sale 4; con el fichero de la época vigente, la regla de `main` activa y la fusión hecha por la operadora (stub de `gh api`), procede. Negativo: mismo fichero con el stub de `gh api` fallando, devolviendo la regla inactiva o una fusión hecha por otro actor: sale 4 y `state.json` no cambia. `pause`, `revoke` y `quarantine` funcionan sin terminal.
- **AC-7 — Fail-closed y estado ausente.** `state.json` corrupto, vacío o ausente con diario presente: `check` sale 6 (`REVOKED`) y `status` lo informa. Sin `python3` en `PATH`, el gate de R7 deniega. `REVOCATION_EPOCH` en `origin/main` con contenido no entero (`3; rm`, `1e3`, vacío con espacios): `epoch` sale 2. Caso límite: sin `state.json` ni diario (instalación nueva), `check` sale 0 con la época de `origin/main`; si en `origin/main` la época es 5, `epoch` imprime 5.
- **AC-8 — Época monótona.** `revoke` dos veces da épocas E+1 y E+2. Un grant con `issued_epoch` mayor que la efectiva es denegado. Un grant sin campo `issued_epoch` pasa con época efectiva 0 y es denegado con época 1. `tests/test-control-epoch-monotonic.bats` falla con un diff que baja `REVOCATION_EPOCH` o lo deja no entero, y pasa con uno que lo sube.
- **AC-9 — Ámbitos.** `pause --scope executor:a` frena a `a` y no a `b`. `resume --scope executor:a` con un `revoke` global vigente no cambia nada y lo dice. `revoke --scope executor:a` sale 2 y ni la época ni `state.json` cambian. `quarantine a` frena a `a`, no cambia la época y deja válidos los grants de `b`.
- **AC-10 — Time-box sin `timeout` e inyección en S4.** El bucle nocturno sin `timeout` en `PATH` no lanza la tarea: sale con error en lugar de correr sin límite (cierra el fallo abierto de S4). Además, `overnight-sprint-loop.sh:291-292` deja de interpolar `$description` dentro de `bash -c "…"` y pasa los argumentos como posicionales (`bash -c '…' _ "$@"`): una descripción con comilla simple y `; touch <marcador>` no crea el marcador. Negativo: el test crea el marcador contra el código de main.
- **AC-11 — Reanudar cada ejecutor.** Tras `revoke` + `reconcile` limpio + `resume` aprobado, el registro de llamadas muestra `resume(epoch)` en todos los adaptadores. Con el adaptador de Soul de prueba devolviendo `STOPPED`, `status` sale 3 con `RESUME_INCOMPLETE`, nombra a Soul y su `pending_manual` (`soul resume`). Cuando el stub de Soul pasa a `RUNNING`, el siguiente `status` sale 0 sin otra orden. El bucle nocturno y el worker vuelven a producir efectos sin acción manual. Negativo: ningún adaptador de prueba de S1, S2 o S3 recibe una orden que levante su STOP nativo (el registro no contiene `soul resume`, `yema` de reactivación ni borrado del fichero STOP del merge-sprint).
- **AC-12 — Motivo obligatorio.** `pause`, `revoke` y `quarantine` con `--reason ""`, solo espacios, sin `--reason` o con más de 500 bytes salen 2 y `state.json` no cambia. Caso límite: 500 bytes exactos pasa.
- **AC-13 — Lista de permitidas del gate.** En `PAUSED`, el gate permite `python3 -I scripts/savia-control.py status` y deniega `python3 -I scripts/savia-control.py status; touch x`, `… status && touch x`, `… status $(touch x)`, `… status | sh` y la orden con un salto de línea seguido de otra. Ninguno de los denegados crea el marcador. El mismo conjunto da el mismo veredicto en el gate bash y en el TS.

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
| F0 | `savia-control.py` (estado, época, diario, cinco operaciones, `check`, `status`, `publish-epoch`), test de CI de época monótona, y tests AC-6 a AC-9 y AC-12 | — |
| F1 | Adaptadores (`halt`, `resume`, `status`) de merge-sprint, bucle nocturno (con AC-10), Yema y Soul local; campo `issued_epoch` en el grant de merge-sprint; AC-2 y AC-11 con stubs | F0 |
| F1-Yema | En el repo de Yema: `issued_epoch` en el contrato y comprobación de época en su bucle, con su caso de reconexión | F0 |
| F2 | Gate de R7 en Claude Code y OpenCode, con AC-13 | F0 |
| F3 | Integración con SE-493 y SE-496 (R8), AC-1, AC-3, AC-4, AC-5 | F0, SE-493, SE-496 |
| F4 | Banco ADV completo y métricas medidas | F1–F3 |

El adaptador de Yema se implementa en el repo de Yema con su flujo (rama `agent/*` y PR que fusiona la operadora).

## Riesgos

- **Parada por un agente.** Cualquier agente puede parar todo. Es intencional: parar solo restringe. Queda en el diario con el motivo.
- **Agente comprometido.** Puede reescribir el estado local. La época de `origin/main` y el gate de cada frontend acotan el daño; no lo eliminan.
- **Terminal como prueba de persona.** Un agente puede abrir una pseudo-terminal. Por eso la vía buena para `resume` es SE-488; la terminal es transitoria.
- **Coste por efecto.** Cada efecto lee la época. Se mide en F4.
- **Ventana de grants sin `issued_epoch`.** Los formatos actuales valen como época 0 hasta el primer `revoke`. Es aceptable porque el primer `revoke` los invalida todos; la alternativa (rechazarlos ya) rompería el merge-sprint antes de F1.
- **Época publicada con retraso.** Hasta que se fusiona la PR de `publish-epoch`, solo la instalación que revocó conoce la época nueva. Otras instalaciones (fuera de alcance: entre máquinas) no la ven hasta entonces.

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
