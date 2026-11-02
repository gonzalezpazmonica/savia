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
| `args_digest` | SHA-256 del JSON canónico de los argumentos que determinan el efecto (`sort_keys`, separadores compactos, UTF-8). Para `pr.merge`: repo, número, head SHA, método. |
| `effect_class` | `read_only \| idempotent_remote \| non_idempotent`. Por defecto `non_idempotent`; `idempotent_remote` solo si el registro de operaciones lo declara con evidencia de que el remoto respeta la clave. |
| `actor` | identificador del perfil activo (como `operator-grant.sh`), nunca un nombre literal en código |
| `run_id`, `attempt`, `state`, marcas de tiempo | — |
| `observation` | última evidencia remota |
| `receipt` | recibo, si existe |

Unicidad: `(op, idempotency_key)`.

Estados y transiciones (las demás se rechazan):

```
PREPARED ──dispatch──▶ DISPATCHED ──ok confirmado──▶ SUCCEEDED (terminal, con recibo)
   │                       │──rechazo confirmado─▶ FAILED (sin efecto; admite attempt+1)
   │                       └──respuesta ambigua / caída / sonda incierta──▶ NEEDS_REVIEW
   └──abort antes de dispatch──▶ (borrado o FAILED)
NEEDS_REVIEW ──resolve con evidencia──▶ SUCCEEDED | FAILED
```

Reglas:

1. **Write-ahead:** `DISPATCHED` se persiste y se sincroniza a disco **antes** de enviar la petición. Un `PREPARED` encontrado después de una caída significa, por construcción, que la petición no salió.
2. **Nada ambiguo devuelve exit 0.** Códigos de `prepare`:

   | Exit | Resultado | Cuándo |
   |---|---|---|
   | 0 | `PROCEED` | registro nuevo, `PREPARED` huérfano o `FAILED` confirmado |
   | 3 | `ALREADY_EXECUTED` | imprime el recibo |
   | 4 | `NEEDS_REVIEW` | — |
   | 5 | `CONFLICT` | misma clave, otra huella |
   | 6 | `IN_FLIGHT` | otro proceso tiene el efecto `DISPATCHED` y no caducado |
   | 2 | error | ledger ilegible, herramienta ausente u orden inválida; fail-closed |

3. **Reconciliación al reintentar:** si la clave está `DISPATCHED` y caducada, se ejecuta la **sonda** de la operación y se resuelve según su respuesta:

   | Sonda | Estado nuevo | Exit |
   |---|---|---|
   | `PRESENT`, con evidencia que coincide con `args_digest` y `actor` | `SUCCEEDED` | 3 |
   | `ABSENT` definitivo | `FAILED` | 0 en el siguiente `prepare` |
   | `UNKNOWN`, error o evidencia que no coincide | `NEEDS_REVIEW` | 4 |

   **Nunca se reenvía** un `non_idempotent` desde `DISPATCHED`.
4. **`release` solo con `ABSENT` definitivo.** Un error de lectura del remoto no equivale a «no ocurrió» (corrige H6).
5. **Resolución de `NEEDS_REVIEW`:** `resolve <effect_id> --outcome succeeded|failed --evidence <ref>`.
   - La resolución manual exige un actor humano (perfil activo, no modo agente). Con `SAVIA_AUTONOMOUS_RUN=1` o en rama `agent/*`, solo vale una sonda definitiva.
   - Queda en el ledger quién resolvió y con qué evidencia.
6. **Recibo verificable:** registro JSON con
   - `effect_id`, `op`, `key`, `args_digest`, `actor` y `outcome`;
   - la evidencia remota (para `pr.merge`: `merge_commit`, `mergedBy`, `headRefOid`);
   - `observed_at` y `prev_hash`.

   Los recibos se encadenan por hash, como el ledger de merge-sprint. `verify-receipt <effect_id>` comprueba la cadena y vuelve a observar el remoto:
   - devuelve `VERIFIED` solo si ambas cosas coinciden;
   - si la sonda no está disponible, devuelve `UNVERIFIED`, nunca `VERIFIED`.

