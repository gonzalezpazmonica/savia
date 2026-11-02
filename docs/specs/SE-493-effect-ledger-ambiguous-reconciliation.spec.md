---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: A
risk: L3
depends_on: [SE-387]
related_specs: [SE-387, SE-433, SE-343, SE-362, SE-488, SE-364]
origin: "Análisis de repositorios externos difundidos públicamente (2026-11-01), iniciativa SAVIA-RESEARCH-01 y validación V1 «efectos exactamente una vez». Patrón extraído de OpenRath (BSD-3-Clause, commit f39331700fb4), sin adoptar el producto. Afirmaciones del análisis contrastadas con main en fa3f486a0 (los scripts afectados no cambian desde cd55e23e8)."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-493 — Effect Ledger y reconciliación de efectos ambiguos

## Problema

Un efecto externo (merge, publicación, mensaje, despliegue, borrado) puede quedar con **resultado incierto**: la petición salió, pero el proceso cayó o la respuesta no llegó antes de registrar el recibo. Si en ese estado se reintenta, el efecto puede ocurrir dos veces. SE-387 F5 prometió «exactly-once» con reserva, idempotencia y recibo; lo construido cubre el caso fácil (efecto cerrado → `ALREADY_EXECUTED`) y deja abierto el ambiguo.

### Qué dice el análisis y qué hay de verdad en el código

El análisis de origen señala `scripts/effect-reservation.sh` y advierte que su ruta para reservas pendientes «no prueba por sí sola que el efecto externo no ocurriera antes de un crash». Contrastado con main:

1. **El análisis apunta al script equivocado.** `effect-reservation.sh` **no tiene consumidores en tiempo de ejecución**. Solo lo nombran `scripts/coherence-gates.sh:45-52`, que comprueba que sea ejecutable y lo cuenta como `PASS coherence/closure-effect-reservation.sh`, y su test `tests/bats/f5-exactly-once.bats`. Es cobertura nominal: el gate de cierre de SE-387 pasa por la existencia de un fichero, justo el riesgo R2 («falsa cobertura») de SE-387.
2. **La advertencia es correcta y aplica al script que sí se usa.** El camino real es `scripts/f5-state.sh`, invocado por `scripts/push-pr.sh` y `scripts/merge-sprint.sh`.
3. **Respuesta a la pregunta clave: sí, hoy un efecto con resultado incierto puede repetirse sin que nada lo impida.** No hay doble ejecución observada; el riesgo está en el contrato.

Hallazgos con fichero:línea:

