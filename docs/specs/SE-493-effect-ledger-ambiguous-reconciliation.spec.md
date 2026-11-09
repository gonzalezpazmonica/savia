---
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: A
risk: L3
human_surface: true
depends_on: [SE-387]
related_specs: [SE-387, SE-433, SE-343, SE-362, SE-488, SE-364]
origin: "Análisis de repositorios externos difundidos públicamente (2026-11-01), iniciativa SAVIA-RESEARCH-01 y validación V1 «efectos exactamente una vez». Patrón extraído de OpenRath (BSD-3-Clause, commit f39331700fb4), sin adoptar el producto. Afirmaciones del análisis contrastadas con main en fa3f486a0; citas fichero:línea re-ancladas en main 3e094038d (2026-11-03) y acompañadas del símbolo, porque merge-sprint.sh cambió entre ambos."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
---
# SE-493 — Effect Ledger y reconciliación de efectos ambiguos

## Problema

Un efecto externo (merge, publicación, mensaje, despliegue, borrado) puede quedar con **resultado incierto**: la petición salió, pero el proceso cayó o la respuesta no llegó antes de registrar el recibo. Si en ese estado se reintenta, el efecto puede ocurrir dos veces. SE-387 F5 prometió «exactly-once» con reserva, idempotencia y recibo; lo construido cubre el caso fácil (efecto cerrado → `ALREADY_EXECUTED`) y deja abierto el ambiguo.

### Qué dice el análisis y qué hay de verdad en el código

El análisis de origen señala `scripts/effect-reservation.sh` y advierte que su ruta para reservas pendientes «no prueba por sí sola que el efecto externo no ocurriera antes de un crash». Contrastado con main:

1. **El análisis apunta al script equivocado.** `effect-reservation.sh` **no tiene consumidores en tiempo de ejecución**. Solo lo nombran `scripts/coherence-gates.sh:45-52`, que comprueba que sea ejecutable y lo cuenta como `PASS coherence/closure-effect-reservation.sh`, y su test `tests/bats/f5-exactly-once.bats`. Es cobertura nominal: el gate de cierre de SE-387 pasa por la existencia de un fichero, justo el riesgo R2 («falsa cobertura») de SE-387.
2. **La advertencia es correcta y aplica al script que sí se usa.** El camino real es `scripts/f5-state.sh`, invocado por `scripts/push-pr.sh` y `scripts/merge-sprint.sh`.
3. **Respuesta a la pregunta clave: sí, hoy un efecto con resultado incierto puede repetirse sin que nada lo impida.** No hay doble ejecución observada; el riesgo está en el contrato.

Hallazgos con fichero:línea (main 3e094038d; entre paréntesis, el símbolo o la orden, que sobrevive a cambios de numeración):

| # | Dónde | Qué pasa | Consecuencia |
|---|---|---|---|
| H1 | `scripts/effect-reservation.sh:9-16` | Cualquier estado distinto de `closed` devuelve exit 0 y el texto «effect exactly-once». | Quien lo use reejecuta el efecto tras un crash. El test `f5-exactly-once.bats:29-33` fija ese comportamiento como correcto. |
| H2 | `scripts/f5-state.sh:24-28` | Con `submitted` y PR sin `MERGED` imprime «NO se solicita otro efecto», pero sale con **exit 0**, el mismo código que «adelante». | El texto dice «no»; el código dice «sí». `tests/bats/f5-cases.bats:32-46` fija ambos casos como «permite reanudar». |
| H3 | `scripts/push-pr.sh:274` y `:281` | Solo comprueba `reserve ... \|\| exit 3` y continúa a `gh pr merge`. | Al relanzar `push-pr.sh --merge` tras un crash o un error ambiguo, se vuelve a pedir el merge. |
| H4 | `scripts/push-pr.sh:281-288` | `mark_submitted` se escribe **después** de pedir el merge. | Una caída entre ambos deja `reserved`, indistinguible de «nunca se pidió» (caso b de V1 confundido con caso a). `merge-sprint.sh:616` (`f5 reserve … && f5 mark_submitted`) sí marca `submitted` antes de pedirlo; el defecto es solo de `push-pr`. |
| H5 | `scripts/push-pr.sh:281-284` | Cualquier fallo de `gh pr merge`, incluido un timeout tras aceptar el servidor, termina con «vuelve a ejecutar push-pr.sh --merge». | La herramienta invita a repetir en estado ambiguo. |
| H6 | `scripts/f5-state.sh:11` y `:49` | `pr_state` traga errores y devuelve `""`; `release` borra la reserva si el estado no es literalmente `MERGED`. `merge-sprint.sh:620` (`f5 release`) llama a `release` ante cualquier salida ≠ 0 de `gh pr merge`. | Un error de red tras un merge aceptado borra la reserva. El siguiente paso ve el PR mergeado sin reserva y para con `merge_externo` (`merge-sprint.sh:860-866`, `case "$(f5 status …)"`). Falla cerrado, pero pierde la procedencia: un merge propio pasa por ajeno y no queda recibo. |
| H7 | `scripts/f5-state.sh:15-30` | Comprueba la existencia del fichero y lo escribe sin cerrojo. | Dos workers con la misma clave pueden reservar los dos (caso f). |
| H8 | `scripts/push-pr.sh:273` y `scripts/merge-sprint.sh:563` (`f5()`) | `push-pr` usa `~/.savia/reservations`; `merge-sprint` usa `$HOME_MS/reservations/<digest>`. | Dos libros para el mismo efecto `pr.merge/N`: ninguno ve la reserva del otro. El cerrojo `run.lock` (`merge-sprint.sh:809`) solo serializa merge-sprint consigo mismo. |
| H9 | `scripts/f5-state.sh:8` | La clave es solo el número de PR; no hay huella de argumentos. El SHA pedido vive en un fichero aparte solo en merge-sprint (`:564` `resv_head`, escrito en `:616`) y no se comprueba al reservar. | Misma clave con otros argumentos (otro head) no se rechaza (caso d). |
| H10 | `scripts/f5-state.sh:42` | El «recibo» es `state=closed` y `closed_at`. | No contiene la evidencia remota (commit de merge, autor, head), no está encadenado y no se puede verificar después. El ledger de merge-sprint sí guarda `merge_commit` (`:643`, `record_merge`), pero no es el recibo F5. |

Matiz de impacto: hoy el único efecto bajo F5 es `pr.merge`, y GitHub lo limita por su cuenta: `--match-head-commit` y un PR ya mergeado no se mergea dos veces. Por eso H3-H5 no han causado daño. El problema es que SE-387 F5 declara el alcance «merge/deploy/publicación/delete/escritura externa», y cualquier efecto **no idempotente** que reutilice este contrato heredaría la reejecución.

## Patrón de referencia (OpenRath)

Leído en `src/rath/runtime/effects.py`, `src/rath/adapters/tool.py`, `src/rath/runtime/models.py`, `src/rath/server/app.py` y `tests/runtime/test_effect_ledger.py`, sin ejecutar nada:

- **Clase de efecto declarada por herramienta:** `none | read_only | idempotent | non_idempotent`.
- **Invocación con estados** `prepared → dispatched → succeeded | failed | ambiguous`. La transición a `dispatched` **se persiste antes** de llamar al efecto (write-ahead).
- **Huella SHA-256 de los argumentos** canonicalizados. Reutilizar la clave con otra huella es `ConflictError`.
- **Reconciliación de invocaciones `dispatched` caducadas** (umbral de gracia):
  - lo idempotente con clave vuelve a `prepared` y se puede reintentar;
  - lo demás pasa a `ambiguous` y la ejecución entera a `NEEDS_REVIEW`.
- **Reanudar desde `NEEDS_REVIEW`** exige `confirm=true` y queda auditado como intervención de la operadora.
- **Transacciones `BEGIN IMMEDIATE` y restricción única** `(run, clave)` contra la concurrencia.

Lo que **no** se copia, y por qué:

- **No hay un verbo para resolver la ambigüedad con evidencia.** Reanudar devuelve la ejecución a la cola, pero la invocación sigue `ambiguous`. Savia añade observación remota (sonda) y resolución atribuida.
- **No hay recibo verificable.** El resultado se guarda sin evidencia remota ni encadenado.
- **El timeout de un `non_idempotent` deja `dispatched` sin más.** Es correcto, pero depende de un reconciliador periódico que Savia no tiene. Aquí la reconciliación ocurre al siguiente intento sobre la misma clave.
- El runtime, el servidor y Postgres quedan fuera. Se extrae el protocolo, no el subsistema (regla 4 del análisis).

## Qué decide esta spec

Un único **Effect Ledger** local, con contrato explícito, sustituye a las dos reservas actuales. Ningún estado ambiguo devuelve «adelante».

### Contrato de efecto

Registro por efecto:

| Campo | Contenido |
|---|---|
| `effect_id` | UUID |
| `op` | operación registrada (`pr.merge`, …) |
| `idempotency_key` | clave estable elegida por quien llama (p. ej. `owner/repo#N`) |
| `args` / `args_digest` | JSON canónico de los argumentos que determinan el efecto (`sort_keys`, separadores compactos, UTF-8) y su SHA-256. Se guardan los dos para que la sonda compare campo a campo. Para `pr.merge`: repo, número, head SHA y método. Cada `op` declara cuáles de esos campos puede **observar** su sonda. En `pr.merge`, `gh pr view` muestra repo, número y `headRefOid`, pero no el método: el método entra en la huella (otro método es `CONFLICT`) y el recibo lo marca como `requested`, no verificado. El `digest` del manifiesto de merge-sprint y el `run_id` **no** entran en `args` ni en la huella: son metadatos del intento. Así `push-pr` y `merge-sprint` producen la misma huella para el mismo merge (AC-f, dos rutas). |
| `install_id` | UUID creado al inicializar el ledger y guardado en su tabla `meta`. Distingue dos instalaciones del mismo operador. |
| `claim_token`, `lease_until`, `holder_pid`, `holder_start` | quién tiene reclamada la clave y hasta cuándo (Regla 2b). `holder_pid` es el proceso **llamador** de larga vida, nunca el del CLI `effect-ledger.py`; `holder_start` es su hora de arranque (campo 22 de `/proc/<pid>/stat`) contra la reutilización de PID |
| `actor_remote` | identidad del actor en el remoto, obtenida al reclamar (Regla 6b). Para `pr.merge`, el login de `gh api user` |
| `review_origin` | de dónde llegó a `NEEDS_REVIEW`: `dispatched` (desde `DISPATCHED` de este ledger), `rejected` (`DISPATCHED` con rechazo anotado y luego `PRESENT`, 3e), `pre_probe` (sonda previa, 3c) o `migration` (importado). Decide si se puede cerrar sin grant (Regla 5) |
| `effect_class` | `read_only \| idempotent_remote \| non_idempotent`. Por defecto `non_idempotent`; `idempotent_remote` solo si el registro de operaciones lo declara con evidencia de que el remoto respeta la clave. |
| `actor` | identificador del perfil activo (como `operator-grant.sh`), nunca un nombre literal en código |
| `run_id`, `attempt`, `state`, marcas de tiempo | — |
| `observation` | última evidencia remota |
| `receipt` | recibo, si existe |