### Implementación prevista

- `scripts/effect-ledger.py` (Python stdlib, `sqlite3` con `BEGIN IMMEDIATE`). Expone `prepare`, `dispatch`, `complete`, `fail`, `resolve`, `status`, `verify-receipt` y `reconcile`. El ledger vive en `${SAVIA_EFFECT_LEDGER:-$HOME/.savia/effects/ledger.db}`, por instalación y fuera del repo.
- **Registro de operaciones** con clase y sonda por `op`. La primera es `pr.merge`; su sonda lee `gh pr view` (`state`, `headRefOid`, `mergedBy`, `mergeCommit`) con `-R` explícito y devuelve `UNKNOWN` ante cualquier error.
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

Todos los tests usan un remoto simulado (stub de `gh` en `PATH`) que **cuenta las peticiones de efecto**, y un ledger temporal por test. El fallo se inyecta en el punto indicado con una variable de prueba que mata el proceso (`SAVIA_EFFECT_FAULT=<punto>`), inerte fuera de tests. Cada test debe fallar contra el código de main en fa3f486a0 o contra la aserción mutada; el PR de implementación lo demuestra con la salida antes/después.

Matriz V1:

- **AC-a — caída antes de iniciar.** Punto: tras `prepare`, antes de `dispatch`. Al relanzar: `PROCEED`, el efecto se pide una vez y queda `SUCCEEDED` con recibo. Contador remoto = 1. Negativo: relanzar otra vez da `ALREADY_EXECUTED` y el contador sigue en 1.
- **AC-b — caída tras pedir el efecto y antes del recibo.** Punto: tras enviar la petición, antes de `complete`. Al relanzar no se llama al efecto:
  - (b1) si la sonda dice `PRESENT` con huella y actor coincidentes, queda `SUCCEEDED` con recibo y exit 3;
  - (b2) si la sonda dice `UNKNOWN`, queda `NEEDS_REVIEW` con exit 4.

  Contador remoto = 1 en ambos. Contra main falla: `f5-state.sh` devuelve 0 y `push-pr.sh` repite el merge.
- **AC-c — efecto confirmado y caída antes de cerrar.** Punto: tras la respuesta OK del remoto, antes de escribir `SUCCEEDED`. Al relanzar, la reconciliación cierra con recibo que contiene la evidencia remota (`merge_commit`). Contador = 1 y exactamente un `SUCCEEDED` y un recibo en la cadena.
- **AC-d — misma clave, otros argumentos.** `prepare` con la misma `(op, key)` y otro head SHA da `CONFLICT` (exit 5), sin llamada remota y con el ledger intacto. Límite: misma clave y mismos argumentos tras `SUCCEEDED` da exit 3 con el recibo original, byte a byte.
- **AC-e — respuesta remota ambigua.** Cada variante termina en `NEEDS_REVIEW` (exit 4), sin reintento automático, con contador = 1 y sin borrar la reserva:
  - timeout del stub tras aplicar el efecto;
  - 5xx;
  - salida no JSON;
  - `gh` ausente del `PATH`;
  - sonda que devuelve cadena vacía.

  Negativo: un rechazo explícito y definitivo del remoto (p. ej. «not mergeable», con estado `OPEN` leído correctamente) da `FAILED` y permite un `attempt` nuevo.
- **AC-f — concurrencia de dos workers.**
  - **Mismo ledger:** 20 rondas con dos procesos simultáneos sobre la misma clave. En cada ronda, exactamente uno obtiene `PROCEED` y el otro `IN_FLIGHT` o `ALREADY_EXECUTED`. Contador remoto = 20, uno por ronda.
  - **Dos rutas:** `push-pr.sh` y `merge-sprint.sh` sobre el mismo `pr.merge/N` ven la misma entrada del ledger.
  - **Dos instalaciones con ledgers distintos (multioperador):** la segunda encuentra el efecto ya presente en el remoto, hecho por otro actor, y termina en `NEEDS_REVIEW` con la evidencia del otro actor. Ni repite ni lo da por propio.