| # | Dónde | Qué pasa | Consecuencia |
|---|---|---|---|
| H1 | `scripts/effect-reservation.sh:9-16` | Cualquier estado distinto de `closed` devuelve exit 0 y el texto «effect exactly-once». | Quien lo use reejecuta el efecto tras un crash. El test `f5-exactly-once.bats:29-33` fija ese comportamiento como correcto. |
| H2 | `scripts/f5-state.sh:24-28` | Con `submitted` y PR sin `MERGED` imprime «NO se solicita otro efecto», pero sale con **exit 0**, el mismo código que «adelante». | El texto dice «no»; el código dice «sí». `tests/bats/f5-cases.bats:32-46` fija ambos casos como «permite reanudar». |
| H3 | `scripts/push-pr.sh:274` y `:281` | Solo comprueba `reserve ... \|\| exit 3` y continúa a `gh pr merge`. | Al relanzar `push-pr.sh --merge` tras un crash o un error ambiguo, se vuelve a pedir el merge. |
| H4 | `scripts/push-pr.sh:281-288` | `mark_submitted` se escribe **después** de pedir el merge. | Una caída entre ambos deja `reserved`, indistinguible de «nunca se pidió» (caso b de V1 confundido con caso a). `merge-sprint.sh:382` sí marca `submitted` antes de pedirlo; el defecto es solo de `push-pr`. |
| H5 | `scripts/push-pr.sh:281-284` | Cualquier fallo de `gh pr merge`, incluido un timeout tras aceptar el servidor, termina con «vuelve a ejecutar push-pr.sh --merge». | La herramienta invita a repetir en estado ambiguo. |
| H6 | `scripts/f5-state.sh:11` y `:49` | `pr_state` traga errores y devuelve `""`; `release` borra la reserva si el estado no es literalmente `MERGED`. `merge-sprint.sh:386` llama a `release` ante cualquier salida ≠ 0 de `gh pr merge`. | Un error de red tras un merge aceptado borra la reserva. El siguiente paso ve el PR mergeado sin reserva y para con `merge_externo` (`merge-sprint.sh:616`). Falla cerrado, pero pierde la procedencia: un merge propio pasa por ajeno y no queda recibo. |
| H7 | `scripts/f5-state.sh:15-30` | Comprueba la existencia del fichero y lo escribe sin cerrojo. | Dos workers con la misma clave pueden reservar los dos (caso f). |
| H8 | `scripts/push-pr.sh:273` y `scripts/merge-sprint.sh:329` | `push-pr` usa `~/.savia/reservations`; `merge-sprint` usa `$HOME_MS/reservations/<digest>`. | Dos libros para el mismo efecto `pr.merge/N`: ninguno ve la reserva del otro. El cerrojo `run.lock` (`merge-sprint.sh:566`) solo serializa merge-sprint consigo mismo. |
| H9 | `scripts/f5-state.sh:8` | La clave es solo el número de PR; no hay huella de argumentos. El SHA pedido vive en un fichero aparte solo en merge-sprint (`:330`, `:382`) y no se comprueba al reservar. | Misma clave con otros argumentos (otro head) no se rechaza (caso d). |
| H10 | `scripts/f5-state.sh:42` | El «recibo» es `state=closed` y `closed_at`. | No contiene la evidencia remota (commit de merge, autor, head), no está encadenado y no se puede verificar después. El ledger de merge-sprint sí guarda `merge_commit` (`:406`), pero no es el recibo F5. |

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
| `review_origin` | de dónde llegó a `NEEDS_REVIEW`: `dispatched` (desde `DISPATCHED` de este ledger), `pre_probe` (sonda previa, 3c) o `migration` (importado). Decide si se puede cerrar sin grant (Regla 5) |
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

Ninguna entrada se borra nunca: el ledger solo añade estados.

Órdenes que cambian estado y desde dónde:

| Orden | Admite | Efecto | Fuera de eso |
|---|---|---|---|
| `dispatch <id> --claim <t>` | `PREPARED` con ese token | sonda previa (3c) y CAS a `DISPATCHED` | 6 si el token no es el vigente; 2 en otro estado |
| `complete <id> --claim <t> --response <json>` | `DISPATCHED` con ese token | `SUCCEEDED` con `attribution: response`, tras comprobar que la respuesta trae la evidencia que declara la `op` (para `pr.merge`, `mergeCommit`); sin ella, la entrada sigue `DISPATCHED` y la cierra la sonda | 2 |
| `fail <id> --claim <t> --reason <txt>` | solo `PREPARED` con ese token: quien llama aborta **antes** de enviar (validación local, grant caducado) | `FAILED` y suelta la reclamación; sin llamada remota | 2. Desde `DISPATCHED` nunca: ahí solo la sonda llega a `FAILED` (3b) |
| `reconcile <key>` | `DISPATCHED` | tabla de la Regla 3 | sin cambios y exit 0 con el estado impreso |
| `resolve <id> …` | `NEEDS_REVIEW` | Regla 5 | 2 |

Reglas:

1. **Write-ahead:** `DISPATCHED` se persiste y se sincroniza a disco **antes** de enviar la petición. Un `PREPARED` encontrado después de una caída significa, por construcción, que la petición no salió.
   - Durabilidad fijada: al abrir, el CLI aplica `PRAGMA journal_mode=WAL` y `PRAGMA synchronous=FULL` y los vuelve a leer. En WAL, `FULL` hace `fsync` del WAL en cada commit; `NORMAL` no lo hace y no vale aquí. Si el valor leído no es `wal` y `2` (FULL), sale con 2 sin escribir (AC-l).