Unicidad: `(op, idempotency_key)`.

Estados y transiciones (las demás se rechazan):

```
PREPARED ──dispatch (CAS + sonda previa ABSENT)──▶ DISPATCHED ──ok confirmado / sonda PRESENT──▶ SUCCEEDED (terminal, con recibo)
   │                       │──sonda ABSENT definitiva pasada la gracia─▶ FAILED (sin efecto; admite attempt+1)
   │                       ├──sonda incierta pasada la gracia──▶ NEEDS_REVIEW (origin dispatched)
   │                       └──sonda PRESENT con evidencia que no coincide (sin esperar)──▶ NEEDS_REVIEW (origin dispatched)
   ├──sonda previa PRESENT──▶ NEEDS_REVIEW (origin pre_probe)
   └──fail --claim <token> (abort antes de dispatch)──▶ FAILED (admite attempt+1)
NEEDS_REVIEW ──resolve (por sonda o manual con grant, Regla 5)──▶ SUCCEEDED | FAILED
```

`reject` (3e) no es una transición: anota el `DISPATCHED` y solo cambia a dónde lleva un `PRESENT` posterior (`NEEDS_REVIEW` con origen `rejected` en lugar de `SUCCEEDED`).

Ninguna entrada se borra nunca: el ledger solo añade estados.

Órdenes que cambian estado y desde dónde:

| Orden | Admite | Efecto | Fuera de eso |
|---|---|---|---|
| `dispatch <id> --claim <t>` | `PREPARED` con ese token | sonda previa (3c) y CAS a `DISPATCHED` | 6 si el token no es el vigente; 2 en otro estado |
| `complete <id> --claim <t> --response <json>` | `DISPATCHED` con ese token | `SUCCEEDED` con `attribution: response`, tras comprobar que la respuesta trae la evidencia que declara la `op` (para `pr.merge`, `mergeCommit`) y sale con 0; sin ella, la entrada sigue `DISPATCHED`, sale con 6 (`IN_FLIGHT`) y la cierra la sonda | 2 |
| `reject <id> --claim <t> --response <txt>` | `DISPATCHED` con ese token, cuando la petición terminó con error **no** debido al `timeout` (3e) | anota `dispatch_rejected` y la respuesta; el estado sigue `DISPATCHED` y sale con 6 | 2 |
| `fail <id> --claim <t> --reason <txt>` | solo `PREPARED` con ese token: quien llama aborta **antes** de enviar (validación local, grant caducado) | `FAILED` y suelta la reclamación; sin llamada remota | 2. Desde `DISPATCHED` nunca: ahí solo la sonda llega a `FAILED` (3b) |
| `reconcile <key>` | cualquier estado, y clave ausente | tabla de la Regla 3d; solo sondea desde `DISPATCHED` | — (todo estado tiene exit propio; 2 solo por error) |
| `resolve <id> …` | `NEEDS_REVIEW` | Regla 5 | 2 |

**Por qué el token ajeno da 6 en `dispatch` y 2 en el resto.** En `dispatch`, un token que ya no es el vigente es el resultado normal de una carrera: otro worker reclamó el `PREPARED` huérfano (2b). El exit 6 dice «no envíes», que es justo lo que tiene que hacer quien pierde la carrera, y no hay nada que corregir. En `complete`, `reject` y `fail` no hay carrera legítima que lleve a un token ajeno. Desde `DISPATCHED` nadie puede volver a reclamar la entrada. Solo la sonda, pasada la gracia, la lleva a `FAILED` y a un `attempt+1` con un token nuevo. Y la gracia (300 s) supera el `timeout` de la petición (120 s), así que un llamador con un token antiguo en esas órdenes es un error de programa o un proceso que ha estado parado más que la gracia. Por eso esas órdenes salen con 2 sin escribir nada, y la entrada la cierra la sonda. Los consumidores tratan el 6 como parada sin envío y el 2 como error que se registra; ninguno de los dos lleva a un reenvío.

Reglas:

1. **Write-ahead:** `DISPATCHED` se persiste y se sincroniza a disco **antes** de enviar la petición. Un `PREPARED` encontrado después de una caída significa, por construcción, que la petición no salió.
   - Durabilidad fijada: al abrir, el CLI aplica `PRAGMA journal_mode=WAL` y `PRAGMA synchronous=FULL` y los vuelve a leer. En WAL, `FULL` hace `fsync` del WAL en cada commit; `NORMAL` no lo hace y no vale aquí. Si el valor leído no es `wal` y `2` (FULL), sale con 2 sin escribir (AC-l).
2. **Nada ambiguo devuelve exit 0.** Códigos de `prepare`:

   | Exit | Resultado | Cuándo |
   |---|---|---|
   | 0 | `PROCEED` | registro nuevo, `PREPARED` huérfano o `FAILED` confirmado; **siempre con reclamación** (2b) |
   | 3 | `ALREADY_EXECUTED` | imprime el recibo |
   | 4 | `NEEDS_REVIEW` | — |
   | 5 | `CONFLICT` | misma clave, otra huella, fuera del caso de 2d |
   | 6 | `IN_FLIGHT` | la clave está reclamada con lease vigente, o `DISPATCHED` dentro de la gracia (2c) |
   | 2 | error | ledger ilegible, herramienta ausente u orden inválida; fail-closed |

   **2d. Precedencia cuando la huella cambia.** Si `prepare` llega con la misma clave y otros `args`, se aplica la primera regla que case:
   1. `NEEDS_REVIEW` → 4. Una persona tiene que mirar la entrada, traiga los `args` que traiga.
   2. `PREPARED` con reclamación vigente (2b) → 6.
   3. **Cambio de head sobre una `op` con head fijado.** La `op` declara `head_pinned: true` en el registro (para `pr.merge` es así, porque todo envío lleva `--match-head-commit`). Además, los `args` nuevos solo difieren en `head`. En ese caso:
      - **`FAILED`:** `PROCEED` con `attempt+1`. Escribe los `args` nuevos y su huella; el intento anterior conserva los suyos.
      - **`DISPATCHED`, con o sin rechazo anotado:** se ejecuta la sonda, fuera de la transacción y sin esperar a la gracia. Si da `OPEN` sin `mergedAt`, `mergeCommit`, `mergedBy` ni `autoMergeRequest`, y con `headRefOid` igual al head **nuevo** (distinto del pedido en el intento anterior), el intento anterior pasa a `FAILED` con `failure: superseded`. En la misma transacción se reclama `attempt+1` con los `args` nuevos y sale con 0. La razón es que el envío anterior iba fijado a otro head: GitHub solo lo aplica si el head del PR sigue siendo ese, y el PR ya tiene otro sin estar mergeado, así que el envío anterior no puede producir el efecto. Cualquier otra respuesta de la sonda se evalúa contra el intento anterior con la tabla de la Regla 3. Un `ABSENT` definitivo pasada la gracia también da `PROCEED` con los `args` nuevos; el resto mantiene sus estados y exits (3, 4 o 6), sin `CONFLICT`.
   4. Cualquier otra diferencia (otro método, o una `op` sin `head_pinned`) → 5.
   5. Con la huella igual, rige la tabla del estado.

   Este es el camino del reintento de merge-sprint tras un rechazo `DIRTY`/`BEHIND`. El sprint anota `reject`, `resync` empuja un head nuevo, `merge_at` comprueba que el PR tiene ese head (`merge-sprint.sh:604`) y llama a `reserve` con él. Por 2d.3 obtiene `PROCEED` sin esperar a la gracia (AC-q). Si `resync` no mueve el head (la rama ya contenía `origin/main`, `merge-sprint.sh:460`), la huella es la misma, el `DISPATCHED` sigue en gracia y el sprint para con `in_flight` en lugar de reintentar el mismo head.

   **2b. Reclamación y compare-and-set.** `prepare` y `dispatch` son transacciones `BEGIN IMMEDIATE`.
   - `prepare` con `PROCEED` escribe en la misma transacción un `claim_token` aleatorio, `holder_pid`, `holder_start` y `lease_until = now + lease_s`, y devuelve el token. Si otro proceso consulta mientras la reclamación está vigente, obtiene `IN_FLIGHT` (6), aunque el estado sea `PREPARED`.
   - **De quién es `holder_pid`.** El llamador lo pasa con `--holder-pid <pid>`, y para un efecto `non_idempotent` es **obligatorio**: sin él, `prepare` sale con 2 sin reclamar. No hay valor por defecto con `os.getppid()`, porque entre el consumidor y el CLI hay envoltorios y subshells efímeros (`merge-sprint → f5() ( cd … ) → bash f5-state.sh → python`) y cualquier padre intermedio muere al volver. Los consumidores bash pasan `$$`, que dentro de un subshell `( … )` sigue valiendo el PID del shell principal (no `$BASHPID`), y ese shell vive hasta terminar el efecto. El CLI **nunca** registra su propio PID. Si el PID es ≤ 1 o su `holder_start` no se puede leer, se registra `holder_pid = NULL` y solo cuenta el lease.
   - **Orden de evaluación** de una reclamación sobre `PREPARED`, en la transacción de `prepare`:
     1. `install_id` ajeno o `holder_pid` NULL → solo cuenta el lease: vigente → 6; vencido → huérfano.
     2. `install_id` local y el proceso `holder_pid` existe con el mismo `holder_start` → **vivo**: 6, aunque el lease haya vencido. Un llamador vivo no pierde su reclamación por tardar.
     3. `install_id` local y el proceso no existe, o existe con otro `holder_start` (PID reutilizado) → huérfano **sin esperar al lease**.

     Solo un huérfano puede reclamarse con un token nuevo. Aunque un llamador muerto o desplazado reapareciera, el CAS de `dispatch` con su token antiguo falla.
   - `dispatch <effect_id> --claim <token>` es un compare-and-set: `UPDATE … SET state='DISPATCHED' WHERE effect_id=? AND state='PREPARED' AND claim_token=?`. Si no cambia exactamente una fila, sale con 6 y quien llama **no envía** la petición. De dos workers, como mucho uno pasa el CAS.

   **2c. Gracia y reloj.** Cada `op` declara en el registro `request_timeout_s` y `dispatch_grace_s`, con `dispatch_grace_s ≥ request_timeout_s + 60`. Para `pr.merge`: 120 s y 300 s.
   - Quien llama ejecuta la petición acotada por `request_timeout_s` (`timeout` en bash). Pasado ese plazo, la petición se da por terminada en el cliente.
   - Un `DISPATCHED` con `now < dispatched_at + dispatch_grace_s` está **en vuelo**: `prepare` da 6 y `reconcile` no concluye ni `ABSENT` ni `UNKNOWN`. Con `now ≥ dispatched_at + dispatch_grace_s` (el borde exacto incluido) la gracia ha pasado.
   - `now` sale del reloj del sistema. En tests puede fijarse con `SAVIA_EFFECT_NOW` (Regla 7).