Contrato:

- **AC-g — sin repetición automática en estado ambiguo.** Para cada estado `DISPATCHED`, `NEEDS_REVIEW` e `IN_FLIGHT`, ningún consumidor (`push-pr.sh`, `merge-sprint.sh`, `f5-state.sh`) llega a la llamada de efecto. Lo prueba el contador del stub, no un grep.
- **AC-h — recibo verificable.** `verify-receipt` da `VERIFIED` con cadena íntegra y remoto coincidente. Da `FAIL` si se altera un byte de un recibo anterior o si cambia el `merge_commit` remoto, y `UNVERIFIED` (exit ≠ 0) sin sonda.
- **AC-i — resolución atribuida.** `resolve` manual con perfil humano registra actor y evidencia. Con `SAVIA_AUTONOMOUS_RUN=1` se rechaza con exit 2; con sonda definitiva, el agente sí puede cerrar.
- **AC-j — multioperador.**
  - Ninguna ruta absoluta ni identidad literal en el código. El ledger se resuelve por variable o `$HOME` y el actor sale del perfil activo.
  - Los tests corren con dos operadores sintéticos y dos `HOME` temporales; ninguno escribe en el `HOME` real.
  - Sin perfil activo, `prepare` de un efecto `non_idempotent` falla cerrado (exit 2).
- **AC-k — cierre honesto en coherence-gates.**
  - `coherence-gates.sh` ejecuta la suite de esta spec; si se rompe un test de la matriz, el gate marca BLOCK.
  - `effect-reservation.sh` no tiene consumidores, o está eliminado.
- **AC-l — fail-closed.** Si el ledger está corrupto, bloqueado más allá del timeout de `sqlite3`, en un disco sin escritura o con un esquema desconocido, el resultado es exit 2 y nunca `PROCEED`.

## Fuera de alcance

- Adoptar OpenRath (runtime, servidor, Postgres, scheduler) o cualquier dependencia nueva.
- Ledger compartido entre máquinas u operadores: cada instalación tiene el suyo y el remoto es la autoridad común (AC-f).
- Firma criptográfica de recibos: el encadenado por hash basta para v1, y la firma se valorará junto a los recibos de SE-488.
- Registrar efectos distintos de `pr.merge`. El contrato y el registro lo permiten; cada `op` nueva necesita su sonda y sus tests en una PR propia.
- Reconciliador periódico en segundo plano: la reconciliación ocurre al reintentar la misma clave o con `reconcile` explícito.

## Plan por slices

1. **S1** — `effect-ledger.py` y el registro de operaciones con stub; tests AC-a, AC-d, AC-f (mismo ledger), AC-h, AC-l.
2. **S2** — Sonda `pr.merge`; envoltorio `f5-state.sh`; `push-pr.sh` con write-ahead y nuevos mensajes; AC-b, AC-c, AC-e y AC-g para `push-pr`.
3. **S3** — `merge-sprint.sh`: ledger único, `reconcile` en lugar de `release` y motivo `needs_review`; AC-f (dos rutas, dos instalaciones) y AC-g para `merge-sprint`. Tests de `test-merge-sprint.bats` AC-25/26 en verde sin debilitar.
4. **S4** — `coherence-gates.sh` y deprecación de `effect-reservation.sh`; AC-k, AC-i, AC-j.

Cada slice es una PR Draft. S2 y S3 tocan el camino de merge, así que son tier 3 y exigen revisión humana explícita (SE-362).

## Riesgos

- **Sobrebloqueo:** más paradas en `NEEDS_REVIEW` cuando la red falla. Es el comportamiento buscado; el coste es una resolución manual por caso, medible en el ledger.
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