2. **Nada ambiguo devuelve exit 0.** Códigos de `prepare`:

   | Exit | Resultado | Cuándo |
   |---|---|---|
   | 0 | `PROCEED` | registro nuevo, `PREPARED` huérfano o `FAILED` confirmado; **siempre con reclamación** (2b) |
   | 3 | `ALREADY_EXECUTED` | imprime el recibo |
   | 4 | `NEEDS_REVIEW` | — |
   | 5 | `CONFLICT` | misma clave, otra huella |
   | 6 | `IN_FLIGHT` | la clave está reclamada con lease vigente, o `DISPATCHED` dentro de la gracia (2c) |
   | 2 | error | ledger ilegible, herramienta ausente u orden inválida; fail-closed |

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
   | `PRESENT`, con los campos observables iguales a `args` y `mergedBy` igual a `actor_remote` (6b) | `SUCCEEDED` | 3 |
   | `PRESENT` con algún campo observable o `mergedBy` distinto | `NEEDS_REVIEW` (`review_origin: dispatched`) | 4 |
   | `ABSENT` definitivo (3b), **pasada la gracia** | `FAILED` y, en la misma llamada, `attempt+1` en `PREPARED` con reclamación nueva | 0 (`PROCEED`) |
   | `ABSENT` dentro de la gracia | sigue `DISPATCHED` | 6 |
   | `UNKNOWN` o error de la sonda, dentro de la gracia | sigue `DISPATCHED` | 6 |
   | `UNKNOWN` o error de la sonda, pasada la gracia | `NEEDS_REVIEW` (`review_origin: dispatched`) | 4 |

   Las dos conclusiones que no dependen del tiempo son `PRESENT` coincidente y `PRESENT` discrepante: lo observado ya existe y no va a cambiar esperando. Todo lo demás espera a la gracia. Con `reconcile <key>` rige la misma tabla, salvo que `ABSENT` pasada la gracia deja `FAILED` sin reclamar un intento nuevo y sale con 0.

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
4. **Nada se libera tras `dispatch`.** El `release` actual (borrar la reserva) desaparece: antes de `dispatch` se usa `fail --claim`, y después solo la sonda lleva a `FAILED`, con `ABSENT` definitivo pasada la gracia. Un error de lectura del remoto no equivale a «no ocurrió» (corrige H6).
5. **Resolución de `NEEDS_REVIEW`.** Hay dos rutas, excluyentes y elegidas por la orden, no por el entorno:

   | Ruta | Orden | Quién | Admite |
   |---|---|---|---|
   | **Por sonda** | `resolve <effect_id> --by-probe [--outcome succeeded\|failed]` | cualquiera, también un agente con `SAVIA_AUTONOMOUS_RUN=1` | solo `review_origin == dispatched` |
   | **Manual** | `resolve <effect_id> --manual --outcome succeeded\|failed --evidence <ref>` | solo una persona con grant | cualquier `review_origin` |

   - **Ruta por sonda (sin grant).** El CLI vuelve a ejecutar la sonda y el resultado sale **de la sonda**, nunca de quien llama: `PRESENT` coincidente → `SUCCEEDED` (`attribution: probe`); `ABSENT` definitivo con `now ≥ dispatched_at + dispatch_grace_s` → `FAILED`. Cualquier otra conclusión (incluido `PRESENT` discrepante) deja `NEEDS_REVIEW` y sale con 4. `--evidence` no se admite en esta ruta (exit 2). Si se pasa `--outcome` y no coincide con la conclusión de la sonda, sale con 2 sin escribir: un agente no puede obtener `attempt+1` declarando `failed` sobre un efecto aplicado. Con `review_origin` `pre_probe` o `migration`, sale con 2 sin sondear: este ledger no pidió ese efecto, y cerrarlo por sonda convertiría en propio un efecto de otra instalación del mismo operador, que es justo lo que 3c impide.
   - **Ruta manual (con grant).** Exige un grant vigente de la operadora con firma asimétrica, `operator-grant.sh check --scope effect-resolve --resource effect:<effect_id>`, con el mismo mecanismo que el scope `merge` (SE-343, LAW-HUMAN-002). Un agente no puede emitirlo solo. El grant es de un solo uso (`consume`). Es la única ruta para `pre_probe` y `migration`, y para `dispatched` cuando la sonda no concluye.
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
- `scripts/f5-state.sh` pasa a ser un envoltorio de compatibilidad sobre el ledger para `pr.merge`. Mantiene el exit 3 de `ALREADY_EXECUTED` y deja de devolver 0 en `submitted`.
  - **Interfaz del envoltorio.** La interfaz `f5 <cmd> <op> <key>` no lleva lo que el ledger necesita, así que se amplía con flags obligatorias para `reserve`:
    ```
    f5-state.sh reserve pr.merge <N> --repo <owner/name> --head <sha40> --method squash --holder-pid <pid>
      → stdout: "PROCEED <effect_id> <claim_token>"   (exit 0)  |  exits 2/3/4/5/6 del ledger tal cual
    f5-state.sh mark_submitted pr.merge <N> --effect <effect_id> --claim <claim_token>   → dispatch (sonda previa + CAS)
    f5-state.sh close          pr.merge <N> --effect <effect_id> --claim <claim_token> --response <json>   → complete
    f5-state.sh release        pr.merge <N> --effect <effect_id> --claim <claim_token>   → fail (solo PREPARED)
    f5-state.sh reconcile      pr.merge <N>                                              → reconcile
    f5-state.sh status         pr.merge <N>                                              → status (solo lectura)
    ```
    Falta de cualquier flag obligatoria → exit 2 sin tocar el ledger. El token **no** se guarda en disco: viaja por stdout al consumidor, que lo guarda en una variable de su propio shell durante el efecto. Así no queda un fichero de token huérfano tras una caída, y un proceso distinto del que reclamó no tiene el token. Los consumidores pasan `--holder-pid $$` (Regla 2b). `release` ya no borra nada: solo existe antes de `dispatch`; después, el consumidor llama a `reconcile`.
  - `f5 status` es **solo informativo** e imprime el estado, no el resultado de `prepare`: `PREPARED` → `reserved`, `DISPATCHED` → `submitted`, `SUCCEEDED` → `closed`, `NEEDS_REVIEW` → `needs_review`, `FAILED` → `failed`, ausencia → cadena vacía. `IN_FLIGHT` no es un estado (es un resultado de `prepare` o `dispatch`), así que `status` nunca lo imprime. Ningún consumidor decide con `status`: S3 sustituye el `case "$(f5 status …)"` de `merge-sprint.sh:611-616` por el exit de `f5 reconcile` (3 → `record_merge … reconciled`; 4 → parada `needs_review`; 6 → parada `in_flight`; 0 o 2 → parada `merge_externo` o `f5_error`). Así la gracia y la sonda las aplica siempre el ledger y la rama `reconcilable` deja de poder saltárselas. Mientras S3 no llega, el `*)` de `:616` ya para con `anomaly merge_externo` ante cualquier literal nuevo, y con el PR abierto `f5 reserve` sale ≠ 0 y para con `f5_reserva` (`:382`): falla cerrado.
  - Reescribir `f5-state.sh` cambia su blob, que el manifiesto de merge-sprint fija (`merge-sprint.sh:195` escribe `f5_blob`, `:584` lo comprueba con `anomaly blob_f5`). Los manifiestos firmados antes de S2 dejan de valer: S2 lo declara en el body y la operadora regenera el plan tras el merge.