3. **Reconciliación al reintentar:** con la clave `DISPATCHED`, `prepare` o `reconcile <key>` ejecutan la **sonda** de la operación y resuelven según su respuesta:

   | Sonda | Estado nuevo | Exit |
   |---|---|---|
   | `PRESENT`, con los campos observables iguales a `args` y `mergedBy` igual a `actor_remote` (6b), sin rechazo anotado | `SUCCEEDED` | 3 |
   | `PRESENT` con algún campo observable o `mergedBy` distinto | `NEEDS_REVIEW` (`review_origin: dispatched`) | 4 |
   | `PRESENT` coincidente sobre un `DISPATCHED` con rechazo anotado (3e) | `NEEDS_REVIEW` (`review_origin: rejected`) | 4 |
   | `ABSENT` definitivo (3b), **pasada la gracia** | `FAILED` y, en la misma llamada, `attempt+1` en `PREPARED` con reclamación nueva | 0 (`PROCEED`) |
   | `ABSENT` dentro de la gracia | sigue `DISPATCHED` | 6 |
   | `UNKNOWN` o error de la sonda, dentro de la gracia | sigue `DISPATCHED` | 6 |
   | `UNKNOWN` o error de la sonda, pasada la gracia | `NEEDS_REVIEW` (`review_origin: dispatched`) | 4 |

   Las dos conclusiones que no dependen del tiempo son `PRESENT` coincidente y `PRESENT` discrepante: lo observado ya existe y no va a cambiar esperando. Todo lo demás espera a la gracia. `reconcile <key>` aplica la misma tabla desde `DISPATCHED`, salvo que `ABSENT` pasada la gracia deja `FAILED` sin reclamar un intento nuevo; sus exits los fija 3d.

   La sonda se ejecuta **fuera** de la transacción (es una llamada de red). Después, en `BEGIN IMMEDIATE`, se comprueba que la entrada sigue en el mismo `state` y `attempt` que antes de sondear; si cambió, no se escribe nada y se sale con 6.

   **Nunca se reenvía** un `non_idempotent` desde `DISPATCHED`.

   **3b. `ABSENT` definitivo, cerrado por `op`.** La salida de `gh pr merge` (código y texto) **nunca** clasifica un rechazo. Desde `DISPATCHED` solo se llega a `FAILED` por la sonda. La sonda de `pr.merge` tiene **una sola lista de campos**, declarada en el registro de operaciones y usada igual en 3b, en la tabla de la Regla 3, en 3c y en `verify-receipt`:

   `PR_MERGE_PROBE_FIELDS = state,mergedAt,mergeCommit,mergedBy,headRefOid,autoMergeRequest`

   La sonda es `gh pr view <N> -R <repo> --json <PR_MERGE_PROBE_FIELDS>`. `ABSENT` exige todo esto a la vez:
   - la orden sale con 0;
   - la salida es JSON válido con las seis claves;
   - `state == "OPEN"`; `mergedAt`, `mergeCommit`, `mergedBy` y `autoMergeRequest` nulos; `headRefOid` igual al head de `args`.

   `PRESENT` exige código 0, JSON válido con las seis claves, `state == "MERGED"`, `mergedAt` y `mergeCommit` no nulos y `mergedBy.login` no vacío; si además `headRefOid` coincide con `args` y `mergedBy.login` con `actor_remote`, es coincidente.

   Cualquier otra cosa es `UNKNOWN`: código distinto de 0 aunque el texto diga `OPEN` (respuesta parcial tras un 5xx), JSON truncado, claves ausentes, `CLOSED` sin merge, un head distinto, o un auto-merge o cola de merge pendiente (`autoMergeRequest` no nulo: el PR sigue `OPEN` pero el merge puede llegar después). Un «not mergeable» se registra como evidencia, pero el `FAILED` lo decide la sonda pasada la gracia, no el texto.

   **Limitación de `pr.merge` v1:** los repos con cola de merge obligatoria no están soportados. Un PR aceptado en la cola puede seguir `OPEN`, sin `autoMergeRequest` visible, durante más de `dispatch_grace_s`, y la sonda lo vería `ABSENT`. El registro de la `op` lo declara (`merge_queue: unsupported`), los consumidores nunca usan `--auto` (SE-343) y el reenvío que pudiera seguir lo frena GitHub con `--match-head-commit`. Una `op` sin esa protección no puede declarar `ABSENT` definitivo por tiempo.

   **3c. Sonda previa al `dispatch`.** Si la `op` tiene sonda, `dispatch` la ejecuta antes del CAS:
   - si da `PRESENT`, no se envía nada y la entrada pasa a `NEEDS_REVIEW` (4) con `review_origin: pre_probe` y la evidencia observada. El efecto existe y este ledger no lo pidió: lo hizo otra instalación u otro actor, aunque `mergedBy` coincida;
   - si da `UNKNOWN`, no se envía nada, la entrada sigue `PREPARED` con su reclamación y sale con 2;
   - si da `ABSENT`, se hace el CAS y se envía.

   Queda una ventana entre la sonda previa y el envío. Para `pr.merge` la cierra GitHub (`--match-head-commit` y no se mergea dos veces). Una `op` sin protección remota equivalente debe declararlo en el registro.

   **3d. Exits de `reconcile`, por estado.** `reconcile` nunca autoriza un envío (eso solo lo hace `PROCEED` de `prepare`), así que su exit describe lo que hay, sin ambigüedad entre «cerrado ahora» y «ya estaba cerrado». Imprime siempre `<RESULTADO> <effect_id|-> <run_id|-> <head|->` en una línea. `head` es el `headRefOid` de la evidencia del recibo con `RECONCILED` y `ALREADY_SUCCEEDED`, es decir, el head que de verdad se mergeó, y `-` en el resto. El head del manifiesto no sirve para esto, porque tras un `resync` el head mergeado es otro.

   | Estado al entrar | Resultado | Exit |
   |---|---|---|
   | `DISPATCHED` sin rechazo anotado (3e) y sonda `PRESENT` coincidente | `RECONCILED`: pasa a `SUCCEEDED` en esta llamada (`attribution: probe`) | 3 |
   | `SUCCEEDED` | `ALREADY_SUCCEEDED`: sin cambios, imprime el recibo | 7 |
   | `DISPATCHED` y `PRESENT` discrepante, `PRESENT` con rechazo anotado (3e), o `UNKNOWN` pasada la gracia → `NEEDS_REVIEW`; o ya `NEEDS_REVIEW` | `NEEDS_REVIEW` (imprime además `review_origin`) | 4 |
   | `DISPATCHED` dentro de la gracia (sonda `ABSENT` o `UNKNOWN`), o `PREPARED` con reclamación vigente (2b) | `IN_FLIGHT` | 6 |
   | `DISPATCHED` y `ABSENT` definitivo pasada la gracia → `FAILED`; ya `FAILED`; `PREPARED` huérfano; clave ausente | `NOT_SENT`: este ledger no tiene un envío pendiente ni consumado para la clave | 0 |
   | ledger ilegible, clave inválida (Regla 8) | error | 2 |

   El exit 0 es «este ledger no hizo el efecto», nunca «adelante»: un consumidor que encuentre el PR mergeado y reciba 0 sabe que el merge es ajeno. La Regla 2 rige para `prepare`; 3d no la contradice.

   **3e. Un rechazo anotado solo resta atribución.** Si la petición termina con error y no por el `timeout` de 2c (exit ≠ 0 y ≠ 124 de `timeout`), el consumidor llama a `reject` con la respuesta. La anotación **nunca** lleva a `FAILED` ni autoriza un reenvío (eso sigue siendo cosa de la sonda pasada la gracia, 3b); solo impide que un `PRESENT` posterior se cierre como propio: con rechazo anotado, `PRESENT` coincidente da `NEEDS_REVIEW` con `review_origin: rejected`. Así se conserva la garantía actual de SE-433 AC-26 (un merge rechazado y luego hecho fuera del sprint no pasa por propio, `test-merge-sprint.bats` «merge rechazado y luego mergeado fuera del sprint»), que hoy da `release` borrando la reserva. Un `timeout` (124) no anota nada: es el caso ambiguo de verdad y lo cierra la sonda.
