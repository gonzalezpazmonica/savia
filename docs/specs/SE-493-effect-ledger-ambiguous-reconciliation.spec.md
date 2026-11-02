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
| `args` / `args_digest` | JSON canónico de los argumentos que determinan el efecto (`sort_keys`, separadores compactos, UTF-8) y su SHA-256. Se guardan los dos para que la sonda compare campo a campo. Para `pr.merge`: repo, número, head SHA y método. Cada `op` declara cuáles de esos campos puede **observar** su sonda. En `pr.merge`, `gh pr view` muestra repo, número y `headRefOid`, pero no el método: el método entra en la huella (otro método es `CONFLICT`) y el recibo lo marca como `requested`, no verificado. |
| `install_id` | UUID creado al inicializar el ledger y guardado en su tabla `meta`. Distingue dos instalaciones del mismo operador. |
| `claim_token`, `lease_until`, `holder_pid` | quién tiene reclamada la clave y hasta cuándo (Regla 2b) |
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
   │                       └──sonda incierta / evidencia que no coincide──▶ NEEDS_REVIEW
   ├──sonda previa PRESENT──▶ NEEDS_REVIEW
   └──abort antes de dispatch──▶ (borrado o FAILED)
NEEDS_REVIEW ──resolve con evidencia──▶ SUCCEEDED | FAILED
```

Reglas:

1. **Write-ahead:** `DISPATCHED` se persiste y se sincroniza a disco **antes** de enviar la petición. Un `PREPARED` encontrado después de una caída significa, por construcción, que la petición no salió.
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
   - `prepare` con `PROCEED` escribe en la misma transacción un `claim_token` aleatorio, `holder_pid` y `lease_until = now + lease_s`, y devuelve el token. Si otro proceso consulta mientras la reclamación está vigente, obtiene `IN_FLIGHT` (6), aunque el estado sea `PREPARED`.
   - Un `PREPARED` es **huérfano** solo si su lease ha vencido, o si su `install_id` es el local y `holder_pid` ya no existe. Solo entonces otro `prepare` puede reclamarlo con un token nuevo.
   - `dispatch <effect_id> --claim <token>` es un compare-and-set: `UPDATE … SET state='DISPATCHED' WHERE effect_id=? AND state='PREPARED' AND claim_token=?`. Si no cambia exactamente una fila, sale con 6 y quien llama **no envía** la petición. De dos workers, como mucho uno pasa el CAS.

   **2c. Gracia y reloj.** Cada `op` declara en el registro `request_timeout_s` y `dispatch_grace_s`, con `dispatch_grace_s ≥ request_timeout_s + 60`. Para `pr.merge`: 120 s y 300 s.
   - Quien llama ejecuta la petición acotada por `request_timeout_s` (`timeout` en bash). Pasado ese plazo, la petición se da por terminada en el cliente.
   - Un `DISPATCHED` con `now < dispatched_at + dispatch_grace_s` está **en vuelo**: `prepare` da 6 y `reconcile` no concluye `ABSENT`.
   - `now` sale del reloj del sistema. En tests puede fijarse con `SAVIA_EFFECT_NOW` (Regla 7).

3. **Reconciliación al reintentar:** con la clave `DISPATCHED`, `prepare` o `reconcile <key>` ejecutan la **sonda** de la operación y resuelven según su respuesta:

   | Sonda | Estado nuevo | Exit |
   |---|---|---|
   | `PRESENT`, con los campos observables iguales a `args` y `mergedBy` igual al actor | `SUCCEEDED` | 3 |
   | `ABSENT` definitivo (3b), y solo **pasada la gracia** | `FAILED` | 0 en el siguiente `prepare` |
   | `ABSENT` dentro de la gracia | sigue `DISPATCHED` | 6 |
   | `UNKNOWN`, error o evidencia que no coincide | `NEEDS_REVIEW` | 4 |

   `PRESENT` sí puede concluirse dentro de la gracia. Es la única conclusión que no depende del tiempo.

   **Nunca se reenvía** un `non_idempotent` desde `DISPATCHED`.

   **3b. `ABSENT` definitivo, cerrado por `op`.** La salida de `gh pr merge` (código y texto) **nunca** clasifica un rechazo. Desde `DISPATCHED` solo se llega a `FAILED` por la sonda. Para `pr.merge`, `ABSENT` exige todo esto a la vez:
   - `gh pr view <N> -R <repo> --json state,mergedAt,mergeCommit,headRefOid` sale con 0;
   - la salida es JSON válido con esas cuatro claves;
   - `state == "OPEN"`, `mergedAt` y `mergeCommit` nulos y `headRefOid` igual al head de `args`.

   Cualquier otra cosa es `UNKNOWN`: código distinto de 0 aunque el texto diga `OPEN` (respuesta parcial tras un 5xx), JSON truncado, claves ausentes, `CLOSED` sin merge, o un head distinto. Un «not mergeable» se registra como evidencia, pero el `FAILED` lo decide la sonda pasada la gracia, no el texto.

   **3c. Sonda previa al `dispatch`.** Si la `op` tiene sonda, `dispatch` la ejecuta antes del CAS:
   - si da `PRESENT`, no se envía nada y la entrada pasa a `NEEDS_REVIEW` (4) con la evidencia observada. El efecto existe y este ledger no lo pidió: lo hizo otra instalación u otro actor;
   - si da `UNKNOWN`, no se envía nada, la entrada sigue `PREPARED` con su reclamación y sale con 2;
   - si da `ABSENT`, se hace el CAS y se envía.

   Queda una ventana entre la sonda previa y el envío. Para `pr.merge` la cierra GitHub (`--match-head-commit` y no se mergea dos veces). Una `op` sin protección remota equivalente debe declararlo en el registro.
4. **`release` solo con `ABSENT` definitivo.** Un error de lectura del remoto no equivale a «no ocurrió» (corrige H6).
5. **Resolución de `NEEDS_REVIEW`:** `resolve <effect_id> --outcome succeeded|failed --evidence <ref>`.
   - **Autoridad:** la resolución manual exige un grant vigente de la operadora con firma asimétrica, `operator-grant.sh check --scope effect-resolve --resource effect:<effect_id>`, con el mismo mecanismo que el scope `merge` (SE-343, LAW-HUMAN-002). Un agente no puede emitirlo solo. El grant es de un solo uso (`consume`).
   - `SAVIA_AUTONOMOUS_RUN=1` y la rama `agent/*` son una barrera **débil**, porque los controla el propio proceso. Se mantienen como rechazo temprano (exit 2), pero no conceden nada: su ausencia no sustituye al grant.
   - Sin grant, solo cierra una sonda definitiva (`PRESENT` coincidente o `ABSENT` pasada la gracia).
   - Queda en el ledger quién resolvió, con qué grant y con qué evidencia.
6. **Recibo verificable:** registro JSON con
   - `effect_id`, `op`, `key`, `args_digest`, `actor`, `install_id` y `outcome`;
   - la evidencia remota (para `pr.merge`: `merge_commit`, `mergedBy`, `headRefOid`) y la lista de campos de `args` **no verificados** (para `pr.merge`, `method`);
   - `attribution`: `response` si el remoto confirmó la petición de este ledger, o `probe` si el éxito se dedujo por la sonda tras una caída;
   - `observed_at` y `prev_hash`.

   **Limitación conocida:** con `attribution: probe`, el remoto no distingue dos instalaciones del mismo operador, porque `mergedBy` es la misma cuenta. Si la otra máquina mergea el mismo PR y head dentro de la ventana de gracia, el recibo lo atribuye a esta. La sonda previa (3c) reduce la ventana a una carrera entre dos `dispatch` casi simultáneos. El recibo no afirma más de lo que se observó.

   Los recibos se encadenan por hash, como el ledger de merge-sprint. `verify-receipt <effect_id>` comprueba la cadena y vuelve a observar el remoto:
   - devuelve `VERIFIED` solo si ambas cosas coinciden;
   - si la sonda no está disponible, devuelve `UNVERIFIED`, nunca `VERIFIED`.
7. **Ganchos de prueba inertes fuera de tests.** `SAVIA_EFFECT_FAULT` (mata el proceso en un punto) y `SAVIA_EFFECT_NOW` (fija el reloj) solo se aplican si se cumplen las dos condiciones:
   - `SAVIA_EFFECT_TEST=1`;
   - la ruta real (`realpath`) de `SAVIA_EFFECT_LEDGER` está bajo `${TMPDIR:-/tmp}` y no es la ruta por defecto.

   Si falta alguna, se ignoran, se escribe un aviso en stderr y el ledger sigue con el reloj real y sin fallos. Con el ledger real, una variable olvidada no puede dejar `DISPATCHED` a voluntad ni adelantar la gracia.

### Implementación prevista

- `scripts/effect-ledger.py` (Python stdlib, `sqlite3` con `BEGIN IMMEDIATE`). Expone `prepare`, `dispatch`, `complete`, `fail`, `resolve`, `status`, `verify-receipt` y `reconcile`. El ledger vive en `${SAVIA_EFFECT_LEDGER:-$HOME/.savia/effects/ledger.db}`, por instalación y fuera del repo.
- **Registro de operaciones** por `op`: clase, sonda, campos observables, `request_timeout_s`, `dispatch_grace_s`, `lease_s` y si hay protección remota contra la doble ejecución (3c). La primera es `pr.merge`. Su sonda lee `gh pr view` (`state`, `mergedAt`, `headRefOid`, `mergedBy`, `mergeCommit`) con `-R` explícito, aplica el criterio cerrado de 3b y devuelve `UNKNOWN` ante cualquier error.
- `operator-grant.sh` gana el scope `effect-resolve`, con firma asimétrica obligatoria como `merge` (Regla 5). Toca el sistema de grants, así que entra en S4 con revisión humana.
- `scripts/f5-state.sh` pasa a ser un envoltorio de compatibilidad sobre el ledger para `pr.merge`. Mantiene el exit 3 de `ALREADY_EXECUTED` y deja de devolver 0 en `submitted`.
- `push-pr.sh`:
  - `dispatch` antes de `gh pr merge` (corrige H4);
  - trata los exits 4, 5 y 6 como parada con mensaje que remite a `resolve`;
  - ante un error ambiguo de `gh` deja de decir «vuelve a ejecutar» y dice «resultado incierto: reconciliar» (corrige H3 y H5).
- `merge-sprint.sh`:
  - usa el mismo ledger (corrige H8; el `digest` del manifiesto entra en la huella, no en la ruta);
  - cambia `release` incondicional por `reconcile` (corrige H6);
  - un `NEEDS_REVIEW` para el sprint con un motivo propio, distinto de `merge_externo`.
- `effect-reservation.sh` queda **deprecado sin consumidores**: se elimina, o se deja como envoltorio que imprime el aviso y delega. Su test se sustituye.
- `coherence-gates.sh` deja de contar «ejecutable» como cierre: ejecuta la suite de fallos inyectados de esta spec y bloquea si falla.
- Tests que cambian de expectativa, porque la semántica pasa de permisiva a bloqueante (no se debilita ninguna aserción; se invierte la que fijaba el defecto):
  - `f5-exactly-once.bats:29-33`;
  - `f5-cases.bats:40-46`;
  - `f5-cases.bats:32-38` se mantiene: `PREPARED` huérfano sigue siendo `PROCEED`.

## Criterios de aceptación

Todos los tests usan un remoto simulado (stub de `gh` en `PATH`) que **cuenta las peticiones de efecto**, y un ledger temporal por test bajo `$BATS_TEST_TMPDIR`. El fallo se inyecta en el punto indicado con `SAVIA_EFFECT_FAULT=<punto>`, que mata el proceso. El paso del tiempo se simula con `SAVIA_EFFECT_NOW`. Los dos ganchos solo actúan con las condiciones de la Regla 7. «Relanzar tarde» significa relanzar con `SAVIA_EFFECT_NOW = dispatched_at + dispatch_grace_s + 1`, y «relanzar al momento», sin adelantar el reloj. Cada test debe fallar contra el código de main en fa3f486a0 o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes/después.

Matriz V1:

- **AC-a — caída antes de iniciar.** Punto: tras `prepare`, antes de `dispatch`. El proceso muerto deja `holder_pid` inexistente, así que el `PREPARED` es huérfano sin esperar al lease. Al relanzar: `PROCEED` con token nuevo, el efecto se pide una vez y queda `SUCCEEDED` con recibo. Contador remoto = 1. Negativos:
  - relanzar otra vez da `ALREADY_EXECUTED` y el contador sigue en 1;
  - con el `holder_pid` vivo y el lease vigente, un segundo `prepare` da `IN_FLIGHT` (6);
  - `dispatch` con el token antiguo sale con 6 sin llamada remota.
- **AC-b — caída tras pedir el efecto y antes del recibo.** Punto: tras enviar la petición, antes de `complete`. En ningún caso se vuelve a llamar al efecto:
  - (b0) relanzar al momento con sonda `ABSENT`: `IN_FLIGHT` (6) y sigue `DISPATCHED`;
  - (b1) relanzar al momento o tarde con sonda `PRESENT`, campos observables y actor coincidentes: `SUCCEEDED`, recibo con `attribution: probe` y exit 3;
  - (b2) relanzar tarde con sonda `UNKNOWN`: `NEEDS_REVIEW` con exit 4.

  Contador remoto = 1 en todos. Contra main falla: `f5-state.sh` devuelve 0 y `push-pr.sh` repite el merge.
- **AC-c — efecto confirmado y caída antes de cerrar.** Punto: tras la respuesta OK del remoto, antes de escribir `SUCCEEDED`. Al relanzar al momento, la sonda `PRESENT` cierra con recibo que contiene la evidencia remota (`merge_commit`). No hace falta adelantar el reloj, porque `PRESENT` no depende de la gracia. Contador = 1 y exactamente un `SUCCEEDED` y un recibo en la cadena.
- **AC-d — misma clave, otros argumentos.** `prepare` con la misma `(op, key)` y otro head SHA da `CONFLICT` (exit 5), sin llamada remota y con el ledger intacto. Límite: misma clave y mismos argumentos tras `SUCCEEDED` da exit 3 con el recibo original, byte a byte.
- **AC-e — respuesta remota ambigua.** La petición de efecto falla de forma ambigua y se relanza tarde. Cada variante de la **sonda** termina en `NEEDS_REVIEW` (exit 4), sin reintento automático, con contador = 1 y sin borrar la reserva:
  - timeout del stub tras aplicar el efecto, con sonda que no responde;
  - sonda con 5xx;
  - sonda con salida no JSON o JSON truncado;
  - sonda con código ≠ 0 y texto `"state":"OPEN"` (respuesta parcial);
  - sonda con `OPEN` y un `headRefOid` distinto del pedido;
  - `gh` ausente del `PATH`;
  - sonda que devuelve cadena vacía.

  Negativos y límite:
  - el stub de merge responde «not mergeable» con código ≠ 0 y la sonda lee `OPEN` válido (3b). Al relanzar al momento da `IN_FLIGHT` (6). Al relanzar en `dispatched_at + dispatch_grace_s - 1` sigue en 6, y en `+ dispatch_grace_s + 1` pasa a `FAILED` y admite un `attempt` nuevo;
  - el texto de `gh pr merge` no cambia el resultado: el mismo stub con texto de éxito y código ≠ 0 sigue el mismo camino;
  - con `SAVIA_EFFECT_TEST` sin definir, o con el ledger fuera de `${TMPDIR:-/tmp}`, `SAVIA_EFFECT_NOW` se ignora (Regla 7) y el estado sigue `DISPATCHED`.
- **AC-f — concurrencia de dos workers.**
  - **Mismo ledger:** 20 rondas con dos procesos simultáneos sobre la misma clave, partiendo de registro nuevo y de `PREPARED` huérfano. En cada ronda, exactamente uno obtiene `PROCEED` y pasa el CAS de `dispatch`. El otro obtiene `IN_FLIGHT` o `ALREADY_EXECUTED`, o, si llegó a `PROCEED` con un token ya sustituido, su `dispatch` sale con 6. Contador remoto = 20, uno por ronda.
  - **Dos rutas:** `push-pr.sh` y `merge-sprint.sh` sobre el mismo `pr.merge/N` ven la misma entrada del ledger.
  - **Dos instalaciones con ledgers distintos (multioperador):** la segunda llega con su ledger vacío y obtiene `PROCEED`. La sonda previa de `dispatch` (3c) encuentra el efecto `PRESENT`, hecho por otro actor, y deja la entrada en `NEEDS_REVIEW` (4) con la evidencia del otro actor. Contador remoto = 1: ni repite ni lo da por propio. Negativo: con la sonda previa `UNKNOWN`, sale con 2 sin llamada remota y la entrada sigue `PREPARED`.
  - **Mismo operador en dos instalaciones:** igual que el caso anterior, pero con el mismo `mergedBy`. La sonda previa da `NEEDS_REVIEW`, nunca `SUCCEEDED`, porque este ledger no tiene `DISPATCHED`. El recibo de la primera instalación lleva su `install_id`.

Contrato:

- **AC-g — sin repetición automática en estado ambiguo.** Para cada estado `DISPATCHED`, `NEEDS_REVIEW` e `IN_FLIGHT`, ningún consumidor (`push-pr.sh`, `merge-sprint.sh`, `f5-state.sh`) llega a la llamada de efecto. Lo prueba el contador del stub, no un grep.
- **AC-h — recibo verificable.** `verify-receipt` da `VERIFIED` con cadena íntegra y remoto coincidente. Da `FAIL` si se altera un byte de un recibo anterior o si cambia el `merge_commit` remoto, y `UNVERIFIED` (exit ≠ 0) sin sonda. `VERIFIED` no cubre los campos que el recibo marca como no verificados (`method`), y la salida lo dice.
- **AC-i — resolución atribuida.**
  - `resolve` manual con un grant `effect-resolve` vigente y firmado para ese `effect_id` registra actor, grant y evidencia, y consume el grant;
  - un segundo `resolve` con el mismo grant se rechaza con exit 2;
  - sin grant, con un grant de otro `effect_id` o con uno caducado, se rechaza con exit 2, **también sin `SAVIA_AUTONOMOUS_RUN` y fuera de una rama `agent/*`**. Este caso prueba que borrar las señales de entorno no concede nada;
  - con `SAVIA_AUTONOMOUS_RUN=1`, se rechaza con exit 2 aunque haya grant;
  - con sonda definitiva, el agente sí puede cerrar sin grant.
- **AC-j — multioperador.**
  - Ninguna ruta absoluta ni identidad literal en el código. El ledger se resuelve por variable o `$HOME` y el actor sale del perfil activo.
  - Los tests corren con dos operadores sintéticos y dos `HOME` temporales; ninguno escribe en el `HOME` real.
  - Sin perfil activo, `prepare` de un efecto `non_idempotent` falla cerrado (exit 2).
- **AC-k — cierre honesto en coherence-gates.**
  - `coherence-gates.sh` ejecuta la suite de esta spec; si se rompe un test de la matriz, el gate marca BLOCK.
  - `effect-reservation.sh` no tiene consumidores, o está eliminado.
- **AC-l — fail-closed.** Si el ledger está corrupto, bloqueado más allá del timeout de `sqlite3`, en un disco sin escritura o con un esquema desconocido, el resultado es exit 2 y nunca `PROCEED`.
- **AC-m — ganchos de prueba inertes.** Con el ledger en la ruta por defecto (un `HOME` temporal) y `SAVIA_EFFECT_FAULT` y `SAVIA_EFFECT_NOW` definidos:
  - sin `SAVIA_EFFECT_TEST=1`, el flujo completo termina `SUCCEEDED`, sin caída, con el reloj real y con un aviso en stderr;
  - con `SAVIA_EFFECT_TEST=1` y el ledger fuera de `${TMPDIR:-/tmp}`, el resultado es el mismo.

  Positivo de control: con las dos condiciones cumplidas, el mismo `SAVIA_EFFECT_FAULT` mata el proceso.

## Fuera de alcance

- Adoptar OpenRath (runtime, servidor, Postgres, scheduler) o cualquier dependencia nueva.
- Ledger compartido entre máquinas u operadores: cada instalación tiene el suyo y el remoto es la autoridad común (AC-f).
- Firma criptográfica de recibos: el encadenado por hash basta para v1, y la firma se valorará junto a los recibos de SE-488.
- Registrar efectos distintos de `pr.merge`. El contrato y el registro lo permiten; cada `op` nueva necesita su sonda y sus tests en una PR propia.
- Reconciliador periódico en segundo plano: la reconciliación ocurre al reintentar la misma clave o con `reconcile` explícito.

## Plan por slices

1. **S1** — `effect-ledger.py` (reclamación, CAS, gracia, ganchos de prueba) y el registro de operaciones con stub; tests AC-a, AC-d, AC-f (mismo ledger), AC-h, AC-l y AC-m.
2. **S2** — Sonda `pr.merge` con el criterio de 3b y sonda previa (3c); envoltorio `f5-state.sh`; `push-pr.sh` con write-ahead, `timeout` y nuevos mensajes; AC-b, AC-c, AC-e y AC-g para `push-pr`.
3. **S3** — `merge-sprint.sh`: ledger único, `reconcile` en lugar de `release` y motivo `needs_review`; AC-f (dos rutas, dos instalaciones, mismo operador) y AC-g para `merge-sprint`. Tests de `test-merge-sprint.bats` AC-25/26 en verde sin debilitar.
4. **S4** — `coherence-gates.sh`, deprecación de `effect-reservation.sh` y scope `effect-resolve` en `operator-grant.sh`; AC-k, AC-i y AC-j.

Cada slice es una PR Draft. S2 y S3 tocan el camino de merge, y S4 el sistema de grants, así que los tres son tier 3 y exigen revisión humana explícita (SE-362).

## Riesgos

- **Sobrebloqueo:** más paradas en `NEEDS_REVIEW` cuando la red falla. Es el comportamiento buscado; el coste es una resolución manual por caso, medible en el ledger.
- **Espera tras un rechazo:** un «not mergeable» deja la clave en `IN_FLIGHT` durante `dispatch_grace_s` (300 s para `pr.merge`) antes de admitir un nuevo intento. Es el precio de no deducir un rechazo del texto de `gh`.
- **Atribución por sonda:** el mismo operador en dos instalaciones puede compartir un recibo `attribution: probe` mal atribuido dentro de la ventana de carrera (Regla 6). Queda documentado en el recibo y no se presenta como verificado.
- **Migración de reservas existentes:** los JSON de `~/.savia/reservations` se importan una vez. Un `submitted` sin sonda concluyente entra como `NEEDS_REVIEW`, nunca como `PROCEED`.
- **Divergencia de envoltorios:** `f5-state.sh` queda como capa fina. Un test compara sus exits con los del ledger para cada estado.

## Rollback

Revertir el PR del slice. El ledger es aditivo: los JSON antiguos no se borran hasta S4, y S1 no cambia el comportamiento de ningún consumidor.

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