- `push-pr.sh`:
  - `dispatch` antes de `gh pr merge` (corrige H4);
  - trata los exits 4, 5 y 6 como parada con mensaje que remite a `resolve`;
  - ante un error ambiguo de `gh` deja de decir «vuelve a ejecutar» y dice «resultado incierto: reconciliar» (corrige H3 y H5).
- `merge-sprint.sh`:
  - usa el mismo ledger (corrige H8). El `digest` del manifiesto no entra en la ruta ni en la huella: se guarda como `run_id` del intento, para que el ledger de merge-sprint siga sabiendo bajo qué manifiesto se pidió;
  - cambia `release` incondicional por `reconcile` (corrige H6);
  - un `NEEDS_REVIEW` para el sprint con un motivo propio, distinto de `merge_externo`.
- **Migración** de las reservas JSON (`effect-ledger.py migrate --from <dir>`). Las reservas antiguas no tienen head ni método (H9), así que nada importado se da por propio sin persona:
  - `closed` con sonda `PRESENT` → `SUCCEEDED` con recibo `attribution: migration` y la evidencia observada, marcando `headRefOid` y `method` como no verificados; con cualquier otra sonda → `NEEDS_REVIEW` (`review_origin: migration`).
  - `reserved` o `submitted` (un `reserved` de `push-pr` puede haber enviado el merge, H4) → sonda: `PRESENT` → `NEEDS_REVIEW` (`migration`); `ABSENT` definitivo con el `ts` del fichero anterior a `now - dispatch_grace_s` → `FAILED`; `ABSENT` más reciente o `UNKNOWN` → `NEEDS_REVIEW` (`migration`). Nunca `PROCEED`.
  - Idempotente: una segunda importación no crea entradas ni cambia estados (la unicidad `(op, idempotency_key)` lo garantiza) e informa `0 importadas`. Un JSON ilegible se cuenta y se reporta, sin abortar el resto ni crear entrada.
  - Los ficheros originales no se borran ni se modifican. S2 importa `~/.savia/reservations` (los de `push-pr`) y S3 los de `$HOME_MS/reservations/<digest>` (merge-sprint).