4. **Nada se libera tras `dispatch`.** El `release` actual (borrar la reserva) desaparece: antes de `dispatch` se usa `fail --claim`, y después solo la sonda lleva a `FAILED`, con `ABSENT` definitivo pasada la gracia. Un error de lectura del remoto no equivale a «no ocurrió» (corrige H6).
5. **Resolución de `NEEDS_REVIEW`.** Hay dos rutas, excluyentes y elegidas por la orden, no por el entorno:

   | Ruta | Orden | Quién | Admite |
   |---|---|---|---|
   | **Por sonda** | `resolve <effect_id> --by-probe [--outcome succeeded\|failed]` | cualquiera, también un agente con `SAVIA_AUTONOMOUS_RUN=1` | solo `review_origin == dispatched` |
   | **Manual** | `resolve <effect_id> --manual --outcome succeeded\|failed --evidence <ref>` | solo una persona con grant | cualquier `review_origin` |

   - **Ruta por sonda (sin grant).** El CLI vuelve a ejecutar la sonda y el resultado sale **de la sonda**, nunca de quien llama: `PRESENT` coincidente → `SUCCEEDED` (`attribution: probe`); `ABSENT` definitivo con `now ≥ dispatched_at + dispatch_grace_s` → `FAILED`. Cualquier otra conclusión (incluido `PRESENT` discrepante) deja `NEEDS_REVIEW` y sale con 4. `--evidence` no se admite en esta ruta (exit 2). Si se pasa `--outcome` y no coincide con la conclusión de la sonda, sale con 2 sin escribir: un agente no puede obtener `attempt+1` declarando `failed` sobre un efecto aplicado. Con `review_origin` `pre_probe`, `rejected` o `migration`, sale con 2 sin sondear: este ledger no pidió ese efecto, y cerrarlo por sonda convertiría en propio un efecto de otra instalación del mismo operador, que es justo lo que 3c impide.
   - **Ruta manual (con grant).** Exige un grant vigente de la operadora con firma asimétrica, `operator-grant.sh check --scope effect-resolve --resource effect:<effect_id>`, con el mismo mecanismo que el scope `merge` (SE-343, LAW-HUMAN-002). Un agente no puede emitirlo solo. El grant es de un solo uso (`consume`). Es la única ruta para `pre_probe`, `rejected` y `migration`, y para `dispatched` cuando la sonda no concluye.
   - `SAVIA_AUTONOMOUS_RUN=1` y la rama `agent/*` rechazan **solo la ruta manual** (exit 2 temprano, aunque haya grant: la resolución manual es de una persona). No afectan a la ruta por sonda, que no concede nada que la sonda no pruebe. Son una barrera **débil**, porque las controla el propio proceso: su ausencia no sustituye al grant.
   - Sin `--by-probe` ni `--manual`, o con los dos, exit 2.
   - Queda en el ledger la ruta, quién resolvió, con qué grant (si lo hubo) y con qué evidencia.
6. **Recibo verificable:** registro JSON con
   - `effect_id`, `op`, `key`, `args_digest`, `actor`, `install_id` y `outcome`;
   - la evidencia remota (para `pr.merge`: `merge_commit`, `mergedBy`, `headRefOid`) y la lista de campos de `args` **no verificados** (para `pr.merge`, `method`);
   - `attribution`: `response` si el remoto confirmó la petición de este ledger, o `probe` si el éxito se dedujo por la sonda tras una caída;
   - `observed_at` y `prev_hash`.

   **Limitación conocida:** con `attribution: probe`, el remoto no distingue dos instalaciones del mismo operador, porque `mergedBy` es la misma cuenta. Si la otra máquina mergea el mismo PR y head dentro de la ventana de gracia, el recibo lo atribuye a esta. La sonda previa (3c) reduce la ventana a una carrera entre dos `dispatch` casi simultáneos. El recibo no afirma más de lo que se observó.

   **6b. Identidad remota del actor.** `actor` (perfil activo) y `mergedBy` (login de GitHub) no se comparan entre sí. Al crear una reclamación nueva (registro nuevo, `PREPARED` huérfano o `attempt+1`), `prepare` obtiene la identidad remota con la orden que declara la `op` (para `pr.merge`, `gh api user --jq .login`) y la guarda en `actor_remote`. La comparación con `mergedBy.login` es exacta tras pasar ambas a minúsculas ASCII (los logins de GitHub no distinguen mayúsculas). Si la orden falla o devuelve vacío, `prepare` sale con 2 sin reclamar: sin identidad remota no hay forma de reconocer un `PRESENT` propio. Si eso ocurre al pasar a `attempt+1` tras un `ABSENT` definitivo, el intento anterior queda `FAILED` y no se reclama el nuevo. Al reconciliar un `DISPATCHED` existente no se vuelve a pedir la identidad: se usa el `actor_remote` guardado, así que con `gh` ausente la sonda da `UNKNOWN` y rige la tabla de la Regla 3 (AC-e). No hay tabla de equivalencias perfil → login en el repo.

   Los recibos se encadenan por hash, como el ledger de merge-sprint. `verify-receipt <effect_id>` comprueba la cadena y vuelve a observar el remoto con la sonda de la `op`:

   | Exit | Resultado | Cuándo |
   |---|---|---|
   | 0 | `VERIFIED` | cadena íntegra y evidencia remota igual a la del recibo |
   | 1 | `FAIL` | cadena alterada (un `prev_hash` no casa) o el remoto contradice el recibo (otro `mergeCommit`, `mergedBy` o head) |
   | 4 | `UNVERIFIED` | cadena íntegra, pero la sonda no concluye (`UNKNOWN`, `gh` ausente) |
   | 2 | error | ledger ilegible o `effect_id` inexistente |

   `FAIL` prevalece sobre `UNVERIFIED`: una cadena rota es `FAIL` aunque no haya sonda.
7. **Ganchos de prueba inertes fuera de tests.** `SAVIA_EFFECT_FAULT` (mata el proceso en un punto) y `SAVIA_EFFECT_NOW` (fija el reloj) solo se aplican si se cumplen las dos condiciones:
   - `SAVIA_EFFECT_TEST=1`;
   - la ruta real (`realpath`) de `SAVIA_EFFECT_LEDGER` está bajo `realpath(${TMPDIR:-/tmp})` y es distinta de `realpath` de la ruta por defecto.

   Si falta alguna, se ignoran, se escribe un aviso en stderr y el ledger sigue con el reloj real y sin fallos. Con el ledger real, una variable olvidada no puede dejar `DISPATCHED` a voluntad ni adelantar la gracia.

   Es una barrera **débil frente a un proceso malicioso**: `SAVIA_EFFECT_TEST` y `TMPDIR` los controla el propio proceso, igual que `SAVIA_AUTONOMOUS_RUN` (Regla 5). Lo que protege de verdad es que el ledger por defecto queda excluido tras resolver enlaces simbólicos; la regla evita accidentes, no ataques.

   **7b. El ledger no es la autoridad; la sonda sí.** `SAVIA_EFFECT_LEDGER` también lo controla quien llama: un agente que lo apunte a un ledger vacío obtiene `PROCEED` aunque el efecto esté `DISPATCHED` o `NEEDS_REVIEW` en el ledger real. Por eso:
   - el override solo se acepta con `SAVIA_EFFECT_TEST=1`; sin él se ignora, se avisa en stderr y se usa `$HOME/.savia/effects/ledger.db` (barrera débil, evita accidentes);
   - el registro de operaciones **rechaza** una `op` `non_idempotent` sin sonda previa (3c): el CLI no arranca con ese registro (exit 2). Con sonda previa obligatoria, un ledger vacío o ajeno acaba en `NEEDS_REVIEW` (`pre_probe`) en cuanto el efecto existe en el remoto, nunca en un segundo envío.
8. **Validación de entradas.** Antes de tocar SQLite o el remoto, cada campo de `args` se valida con la lista blanca que declara su `op`. Para `pr.merge`: número `^[1-9][0-9]{0,9}$`, repo `<owner>/<name>` con cada segmento en `^[A-Za-z0-9._-]+$`, sin empezar por `-` y distinto de `.` y `..`, head `^[0-9a-f]{40}$` y método en `{merge, squash, rebase}`. Si algo no casa, exit 2 sin escribir. Todas las consultas SQL usan parámetros (`?`), sin excepción. Las órdenes remotas se lanzan con lista de argumentos, sin shell.

### Implementación prevista

- `scripts/effect-ledger.py` (Python stdlib, `sqlite3` con `BEGIN IMMEDIATE`). Expone `prepare`, `dispatch`, `complete`, `fail`, `resolve`, `status`, `verify-receipt`, `reconcile` y `migrate`. El ledger vive en `$HOME/.savia/effects/ledger.db`, por instalación y fuera del repo; `SAVIA_EFFECT_LEDGER` solo lo cambia en tests (Regla 7b).
- **Registro de operaciones** por `op`: clase, sonda, campos de la sonda, campos observables, `request_timeout_s`, `dispatch_grace_s`, `lease_s`, si hay protección remota contra la doble ejecución (3c) y limitaciones (`merge_queue`). La primera es `pr.merge`. Su sonda usa `PR_MERGE_PROBE_FIELDS` (3b) con `-R` explícito, aplica el criterio cerrado de 3b y devuelve `UNKNOWN` ante cualquier error. Un registro con una `op` `non_idempotent` sin sonda previa no carga (7b).
- `operator-grant.sh` gana el scope `effect-resolve`, con firma asimétrica obligatoria como `merge` (Regla 5). Toca el sistema de grants, así que entra en S2, el primer slice que produce entradas `pre_probe` y `migration`, con revisión humana.
- `push-pr.sh` (S2) llama **directamente** a `effect-ledger.py`, sin pasar por `f5-state.sh`:
  - `out=$(python3 effect-ledger.py prepare pr.merge … --holder-pid $$); rc=$?` y lee `PROCEED <effect_id> <claim_token>` de `out` solo con `rc == 0`;
  - `dispatch` antes de `gh pr merge` (corrige H4), y `gh pr merge` acotado por `timeout request_timeout_s`;
  - trata los exits 4, 5 y 6 como parada con mensaje que remite a `resolve`;
  - si `gh pr merge` falla sin `timeout`, llama a `reject` (3e); ante cualquier fallo deja de decir «vuelve a ejecutar» y dice «resultado incierto: reconciliar» (corrige H3 y H5).

  Entre S2 y S3, `merge-sprint.sh` sigue con el `f5-state.sh` de hoy y su directorio `$HOME_MS/reservations/<digest>`, sin cambio de comportamiento: H8 (dos libros) sigue igual que en main, no peor, y los tests `test-merge-sprint.bats` no se tocan en S2.