- `effect-reservation.sh` queda **deprecado sin consumidores**: se elimina, o se deja como envoltorio que imprime el aviso y delega. Su test se sustituye.
- `coherence-gates.sh` deja de contar «ejecutable» como cierre: ejecuta la suite de fallos inyectados de esta spec y bloquea si falla.
- Tests que cambian de expectativa, porque la semántica pasa de permisiva a bloqueante (no se debilita ninguna aserción; se invierte la que fijaba el defecto):
  - `f5-exactly-once.bats:29-33`;
  - `f5-cases.bats:40-46`;
  - `f5-cases.bats:32-38` se mantiene: `PREPARED` huérfano sigue siendo `PROCEED`.

## Criterios de aceptación

Todos los tests usan un remoto simulado (stub de `gh` en `PATH`) que **cuenta las peticiones de efecto**, y un ledger temporal por test bajo `$BATS_TEST_TMPDIR`. El fallo se inyecta en el punto indicado con `SAVIA_EFFECT_FAULT=<punto>`, que mata el proceso. El paso del tiempo se simula con `SAVIA_EFFECT_NOW`. Los dos ganchos solo actúan con las condiciones de la Regla 7. «Relanzar tarde» significa relanzar con `SAVIA_EFFECT_NOW = dispatched_at + dispatch_grace_s + 1`, y «relanzar al momento», sin adelantar el reloj. Cada test debe fallar contra el código de main en fa3f486a0 o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes/después.

Matriz V1:

- **AC-a — caída antes de iniciar.** Punto: tras `prepare`, antes de `dispatch`. El fallo mata al **llamador** (el proceso cuyo PID se pasó con `--holder-pid`), así que el `PREPARED` es huérfano sin esperar al lease. Al relanzar: `PROCEED` con token nuevo, el efecto se pide una vez y queda `SUCCEEDED` con recibo. Contador remoto = 1. Negativos:
  - relanzar otra vez da `ALREADY_EXECUTED` y el contador sigue en 1;
  - con el llamador vivo (un `sleep` cuyo PID se pasa con `--holder-pid`) y el lease vigente, un segundo `prepare` da `IN_FLIGHT` (6); con el llamador vivo y el lease **vencido**, también 6 (Regla 2b, paso 2);
  - `prepare` de `pr.merge` sin `--holder-pid` sale con 2 sin escribir en el ledger;
  - vía envoltorio: un consumidor de prueba que llama a `f5-state.sh reserve … --holder-pid $$` desde dentro de un subshell `( cd … && … )` registra el PID del shell principal; tras salir el subshell, un segundo `reserve` desde otro proceso da 6. `f5-state.sh reserve` sin `--head`, `--repo`, `--method` o `--holder-pid` sale con 2 sin tocar el ledger;
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
- **AC-d — misma clave, otros argumentos.** `prepare` con la misma `(op, key)` y otro head SHA da `CONFLICT` (exit 5), sin llamada remota y con el ledger intacto. Límite: misma clave y mismos argumentos tras `SUCCEEDED` da exit 3 con el recibo original, byte a byte.
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
  - **Dos rutas:** `push-pr.sh` y `merge-sprint.sh` sobre el mismo `pr.merge/N`, mismo repo, head y método, ven la misma entrada del ledger aunque merge-sprint lleve un `digest` de manifiesto: la segunda ruta obtiene `IN_FLIGHT` (6) o `ALREADY_EXECUTED` (3), **nunca** `CONFLICT` (5), y el contador remoto queda en 1. Negativo: con otro head, la segunda ruta obtiene `CONFLICT` (5) sin llamada remota.
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
- **AC-n — validación de entradas (Regla 8).** `prepare` con número `12; DROP`, repo `-R--foo/x`, `x/-y`, `../..`, `./x`, `x/..` o `a/b/c`, head de 39 caracteres o en mayúsculas, o método `fast-forward` sale con 2, sin escribir en el ledger y sin llamada remota. Límite: el mismo `prepare` con valores válidos da 0. Sin identidad remota (`gh api user` falla o devuelve vacío), `prepare` sale con 2 sin reclamar (Regla 6b); con `mergedBy` que solo difiere en mayúsculas, la sonda es coincidente.
- **AC-j — multioperador.**
  - Ninguna ruta absoluta ni identidad literal en el código. El ledger se resuelve por `$HOME` (o la variable de test) y el actor sale del perfil activo. Se comprueba con `grep -nE '(/home/|/Users/|/root/)'` sobre `effect-ledger.py`, el registro de operaciones y los consumidores tocados: 0 coincidencias; el test se valida mutando un fichero temporal con una ruta literal y viendo que falla.
  - Los tests corren con dos operadores sintéticos y dos `HOME` temporales; ninguno escribe en el `HOME` real.
  - Sin perfil activo, `prepare` de un efecto `non_idempotent` falla cerrado (exit 2).
- **AC-k — cierre honesto en coherence-gates.**
  - `coherence-gates.sh` ejecuta la suite de esta spec; si se rompe un test de la matriz, el gate marca BLOCK.
  - `effect-reservation.sh` no tiene consumidores, o está eliminado.
- **AC-l — fail-closed.** Si el ledger está corrupto, bloqueado más allá del timeout de `sqlite3`, en un disco sin escritura o con un esquema desconocido, el resultado es exit 2 y nunca `PROCEED`. Además:
  - tras abrir, `PRAGMA journal_mode` es `wal` y `PRAGMA synchronous` es `2` (FULL); si el CLI no logra fijarlos (simulado con un gancho de prueba que fuerza `NORMAL`), exit 2 sin escribir (Regla 1);
  - un registro de operaciones con una `op` `non_idempotent` sin sonda previa hace que cualquier orden salga con 2 (Regla 7b);
  - sin `SAVIA_EFFECT_TEST=1`, `SAVIA_EFFECT_LEDGER` se ignora con aviso en stderr y se usa el ledger de `$HOME` (un `HOME` temporal en el test).
- **AC-o — migración de reservas JSON.** Con un directorio de reservas sintético y la sonda simulada:
  - `closed` con sonda `PRESENT` → `SUCCEEDED` con `attribution: migration`; `closed` con sonda `UNKNOWN` → `NEEDS_REVIEW` (`migration`);
  - `submitted` y `reserved` con sonda `PRESENT` → `NEEDS_REVIEW` (`migration`); con `UNKNOWN` → `NEEDS_REVIEW`; con `ABSENT` y `ts` anterior a la gracia → `FAILED`; con `ABSENT` y `ts` reciente → `NEEDS_REVIEW`. Ninguno queda en un estado que dé `PROCEED` sin pasar por `FAILED` confirmado;
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