- `scripts/f5-state.sh` (S3) pasa a ser un envoltorio de compatibilidad sobre el ledger para `pr.merge`, **en la misma PR** que adapta `merge-sprint.sh`, su único consumidor tras S2. Nunca hay un main en el que el envoltorio exija flags que el consumidor no pasa. Mantiene el exit 3 de `ALREADY_EXECUTED` y deja de devolver 0 en `submitted`.
  - **Interfaz del envoltorio.** La interfaz `f5 <cmd> <op> <key>` no lleva lo que el ledger necesita, así que se amplía con flags obligatorias para `reserve`:
    ```
    f5-state.sh reserve pr.merge <N> --repo <owner/name> --head <sha40> --method squash --holder-pid <pid> [--run-id <digest>]
      → stdout: "PROCEED <effect_id> <claim_token>"   (exit 0)  |  exits 2/3/4/5/6 del ledger tal cual
    f5-state.sh mark_submitted pr.merge <N> --effect <effect_id> --claim <claim_token>   → dispatch (sonda previa + CAS)
    f5-state.sh close          pr.merge <N> --effect <effect_id> --claim <claim_token> --response <json>   → complete
    f5-state.sh reject         pr.merge <N> --effect <effect_id> --claim <claim_token> --response <txt>   → reject (3e)
    f5-state.sh release        pr.merge <N> --effect <effect_id> --claim <claim_token>   → fail (solo PREPARED)
    f5-state.sh reconcile      pr.merge <N> --repo <owner/name>                          → reconcile (exits de 3d)
    f5-state.sh status         pr.merge <N> --repo <owner/name>                          → status (solo lectura)
    ```
    Falta de cualquier flag obligatoria → exit 2 sin tocar el ledger. El token **no** se guarda en disco: viaja por stdout al consumidor, que lo guarda en una variable de su propio shell durante el efecto. Así no queda un fichero de token huérfano tras una caída, y un proceso distinto del que reclamó no tiene el token. Los consumidores pasan `--holder-pid $$` (Regla 2b). `release` ya no borra nada: solo existe antes de `dispatch`; después, el consumidor llama a `reconcile`.
  - En `merge-sprint.sh`, la línea de reserva deja de descartar la salida: `out=$(f5 reserve …) && read -r verdict eid tok <<<"$out" && [[ $verdict == PROCEED ]] && f5 mark_submitted … --effect "$eid" --claim "$tok" || anomaly f5_reserva`. `eid` y `tok` viven en variables del shell del sprint, no en disco, desde `merge_at` (`merge-sprint.sh:597`) hasta `f5 close` en `record_merge` (`:645`) o `f5 reject`. Si el proceso cae entre medias, el token se pierde a propósito: la entrada queda `DISPATCHED` y la cierra `reconcile` en la reanudación.
  - `f5 status` es **solo informativo** e imprime el estado: `PREPARED` → `reserved`, `DISPATCHED` → `submitted`, `SUCCEEDED` → `closed`, `NEEDS_REVIEW` → `needs_review`, `FAILED` → `failed`, ausencia → `none` (el literal que imprime hoy `f5-state.sh:52`). `IN_FLIGHT` no es un estado, así que `status` nunca lo imprime. Ningún consumidor decide con `status`.
  - S3 sustituye el `case "$(f5 status …)"` de la reanudación (`merge-sprint.sh:860-866`, rama «PR ya `MERGED`») por el exit de `f5 reconcile` (3d), comparando además el `run_id` impreso con el `digest` del manifiesto en curso:

    | Exit de `reconcile` | `run_id` = digest actual | Acción del sprint |
    |---|---|---|
    | 7 `ALREADY_SUCCEEDED` | sí | `continue` (ya registrado: `record_merge` va antes de `close`) |
    | 3 `RECONCILED` | sí | `record_merge <pr> <tier> <head> reconciled`, con el `head` que imprime `reconcile`, una sola vez, y `continue` |
    | 7 o 3 | no (lo mergeó `push-pr` u otro manifiesto) | parada `merge_externo`: el ledger queda correcto, pero el merge no es de este sprint |
    | 4 con `review_origin: rejected` | — | parada `merge_externo` (conserva SE-433 AC-26, 3e) |
    | 4, otro origen | — | parada `needs_review` |
    | 6 | — | parada `in_flight` |
    | 0 `NOT_SENT` | — | parada `merge_externo` (sin reserva, `FAILED` o `PREPARED` huérfano: este ledger no hizo el merge) |
    | 2 u otro | — | parada `f5_error` |

    Así la gracia, la sonda y la comparación de head y cuenta (hoy en `reconcilable`, `merge-sprint.sh:565`) las aplica siempre el ledger, y `reconcilable` desaparece.
  - `record_merge` (`merge-sprint.sh:635-648`) **no** llama a `f5 close` cuando la equivalencia es `reconciled`. En esa ruta el token se perdió a propósito con la caída y la entrada ya es `SUCCEEDED` por la sonda de `reconcile`. Un `close` sin `--effect`/`--claim` saldría con 2 y dispararía `anomaly f5_close`. En las demás equivalencias, `record_merge` llama a `f5 close … --effect "$eid" --claim "$tok" --response <json>` con las variables que dejó `merge_at`.
  - Reescribir `f5-state.sh` cambia su blob, que el manifiesto de merge-sprint fija (`merge-sprint.sh:211-216` escribe `f5_blob`, `:827` lo comprueba con `anomaly blob_f5`). Los manifiestos firmados antes de S3 dejan de valer: S3 lo declara en el body y la operadora regenera el plan tras el merge.
- `merge-sprint.sh` (S3):
  - usa el mismo ledger (corrige H8). El `digest` del manifiesto no entra en la ruta ni en la huella: se guarda como `run_id` del intento (`--run-id`), para que el sprint sepa bajo qué manifiesto se pidió;
  - cambia `release` incondicional por `reject` si `gh pr merge` falla sin `timeout` (3e) y no hace nada más si fue `timeout`: la entrada queda `DISPATCHED` y la cierra `reconcile` en el siguiente paso (corrige H6);
  - mantiene el reintento de `try_merge` tras un rechazo `DIRTY`/`BEHIND` con `RESYNC=1` (`merge-sprint.sh:798-801`): el `reserve` del segundo intento lleva el head nuevo y obtiene `PROCEED` por 2d.3. Si `reserve` da 6 (el `resync` no movió el head, o la sonda no concluye), el sprint para con `in_flight`; con 4, con `needs_review`. Nunca reenvía el head anterior;
  - motivos de parada propios `needs_review` e `in_flight`, distintos de `merge_externo`.
- **Migración** de las reservas JSON: `effect-ledger.py migrate --from <dir> --repo <owner/name>`. `--repo` es obligatorio y se valida con la Regla 8; sin él, exit 2 sin importar nada (en `push-pr` el repo salía del directorio de `gh` y en merge-sprint de `SAVIA_GH_REPO`; ninguno queda en el JSON). `migrate` obtiene `actor_remote` igual que `prepare` (6b); si no puede, exit 2 sin importar nada.
  - **Clave y `args` parciales.** La clave es `owner/repo#N`, como la de `prepare`. `args` lleva `repo` y `number`, `head` si existe el fichero hermano `pr.merge__N.head` de merge-sprint con un SHA válido (`resv_head`, `merge-sprint.sh:564`) y nulo si no, y `method` nulo. `args_digest` queda nulo y la entrada lleva `args_partial: true`. Un `prepare` posterior sobre esa clave compara **solo los campos no nulos**. Si alguno difiere, aplica la precedencia de 2d: `NEEDS_REVIEW` → 4, `FAILED` con solo el head distinto → `PROCEED`, y el resto → `CONFLICT` (5). Si coinciden, rige el estado: `SUCCEEDED` → 3 con el recibo de migración, `NEEDS_REVIEW` → 4 y `FAILED` → `PROCEED` con `attempt+1`, que escribe los `args` completos y su huella y deja de ser parcial. Así una entrada migrada nunca produce un `CONFLICT` permanente contra el primer `prepare` legítimo.
  - **Sonda de migración.** Con `head` conocido se aplica 3b tal cual. Sin `head`, `ABSENT` es 3b **sin** la comparación de `headRefOid` (el resto de condiciones, incluido `autoMergeRequest` nulo, se mantienen): para `pr.merge` el efecto es «el PR está mergeado», y un PR `OPEN` sin merge ni auto-merge no lo está, sea cual sea su head. Sin esta regla la rama `ABSENT → FAILED` sería inalcanzable y todo acabaría en `NEEDS_REVIEW`.
  - Nada importado pasa a propio con **menos** evidencia de la que ya exigía el sistema anterior (el `close` antiguo exigía `MERGED`, `f5-state.sh:38-41`; `reconcilable` exigía head y cuenta):
    - `closed` con sonda `PRESENT`, `mergedBy` igual a `actor_remote` y, si hay `head`, `headRefOid` igual → `SUCCEEDED` con recibo `attribution: migration` y la evidencia observada, marcando como no verificados `method` y, si faltaba, `head`. Cualquier otra sonda o `mergedBy` distinto → `NEEDS_REVIEW` (`review_origin: migration`).
    - `reserved` o `submitted` (un `reserved` de `push-pr` puede haber enviado el merge, H4) → sonda: `PRESENT` → `NEEDS_REVIEW` (`migration`); `ABSENT` definitivo con la hora de referencia anterior a `now - dispatch_grace_s` → `FAILED`; `ABSENT` más reciente o `UNKNOWN` → `NEEDS_REVIEW` (`migration`). La hora de referencia es la mayor entre `ts` y el `mtime` del fichero, porque `mark_submitted` reescribe el fichero sin cambiar `ts`. Nunca `PROCEED`; un `FAILED` solo lleva a un nuevo envío pasando por `prepare` y la sonda previa (3c).
  - **Duplicados.** Varios ficheros que dan la misma `(op, key)` en una importación (p. ej. dos `<digest>` de merge-sprint) se funden en una entrada con el estado **más restrictivo**: `NEEDS_REVIEW` antes que `SUCCEEDED` antes que `FAILED`. Todas las rutas de origen quedan en `observation.migrated_from` y el informe cuenta `fundidas: K`. Si la clave ya existe en el ledger, la entrada no se modifica; si el estado que daría la fuente es distinto del guardado, se informa como `discrepancia` con ambas rutas.
  - Idempotente: una segunda importación no crea entradas ni cambia estados (la unicidad `(op, idempotency_key)` lo garantiza) e informa `0 importadas`. Un JSON ilegible se cuenta y se reporta, sin abortar el resto ni crear entrada.
  - Exit de `migrate`: 0 si todo se importó o ya estaba sin discrepancias; 4 si hubo ilegibles o discrepancias (requieren persona); 2 por error de entrada o de ledger.
  - Los ficheros originales no se borran ni se modifican. S2 importa `~/.savia/reservations` (los de `push-pr`; si mezcla repos, la operadora lo separa antes: un repo equivocado produce bloqueos 3/4/5, nunca un envío). S3 importa los de `$HOME_MS/reservations/<digest>` con `--repo` del manifiesto, con `run.lock` tomado para que ningún sprint esté en curso.
- `effect-reservation.sh` queda **deprecado sin consumidores**: se elimina, o se deja como envoltorio que imprime el aviso y delega. Su test se sustituye.
- `coherence-gates.sh` deja de contar «ejecutable» como cierre: ejecuta la suite de fallos inyectados de esta spec y bloquea si falla.
- Tests que cambian de expectativa, porque la semántica pasa de permisiva a bloqueante (no se debilita ninguna aserción; se invierte la que fijaba el defecto):
  - `f5-exactly-once.bats:29-33`;
  - `f5-cases.bats:40-46`;
  - `f5-cases.bats:32-38` se mantiene: `PREPARED` huérfano sigue siendo `PROCEED`;
  - `test-merge-sprint.bats` «AC-26 block: reserva submitted con merge real de otro head o de otra cuenta» (S3): sigue exigiendo parada y ningún merge más, pero el motivo pasa de `merge_externo` a `needs_review`, porque el ledger sí hizo un `DISPATCHED` y lo observado discrepa (Regla 3). Es un cambio de etiqueta declarado, no una aserción quitada.
  - `test-merge-sprint.bats` «v3 positivo: main avanza tras el resync…» y «v3 boundary: desfase persistente agota MERGE_SPRINT_TRIES…» (S3). El stub rechaza el merge con un contador, sin mover `main`, así que el `resync` del segundo intento no cambia el head y por 2d el reintento del mismo head para con `in_flight`. En S3, el stub de `pr merge` avanza `main` en el remoto simulado en cada rechazo `BEHIND`/`DIRTY`, como pasa en GitHub, donde ese rechazo significa que `main` se ha movido. Así el `resync` produce un head nuevo. Las aserciones no cambian: merge en el segundo intento, y dos `RETRY` con `main_movido_sin_converger`. Se añade el caso con el head sin mover, que espera `in_flight` (AC-q). El cambio de comportamiento queda declarado: hoy, un rechazo por desfase con la rama ya al día se reintenta al momento; con S3 se para hasta que pase la gracia.

## Criterios de aceptación

Todos los tests usan un remoto simulado (stub de `gh` en `PATH`) que **cuenta las peticiones de efecto**, y un ledger temporal por test bajo `$BATS_TEST_TMPDIR`. El fallo se inyecta en el punto indicado con `SAVIA_EFFECT_FAULT=<punto>`, que mata el proceso. El paso del tiempo se simula con `SAVIA_EFFECT_NOW`. Los dos ganchos solo actúan con las condiciones de la Regla 7. «Relanzar tarde» significa relanzar con `SAVIA_EFFECT_NOW = dispatched_at + dispatch_grace_s + 1`, y «relanzar al momento», sin adelantar el reloj. Cada test debe fallar contra el código de main en fa3f486a0 o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes/después.

Matriz V1:

- **AC-a — caída antes de iniciar.** Punto: tras `prepare`, antes de `dispatch`. El fallo mata al **llamador** (el proceso cuyo PID se pasó con `--holder-pid`), así que el `PREPARED` es huérfano sin esperar al lease. Al relanzar: `PROCEED` con token nuevo, el efecto se pide una vez y queda `SUCCEEDED` con recibo. Contador remoto = 1. Negativos:
  - relanzar otra vez da `ALREADY_EXECUTED` y el contador sigue en 1;
  - con el llamador vivo (un `sleep` cuyo PID se pasa con `--holder-pid`) y el lease vigente, un segundo `prepare` da `IN_FLIGHT` (6); con el llamador vivo y el lease **vencido**, también 6 (Regla 2b, paso 2);
  - `prepare` de `pr.merge` sin `--holder-pid` sale con 2 sin escribir en el ledger;
  - vía envoltorio (S3): un consumidor de prueba que llama a `f5-state.sh reserve … --holder-pid $$` desde dentro de un subshell `( cd … && … )` registra el PID del shell principal; tras salir el subshell, un segundo `reserve` desde otro proceso da 6. `f5-state.sh reserve` sin `--head`, `--repo`, `--method` o `--holder-pid` sale con 2 sin tocar el ledger;
  - PID reutilizado: con `holder_pid` vivo pero `holder_start` distinto, el `PREPARED` es huérfano;
  - `dispatch` con el token antiguo sale con 6 sin llamada remota.
- **AC-b — caída tras pedir el efecto y antes del recibo.** Punto: tras enviar la petición, antes de `complete`. En ningún caso se vuelve a llamar al efecto:
  - (b0) relanzar al momento con sonda `ABSENT`: `IN_FLIGHT` (6) y sigue `DISPATCHED`;
  - (b1) relanzar al momento o tarde con sonda `PRESENT`, campos observables y actor coincidentes: `SUCCEEDED`, recibo con `attribution: probe` y exit 3;
  - (b2) relanzar tarde con sonda `UNKNOWN`: `NEEDS_REVIEW` con exit 4 y `review_origin: dispatched`;
  - (b3) relanzar al momento con sonda `UNKNOWN` (el fallo de red más habitual): `IN_FLIGHT` (6), sigue `DISPATCHED` y no se escribe `NEEDS_REVIEW`. Límite: en `dispatched_at + dispatch_grace_s - 1` sigue en 6; en `+ dispatch_grace_s` exacto pasa a 4;
  - (b4) relanzar al momento con sonda `PRESENT` y `mergedBy` distinto de `actor_remote`: `NEEDS_REVIEW` (4) sin esperar a la gracia.

  Contador remoto = 1 en todos. Contra main falla: `f5-state.sh` devuelve 0 y `push-pr.sh` repite el merge.
- **AC-c — efecto confirmado y caída antes de cerrar.** Punto: tras la respuesta OK del remoto, antes de escribir `SUCCEEDED`. Al relanzar al momento, la sonda `PRESENT` cierra con recibo que contiene la evidencia remota (`merge_commit`). No hace falta adelantar el reloj, porque `PRESENT` no depende de la gracia. Contador = 1 y exactamente un `SUCCEEDED` y un recibo en la cadena.
- **AC-d — misma clave, otros argumentos (2d).** Sobre una entrada `SUCCEEDED`, `prepare` con la misma `(op, key)` y otro head SHA da `CONFLICT` (exit 5), sin llamada remota y con el ledger intacto; con otro método, también 5 desde `FAILED` y `DISPATCHED`. Sobre `NEEDS_REVIEW` con otro head da 4, no 5. Sobre `FAILED` con solo el head distinto da 0 y el nuevo intento lleva los `args` nuevos. Con una `op` de prueba sin `head_pinned`, el mismo cambio de head sobre `FAILED` da 5. Límite: misma clave y mismos argumentos tras `SUCCEEDED` da exit 3 con el recibo original, byte a byte.
- **AC-e — respuesta remota ambigua.** La petición de efecto falla de forma ambigua y se relanza tarde. Cada variante de la **sonda** termina en `NEEDS_REVIEW` (exit 4), sin reintento automático, con contador = 1 y sin borrar la reserva:
  - timeout del stub tras aplicar el efecto, con sonda que no responde;
  - sonda con 5xx;
  - sonda con salida no JSON o JSON truncado;
  - sonda con código ≠ 0 y texto `"state":"OPEN"` (respuesta parcial);
  - sonda con `OPEN` y un `headRefOid` distinto del pedido;
  - sonda con `OPEN` y `autoMergeRequest` no nulo (merge programado pendiente);
  - sonda sin alguna de las seis claves de `PR_MERGE_PROBE_FIELDS` (p. ej. sin `mergedBy`);
  - `gh` ausente del `PATH`;
  - sonda que devuelve cadena vacía.

  Negativos y límite:
  - el stub de merge responde «not mergeable» con código ≠ 0 y la sonda lee `OPEN` válido (3b). Al relanzar al momento da `IN_FLIGHT` (6). Al relanzar en `dispatched_at + dispatch_grace_s - 1` sigue en 6. En `+ dispatch_grace_s` exacto, el **mismo** `prepare` deja `FAILED` el intento anterior, reclama `attempt+1` en `PREPARED` y sale con 0. Con `reconcile` en ese instante, queda `FAILED` sin intento nuevo y sale con 0;
  - el texto de `gh pr merge` no cambia el resultado: el mismo stub con texto de éxito y código ≠ 0 sigue el mismo camino;
  - con `SAVIA_EFFECT_TEST` sin definir, o con el ledger fuera de `${TMPDIR:-/tmp}`, `SAVIA_EFFECT_NOW` se ignora (Regla 7) y el estado sigue `DISPATCHED`.
- **AC-f — concurrencia de dos workers.**
  - **Mismo ledger:** 20 rondas con dos procesos simultáneos sobre la misma clave, partiendo de registro nuevo y de `PREPARED` huérfano. En cada ronda, exactamente uno obtiene `PROCEED` y pasa el CAS de `dispatch`. El otro obtiene `IN_FLIGHT` o `ALREADY_EXECUTED`, o, si llegó a `PROCEED` con un token ya sustituido, su `dispatch` sale con 6. Contador remoto = 20, uno por ronda.
  - **Dos rutas:** `push-pr.sh` y `merge-sprint.sh` sobre el mismo `pr.merge/N`, mismo repo, head y método, ven la misma entrada del ledger aunque merge-sprint lleve un `digest` de manifiesto: la segunda ruta obtiene `IN_FLIGHT` (6) o `ALREADY_EXECUTED` (3), **nunca** `CONFLICT` (5), y el contador remoto queda en 1. Negativo: con otro head, la segunda ruta obtiene `IN_FLIGHT` (6) mientras la primera está `PREPARED` o `DISPATCHED` en gracia, porque la sonda ve el head de la primera y no el suyo (2d.3); obtiene `CONFLICT` (5) si la primera ya está `SUCCEEDED`. Nunca obtiene 0, y el contador remoto queda en 1.
  - **Dos instalaciones con ledgers distintos (multioperador):** la segunda llega con su ledger vacío y obtiene `PROCEED`. La sonda previa de `dispatch` (3c) encuentra el efecto `PRESENT`, hecho por otro actor, y deja la entrada en `NEEDS_REVIEW` (4) con la evidencia del otro actor. Contador remoto = 1: ni repite ni lo da por propio. Negativo: con la sonda previa `UNKNOWN`, sale con 2 sin llamada remota y la entrada sigue `PREPARED`.
  - **Mismo operador en dos instalaciones:** igual que el caso anterior, pero con el mismo `mergedBy`. La sonda previa da `NEEDS_REVIEW` con `review_origin: pre_probe`, nunca `SUCCEEDED`, porque este ledger no tiene `DISPATCHED`. El recibo de la primera instalación lleva su `install_id`. Esa entrada **no** se puede cerrar sin grant (AC-i).