1. **S1** — `effect-ledger.py` (reclamación, CAS, gracia, `complete`/`fail`, `resolve --by-probe`, durabilidad, ganchos de prueba, validación de entradas) y el registro de operaciones con stub; tests AC-a (CLI), AC-d, AC-f (mismo ledger), AC-h, AC-l, AC-m, AC-n y la parte por sonda de AC-i. Sin consumidores: no produce entradas `pre_probe` ni `migration`.
2. **S2** — Sonda `pr.merge` con el criterio de 3b y sonda previa (3c); envoltorio `f5-state.sh` con la interfaz ampliada; `push-pr.sh` con write-ahead, `timeout` y nuevos mensajes; scope `effect-resolve` en `operator-grant.sh` y `resolve --manual`; `migrate` de `~/.savia/reservations`. AC-a (envoltorio), AC-b, AC-c, AC-e, AC-g para `push-pr`, AC-i completo y AC-o. Va junto con el grant porque S2 es el primer slice que produce `pre_probe` y `migration`, que solo se resuelven con grant: sin él, esas entradas quedarían sin salida.
3. **S3** — `merge-sprint.sh`: ledger único, `reconcile` en lugar de `release` y en lugar del `case` sobre `status`, motivos `needs_review` e `in_flight`, y `migrate` de `$HOME_MS/reservations`; AC-f (dos rutas, dos instalaciones, mismo operador), AC-g para `merge-sprint` y AC-o para ese directorio. Tests de `test-merge-sprint.bats` AC-25/26 en verde sin debilitar.
4. **S4** — `coherence-gates.sh` y deprecación de `effect-reservation.sh`; AC-k y AC-j.

Cada slice es una PR Draft. S2 y S3 tocan el camino de merge y S2 además el sistema de grants, así que los dos son tier 3 y exigen revisión humana explícita (SE-362). S4 toca un gate, también tier 3.

## Riesgos

- **Sobrebloqueo:** más paradas en `NEEDS_REVIEW` cuando la red falla. Es el comportamiento buscado; el coste es una resolución manual por caso, medible en el ledger.
- **Espera tras un rechazo:** un «not mergeable» deja la clave en `IN_FLIGHT` durante `dispatch_grace_s` (300 s para `pr.merge`) antes de admitir un nuevo intento. Es el precio de no deducir un rechazo del texto de `gh`.
- **Atribución por sonda:** el mismo operador en dos instalaciones puede compartir un recibo `attribution: probe` mal atribuido dentro de la ventana de carrera (Regla 6). Queda documentado en el recibo y no se presenta como verificado.
- **Migración de reservas existentes:** los JSON de `~/.savia/reservations` y de merge-sprint se importan con `migrate` (AC-o). Un `submitted` sin sonda concluyente entra como `NEEDS_REVIEW`, nunca como `PROCEED`.
- **Cola de merge:** los repos con cola de merge obligatoria no están soportados por `pr.merge` v1 (3b).
- **Llamador colgado:** un llamador vivo conserva su reclamación aunque venza el lease (Regla 2b, paso 2). Si se cuelga sin morir, la clave queda en `IN_FLIGHT` hasta que alguien lo mate. Falla cerrado: bloquea, no repite.
- **Manifiestos de merge-sprint:** S2 cambia el blob de `f5-state.sh` fijado en el manifiesto (`merge-sprint.sh:195`, `:584`). Los planes firmados antes quedan inválidos con `anomaly blob_f5`, que es el comportamiento correcto.
- **Más grants manuales:** las entradas `pre_probe` y `migration` exigen siempre grant (Regla 5). La migración inicial puede producir varias; se cuentan en el ledger.
- **Divergencia de envoltorios:** `f5-state.sh` queda como capa fina. Un test compara sus exits con los del ledger para cada estado.

## Rollback

Revertir el PR del slice. El ledger es aditivo: los JSON antiguos no se borran ni se modifican (la migración solo lee), y S1 no cambia el comportamiento de ningún consumidor.

Revertir S2 o S3 tiene un coste: los consumidores vuelven a los JSON y no ven las entradas creadas en el ledger desde entonces. Antes de revertir, `effect-ledger.py status --open` lista las entradas `PREPARED`, `DISPATCHED` y `NEEDS_REVIEW`; se resuelven o se reconcilian primero. Con alguna `DISPATCHED` o `NEEDS_REVIEW` abierta, el revert no se hace.

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