Contrato:

- **AC-g — sin repetición automática en estado ambiguo.** Para cada estado `DISPATCHED`, `NEEDS_REVIEW` e `IN_FLIGHT`, ningún consumidor (`push-pr.sh`, `merge-sprint.sh`, `f5-state.sh`) llega a la llamada de efecto. Lo prueba el contador del stub, no un grep.
- **AC-h — recibo verificable.** `verify-receipt` sale con 0 (`VERIFIED`) con cadena íntegra y remoto coincidente; con 1 (`FAIL`) si se altera un byte de un recibo anterior o si cambia el `merge_commit` remoto; con 4 (`UNVERIFIED`) con cadena íntegra y sonda `UNKNOWN` o `gh` ausente; y con 1, no 4, si la cadena está alterada y además no hay sonda. `VERIFIED` no cubre los campos que el recibo marca como no verificados (`method`), y la salida lo dice.
- **AC-i — resolución atribuida (Regla 5).**
  - Ruta manual: `resolve --manual` con un grant `effect-resolve` vigente y firmado para ese `effect_id` registra ruta, actor, grant y evidencia, y consume el grant. Un segundo `resolve --manual` con el mismo grant se rechaza con exit 2.
  - Ruta manual sin grant, con un grant de otro `effect_id` o con uno caducado: exit 2, **también sin `SAVIA_AUTONOMOUS_RUN` y fuera de una rama `agent/*`**. Este caso prueba que borrar las señales de entorno no concede nada.
  - Ruta manual con `SAVIA_AUTONOMOUS_RUN=1`: exit 2 aunque haya grant.
  - Ruta por sonda con `SAVIA_AUTONOMOUS_RUN=1` y `review_origin: dispatched`: con sonda `PRESENT` coincidente cierra `SUCCEEDED` sin grant (exit 0); con `ABSENT` definitivo pasada la gracia cierra `FAILED`; con `UNKNOWN` sale con 4 y la entrada sigue `NEEDS_REVIEW`.
  - Ruta por sonda con `--outcome` distinto de la sonda: con sonda `PRESENT` coincidente y `--outcome failed`, exit 2, la entrada sigue `NEEDS_REVIEW`, no hay `attempt+1` y el contador remoto no cambia. Igual con sonda `ABSENT` y `--outcome succeeded`. Con `--evidence`, exit 2.
  - Ruta por sonda con `review_origin: pre_probe` (AC-f, mismo operador) y una sonda `PRESENT` con el mismo `mergedBy` y el mismo head: exit 2 sin sondear y la entrada sigue `NEEDS_REVIEW`; por la ruta manual con grant vigente, cierra. Lo mismo con `review_origin: migration`.
  - `resolve` sin `--by-probe` ni `--manual`, o con los dos: exit 2.
- **AC-p — `reconcile` por estado y reanudación de merge-sprint (Regla 3d, 3e).**
  - CLI (S1): para cada estado de entrada de la tabla de 3d (`DISPATCHED` con cada resultado de sonda dentro y fuera de la gracia, `SUCCEEDED`, `NEEDS_REVIEW`, `FAILED`, `PREPARED` vivo, `PREPARED` huérfano, clave ausente) `reconcile` sale con el exit de la tabla y el estado final es el indicado. Dos `reconcile` seguidos sobre un `DISPATCHED` con sonda `PRESENT` coincidente dan 3 y luego 7, con exactamente un recibo. Con `RECONCILED` y `ALREADY_SUCCEEDED`, la cuarta columna de la salida es el `headRefOid` del recibo; en el resto de resultados es `-`. Ningún `reconcile` llama al efecto (contador = 0).
  - `reject` (S1): `DISPATCHED` con rechazo anotado y sonda `PRESENT` coincidente → 4 con `review_origin: rejected`; `resolve --by-probe` sobre esa entrada sale con 2 sin sondear. Negativo: sin anotación, la misma sonda da 3. `reject` sobre `PREPARED`, o con token ajeno, sale con 2. Con rechazo anotado y `ABSENT` pasada la gracia → `FAILED` como sin anotación.
  - merge-sprint (S3), con el PR ya `MERGED` al reanudar: `SUCCEEDED` del mismo manifiesto → `continue` y una sola línea `"event":"MERGED"` para el PR en el ledger del sprint; `DISPATCHED` con sonda coincidente → `record_merge … reconciled` una vez, con el head que imprime `reconcile` (que en el test difiere del head del manifiesto, como tras un `resync`), sin llamar a `f5 close` y sin `anomaly f5_close`; `SUCCEEDED` o `RECONCILED` con otro `run_id` → `merge_externo`; sin entrada, `FAILED` o `PREPARED` huérfano → `merge_externo`; rechazo anotado → `merge_externo`; `NEEDS_REVIEW` de otro origen → `needs_review`; `DISPATCHED` en gracia → `in_flight`. Los tests `test-merge-sprint.bats` AC-25 y «merge rechazado y luego mergeado fuera del sprint» (AC-26) siguen en verde sin tocarse.
- **AC-q — reintento tras rechazo y `resync` (2d.3).**
  - CLI (S1): `DISPATCHED` con rechazo anotado para el head A. La sonda devuelve `OPEN`, sin merge ni auto-merge, con `headRefOid` = B. Un `prepare` al momento con head B da 0: el intento A queda `FAILED` con `failure: superseded` y el intento nuevo lleva B. Lo mismo sin rechazo anotado. Negativos al momento, todos sin `PROCEED`: con la sonda en `headRefOid` = A da 6; con `UNKNOWN`, 6; con `MERGED` de A y rechazo anotado, 4 (`rejected`); con otro método, 5. Límite: con `autoMergeRequest` no nulo y head B da 6. Contador = 0 en todos (el CLI no envía).
  - merge-sprint (S3): el stub de `gh pr merge` rechaza el primer intento con `BEHIND`, `resync` mueve el head de A a B y el segundo intento mergea B. Resultado: `MERGED` con `head=B`, contador de merges = 2 (uno rechazado y uno aplicado), ninguna `anomaly f5_reserva` y un solo `"event":"MERGED"`. Negativo: si `resync` deja el head en A, el sprint para con `in_flight` y el contador queda en 1. Contra main, el negativo falla: hoy se reintenta el mismo head.
- **AC-n — validación de entradas (Regla 8).** `prepare` con número `12; DROP`, repo `-R--foo/x`, `x/-y`, `../..`, `./x`, `x/..` o `a/b/c`, head de 39 caracteres o en mayúsculas, o método `fast-forward` sale con 2, sin escribir en el ledger y sin llamada remota. Límite: el mismo `prepare` con valores válidos da 0. Sin identidad remota (`gh api user` falla o devuelve vacío), `prepare` sale con 2 sin reclamar (Regla 6b); con `mergedBy` que solo difiere en mayúsculas, la sonda es coincidente.
- **AC-j — multioperador.**
  - Se ejecuta desde S1 sobre los ficheros que toca cada slice (S1: `effect-ledger.py` y el registro; S2 y S3 añaden sus consumidores), no solo al final.
  - Ninguna ruta absoluta ni identidad literal en el código. El ledger se resuelve por `$HOME` (o la variable de test) y el actor sale del perfil activo. Se comprueba con `grep -nE '(/home/|/Users/|/root/)'` sobre `effect-ledger.py`, el registro de operaciones y los consumidores tocados: 0 coincidencias; el test se valida mutando un fichero temporal con una ruta literal y viendo que falla.
  - Los tests corren con dos operadores sintéticos y dos `HOME` temporales; ninguno escribe en el `HOME` real.
  - Sin perfil activo, `prepare` de un efecto `non_idempotent` falla cerrado (exit 2).
  - Sin `/proc` (macOS), `holder_start` no se puede leer: se registra `holder_pid = NULL` y solo cuenta el lease (2b). Un test con el lector de `/proc` sustituido por uno que falla comprueba que la reclamación sigue siendo exclusiva mientras el lease está vigente, y que nunca se declara huérfana antes de que venza.
- **AC-k — cierre honesto en coherence-gates.**
  - `coherence-gates.sh` ejecuta la suite de esta spec; si se rompe un test de la matriz, el gate marca BLOCK.
  - `effect-reservation.sh` no tiene consumidores, o está eliminado.
- **AC-l — fail-closed.** Si el ledger está corrupto, bloqueado más allá del timeout de `sqlite3`, en un disco sin escritura o con un esquema desconocido, el resultado es exit 2 y nunca `PROCEED`. Además:
  - tras abrir, `PRAGMA journal_mode` es `wal` y `PRAGMA synchronous` es `2` (FULL); si el CLI no logra fijarlos (simulado con un gancho de prueba que fuerza `NORMAL`), exit 2 sin escribir (Regla 1);
  - un registro de operaciones con una `op` `non_idempotent` sin sonda previa hace que cualquier orden salga con 2 (Regla 7b);
  - sin `SAVIA_EFFECT_TEST=1`, `SAVIA_EFFECT_LEDGER` se ignora con aviso en stderr y se usa el ledger de `$HOME` (un `HOME` temporal en el test).
- **AC-o — migración de reservas JSON.** Con un directorio de reservas sintético y la sonda simulada:
  - sin `--repo`, o con un repo inválido (Regla 8), o sin identidad remota: exit 2 y ledger sin filas;
  - `closed` con sonda `PRESENT` y `mergedBy` = `actor_remote` → `SUCCEEDED` con `attribution: migration`; `closed` con `mergedBy` distinto, o con `head` conocido distinto de `headRefOid` → `NEEDS_REVIEW` (`migration`); `closed` con sonda `UNKNOWN` → `NEEDS_REVIEW` (`migration`);
  - `submitted` y `reserved` con sonda `PRESENT` → `NEEDS_REVIEW` (`migration`); con `UNKNOWN` → `NEEDS_REVIEW`; con `ABSENT` y hora de referencia anterior a la gracia → `FAILED`, **sin** fichero `.head` (se comprueba que la rama es alcanzable) y con él; con `ABSENT` y hora reciente → `NEEDS_REVIEW`. Límite: `ts` antiguo pero `mtime` reciente → `NEEDS_REVIEW`. Ninguno queda en un estado que dé `PROCEED` sin pasar por `FAILED` confirmado;
  - `args` parciales: tras migrar `closed` → `SUCCEEDED` sin head, un `prepare` con el mismo repo y número y un head cualquiera da 3, no 5; tras migrar `closed` → `SUCCEEDED` con `.head`, un `prepare` con otro head da 5; tras migrar a `FAILED`, `prepare` da 0 y la entrada queda con `args` completos y huella;
  - el mismo PR en dos directorios `<digest>` con estados `submitted` (sonda `PRESENT`) y `closed` → una entrada `NEEDS_REVIEW` con las dos rutas en `migrated_from` e informe `fundidas: 1`;
  - importar dos veces: la segunda informa `0 importadas` y el ledger es idéntico byte a byte en sus filas;
  - un JSON ilegible se reporta y no crea entrada, sin abortar el resto;
  - los ficheros de origen no cambian (hash antes y después).
  - Contador de peticiones de efecto = 0 en toda la migración.
- **AC-m — ganchos de prueba inertes.** Con el ledger en la ruta por defecto (un `HOME` temporal) y `SAVIA_EFFECT_FAULT` y `SAVIA_EFFECT_NOW` definidos:
  - sin `SAVIA_EFFECT_TEST=1`, el flujo completo termina `SUCCEEDED`, sin caída, con el reloj real y con un aviso en stderr;
  - con `SAVIA_EFFECT_TEST=1` y el ledger fuera de `${TMPDIR:-/tmp}`, el resultado es el mismo;
  - con `SAVIA_EFFECT_TEST=1` y `SAVIA_EFFECT_LEDGER` apuntando a un enlace simbólico bajo `${TMPDIR:-/tmp}` que resuelve a la ruta por defecto, el resultado es el mismo (se compara tras `realpath`).

  Positivo de control: con las dos condiciones cumplidas, el mismo `SAVIA_EFFECT_FAULT` mata el proceso.

## Fuera de alcance

- Adoptar OpenRath (runtime, servidor, Postgres, scheduler) o cualquier dependencia nueva.
- Ledger compartido entre máquinas u operadores: cada instalación tiene el suyo y el remoto es la autoridad común (AC-f).
- Firma criptográfica de recibos: el encadenado por hash basta para v1, y la firma se valorará junto a los recibos de SE-488.
- Registrar efectos distintos de `pr.merge`. El contrato y el registro lo permiten; cada `op` nueva necesita su sonda y sus tests en una PR propia.
- Reconciliador periódico en segundo plano: la reconciliación ocurre al reintentar la misma clave o con `reconcile` explícito.

## Plan por slices

1. **S1** — `effect-ledger.py` (reclamación, CAS, gracia, `complete`/`fail`/`reject`, `reconcile` con los exits de 3d, `resolve --by-probe`, durabilidad, ganchos de prueba, validación de entradas) y el registro de operaciones con stub; tests AC-a (CLI), AC-d, AC-f (mismo ledger), AC-h, AC-j (sobre sus ficheros), AC-l, AC-m, AC-n, la parte CLI de AC-p, la parte CLI de AC-q y la parte por sonda de AC-i. Sin consumidores del ledger: no produce entradas `pre_probe` ni `migration`. Añade además un guard mínimo: `f5-state.sh` y `effect-reservation.sh` rechazan con exit 2 cualquier `op` distinta de `pr.merge`, con un test que lo comprueba. Así la prohibición de «Orden» no depende solo de la disciplina.
2. **S2** — Sonda `pr.merge` con el criterio de 3b y sonda previa (3c); `push-pr.sh` llamando directamente al ledger, con write-ahead, `timeout`, `reject` y nuevos mensajes; scope `effect-resolve` en `operator-grant.sh` y `resolve --manual`; `migrate` de `~/.savia/reservations`. AC-b, AC-c, AC-e, AC-g para `push-pr`, AC-i completo, AC-j sobre `push-pr.sh` y AC-o. **No toca `f5-state.sh` ni `merge-sprint.sh`**: merge-sprint sigue exactamente como en main y `test-merge-sprint.bats` no cambia. Va junto con el grant porque S2 es el primer slice que produce `pre_probe`, `rejected` y `migration`, que solo se resuelven con grant.
3. **S3** — `f5-state.sh` como envoltorio y `merge-sprint.sh` en la **misma PR**: ledger único, token capturado, `reject` en lugar de `release`, `reconcile` en lugar del `case` sobre `status` y de `reconcilable`, motivos `needs_review` e `in_flight`, y `migrate` de `$HOME_MS/reservations`; AC-a (envoltorio), AC-f (dos rutas, dos instalaciones, mismo operador), AC-g para `merge-sprint`, AC-j sobre ambos, la parte merge-sprint de AC-p, la parte merge-sprint de AC-q y AC-o para ese directorio. Tests de `test-merge-sprint.bats` AC-25/26 en verde sin debilitar (con el único cambio de etiqueta declarado en «Tests que cambian de expectativa»). Juntar envoltorio y consumidor evita un main intermedio en el que `f5 reserve` exija flags que merge-sprint no pasa y todo merge del sprint pare con `f5_reserva`.
4. **S4** — `coherence-gates.sh` y deprecación de `effect-reservation.sh`; AC-k.

Orden: S2 va inmediatamente después de S1 en el camino de merge, sin otras PR de ese camino entre medias. Hasta S2, ninguna `op` no idempotente puede reutilizar `f5-state.sh` ni `effect-reservation.sh`: la tabla H1-H10 describe en público cómo repetir un efecto incierto, y hoy solo lo frena la protección propia de GitHub para `pr.merge`.

Cada slice es una PR Draft. S2 y S3 tocan el camino de merge y S2 además el sistema de grants, así que los dos son tier 3 y exigen revisión humana explícita (SE-362). S4 toca un gate, también tier 3.

## Riesgos

- **Sobrebloqueo:** más paradas en `NEEDS_REVIEW` cuando la red falla. Es el comportamiento buscado; el coste es una resolución manual por caso, medible en el ledger.
- **Espera tras un rechazo:** un «not mergeable» con el **mismo** head deja la clave en `IN_FLIGHT` durante `dispatch_grace_s` (300 s para `pr.merge`) antes de admitir un nuevo intento. Es el precio de no deducir un rechazo del texto de `gh`. El reintento normal de merge-sprint tras `resync` no espera, porque el head cambia y la sonda prueba que el envío anterior ya no puede aplicarse (2d.3). Si `resync` no mueve el head, el sprint para con `in_flight` en lugar de reintentar al momento como hoy.
- **Atribución por sonda:** el mismo operador en dos instalaciones puede compartir un recibo `attribution: probe` mal atribuido dentro de la ventana de carrera (Regla 6). Queda documentado en el recibo y no se presenta como verificado.
- **Migración de reservas existentes:** los JSON de `~/.savia/reservations` y de merge-sprint se importan con `migrate` (AC-o). Un `submitted` sin sonda concluyente entra como `NEEDS_REVIEW`, nunca como `PROCEED`.
- **Cola de merge:** los repos con cola de merge obligatoria no están soportados por `pr.merge` v1 (3b).
- **Llamador colgado:** un llamador vivo conserva su reclamación aunque venza el lease (Regla 2b, paso 2). Si se cuelga sin morir, la clave queda en `IN_FLIGHT` hasta que alguien lo mate. Falla cerrado: bloquea, no repite.
- **Manifiestos de merge-sprint:** S3 cambia el blob de `f5-state.sh` fijado en el manifiesto (`merge-sprint.sh:211-216`, `:827`). Los planes firmados antes quedan inválidos con `anomaly blob_f5`, que es el comportamiento correcto.
- **Más grants manuales:** las entradas `pre_probe`, `rejected` y `migration` exigen siempre grant (Regla 5). La migración inicial puede producir varias; se cuentan en el ledger.
- **Divergencia de envoltorios:** `f5-state.sh` queda como capa fina. Un test compara sus exits con los del ledger para cada estado.

## Rollback

Revertir el PR del slice. El ledger es aditivo: los JSON antiguos no se borran ni se modifican (la migración solo lee), y S1 no cambia el comportamiento de ningún consumidor.

Revertir S2 o S3 tiene un coste: los consumidores vuelven a los JSON y no ven las entradas creadas en el ledger desde entonces. Antes de revertir, `effect-ledger.py status --open` lista las entradas `PREPARED`, `DISPATCHED` y `NEEDS_REVIEW`; se resuelven o se reconcilian primero. Con alguna `DISPATCHED` o `NEEDS_REVIEW` abierta, el revert no se hace.

## Lo que he entendido

### Escenas
1. Savia pide un merge y la red cae antes de la respuesta. No lo vuelve a pedir: «El merge de #1500 quedó dudoso: la petición salió pero no sé si GitHub lo aceptó. Lo compruebo antes de repetir nada.» Si la comprobación lo confirma, lo marca hecho con su commit.
2. Por la mañana lees: «1 efecto en revisión: publicación del informe, dudoso desde las 03:12. ¿Lo doy por hecho o por fallido?». Nada se repite hasta que eliges, y tu elección queda registrada.
3. Dos agentes intentan fusionar el mismo PR a la vez. Solo uno lo pide; el otro recibe «ya en curso».

### Palabras de la persona
«Savia Viva + tokens y efectos» — 2026-11-09, respuesta de la operadora a la pregunta interactiva sobre qué specs aprobar.

### Qué SÍ será
- Ningún efecto con resultado dudoso se repite sin comprobarlo o sin tu decisión.
- Un recibo de cada efecto que se puede verificar después.

### Qué NO será
- No deshace efectos.
- No repite algo dudoso porque falló la red.

### Confirmación
- fecha: 2026-11-09
- respuesta: «Confirmo las escenas». Opción elegida por la operadora en la pregunta interactiva del 2026-11-09 en la que se le enseñaron estas escenas literalmente.

## Slice S0 — Prototipo navegable
- prototipo: los tres textos exactos de las escenas y la salida de la reconciliación sobre un ledger de ejemplo con un efecto hecho, uno fallido y uno dudoso.

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/effect-ledger.py` | invocado por scripts bash | mismo script, sin binding de frontend |
| `push-pr.sh`, `merge-sprint.sh`, `f5-state.sh` | scripts bash | mismos scripts |
| `coherence-gates.sh` | CI y validación local | idéntico |

### Verification protocol

- [ ] La suite de fallos inyectados corre igual desde ambos frontends: no depende de ninguno.
- [ ] Ningún hook nuevo; ningún cambio en `savia-gates`.

### Portability classification

- [x] **PURE_BASH**: bash más Python stdlib (`sqlite3`, `hashlib`, `json`), sin bindings de frontend.

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). 
