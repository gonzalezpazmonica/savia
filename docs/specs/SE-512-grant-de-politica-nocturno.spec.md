---
status: PROPOSED
priority: P0
developer_type: agent-single
created: 2026-11-05
author: Savia
phase: B
risk: L4
related_specs: [SE-343, SE-362, SE-433, SE-445, SE-493, SE-498, SE-500, SE-501, SE-508]
origin: "Petición literal de la operadora (2026-11-05, 03:xx): «Pide un grant general, estás constantemente pidiendo permisos cuando estás en auto y en sprint nocturno. No me estás dejando dormir. El sprint nocturno ha de ser 100% autónomo por necesidad.»"
timeline:
  - from: "2026-11-05"
    learned: "2026-11-05"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-512 — Grant de política para el sprint nocturno

## Problema

El merge-sprint (SE-433) autoriza una **lista congelada**: el grant firma el digest exacto de un
manifiesto (PR, head, tier, ficheros, blobs y checks) y el ejecutor solo fusiona si ese digest no ha
cambiado. Es correcto para una sesión de tarde con la operadora delante. De noche no funciona: las PR
se corrigen, se vuelven a revisar y se registran, el plan cambia, y cada plan nuevo necesita otro grant,
o sea, otra pregunta a la operadora. Cada pregunta la despierta.

La operadora ha pedido un grant general y que el sprint nocturno sea 100 % autónomo. Esta spec propone
un **grant de política**: la operadora firma una vez, antes de dormir, una regla con alcance, ventana y
tope, y el ejecutor fusiona en serie cualquier PR que cumpla la regla **en el momento de fusionarla**.

### Dónde nace cada pregunta (verificado en origin/main afd6f49d1)

| # | Punto | Dónde | Por qué despierta |
|---|---|---|---|
| P1 | El grant ata el digest del manifiesto | `scripts/merge-sprint.sh:227-235` (`cmd_grant`: `sha < manifest == digest`), `:813-814` (`run` aborta si el manifiesto cambió tras el grant), `:585` (`sprint_gate`: grant de otro digest = anomalía) | Cualquier `plan` nuevo produce otro digest y exige otro grant. |
| P2 | El manifiesto se fija con el head revisado | `:180-199` (`plan` guarda el SHA revisado), `:604` (`merge_at`: `FAIL=head_movido`) | Un arreglo nocturno tras el APPROVE aparca la PR; volver a meterla exige `plan` y grant nuevos. |
| P3 | `grant` es «ask» en el frontend | `docs/rules/domain/autonomous-safety-merge-sprint.md:27-29` (pregunta con AskUserQuestion), `:124-125` (Ask: `grant`) | Cada grant es un aviso de permiso y una pregunta interactiva. |
| P4 | Un sprint parado no se reanuda | `:546-558` (`halt`, `stop_gate`), regla `autonomous-safety-merge-sprint.md:102` | Tras cualquier STOP hace falta un grant nuevo; correcto, pero hoy también tras un STOP que no es culpa de ninguna PR. |
| P5 | `main` solo se comprueba después de fusionar | `:591-595` (`main_ci_gate`, llamado desde `record_merge`); `sprint_gate` (`:583-589`) no mira `main` | Si `main` se pone en rojo por una causa externa, el ejecutor fusiona la primera PR sobre un `main` roto y para después. |
| P6 | Tier 1/2 exige una sola APPROVE | `:112` (`need = {"correctness"}`) | Suficiente con un humano que mira la lista; demasiado poco cuando nadie la mira (ver «Contrapesos»). |

### Fricciones de la noche del 2026-11-04 al 05

Datos que reporta la orquestadora de esa noche (el ledger es local y no se versiona, `autonomous-safety-merge-sprint.md:115-118`):

1. **Tres avisos de permiso y una pregunta interactiva** entre la medianoche y las 03:xx. Cada uno es un caso de P1+P3: plan nuevo, grant nuevo.
2. **#1478 aparcada por `head_movido`** (P2): las revisoras pidieron cambios (HOLD sobre la cabeza H0), el arreglo llegó después y la PR salió del sprint. Volver a meterla exigía otro grant. Es el caso «HOLD + arreglo + re-APPROVE» que R2.5 admite una vez por noche.
3. **`main` en rojo sin que ninguna fusión lo rompiera** (#1484): la CI solo descargaba 300 commits para `roadmap validate` y SE-402 salió de la ventana. Todas las PR salían en rojo. Es el caso de P5: el ejecutor no sabía que `main` estaba roto antes de fusionar.

## Qué decide esta spec

1. Un tipo de autorización nuevo, el **grant de política**, que convive con el grant de manifiesto de SE-433 y no lo sustituye.
2. Qué firma la operadora, cómo se verifica en cada fusión, cómo se revoca y cómo se audita por la mañana.
3. Un **modo nocturno** en el que ninguna acción puede disparar un aviso de permiso: lo que lo dispararía va a la lista de pendientes de la mañana.

No cambia nada de tier 3/4 (SE-362), del juez de cambios (SE-433 §2.7) ni del grant de un PR (SE-343).

## Qué cambia en la afirmación de SE-433

SE-433 afirma «lo autorizó un humano, de forma expresa, **sobre una lista concreta** y tras ver la
revisión de agentes» (`docs/specs/SE-433-merge-sprint.spec.md:53-57`), y señala como hueco que
«cualquier PR abierto con revisión entra, también los creados después de la autorización» (`:42-43`).

Un grant de política reabre ese hueco a propósito. La afirmación pasa a ser: **«lo autorizó un humano,
de forma expresa, sobre una regla concreta, acotada en alcance, tiempo y número; cada fusión cumplió la
regla en el momento de hacerse y quedó registrada»**. La operadora ya no ve la lista; ve la regla y, por
la mañana, el informe. Esto es más débil que SE-433 y se declara así. Los contrapesos de abajo existen
para compensar justo lo que se pierde: que ningún humano ve la lista antes de fusionar.

## Alternativas

| Opción | Qué es | Por qué no |
|---|---|---|
| A. Grant de manifiesto con TTL largo | Igual que hoy, 12 h | No resuelve nada: lo que caduca es el digest, no el tiempo. |
| B. Universo congelado al firmar | Solo las PR abiertas al firmar, con cabeza libre | Útil, pero deja fuera el trabajo que los workers abren de noche, que es la mayor parte. Se ofrece como opción de la política (`universe: frozen`), no como única. |
| C. Auto-merge de GitHub | `gh pr merge --auto` | Prohibido: GitHub fusiona aunque el grant se haya revocado (`autonomous-safety-merge-grant.md:51-56`). |
| **D. Grant de política** | Regla firmada, comprobada en cada fusión | **Elegida.** |

## Requisitos

### R1 — Qué se firma

La política es un JSON canónico (claves ordenadas, sin espacios) que genera
`merge-sprint.sh policy-plan` y que la operadora autoriza con su respuesta. Campos:

| Campo | Contenido | Límites |
|---|---|---|
| `kind` | `"policy"` | fijo |
| `id` | aleatorio, 16 hex | único |
| `not_before`, `not_after` | instantes en UTC (`…Z`); la hora local de la operadora se muestra en la pregunta y en el informe, pero no entra en el digest | límite único: `not_after − not_before ≤ 12 h` (12 h exactas se aceptan; 12 h y 1 s no). No hay ampliación a 24 h: la política es más débil que el manifiesto de SE-433 y su ventana es más corta. Por defecto, `not_before` es la hora de emisión y `not_after` es el primero de estos dos instantes: las 08:00 locales del día siguiente o `not_before + 12 h`. Así, firmar antes de las 20:00 recorta la ventana a 12 h, no la rechaza. Un `not_after` explícito que exceda 12 h se rechaza |
| `repos[]` | `{repo, base, include[], exclude[]}` | `include` son globs de rutas; una PR con un solo fichero fuera de `include` o dentro de `exclude` no entra (semántica exacta en R2.3). Exclusión forzosa, aunque la política diga otra cosa: (a) todo lo que `scripts/risk-tier.py` clasifica como gobernanza (`is_governance`, `:36-55`: `GOVERNANCE_EXACT`, `GOVERNANCE_PREFIXES` —incluye `.opencode/`, donde vive el plugin `savia-gates`, y `.github/workflows/`—, `.claude/settings*.json` y `docs/rules/domain/autonomous-safety*.md`); (b) el código de los gates que no es gobernanza hoy: `.claude/hooks/**`, `.claude/agents/**` (definiciones de las revisoras), `scripts/confidentiality-*`, `scripts/validate-ci*`, `scripts/f5-state.sh`, `scripts/merge-registry-resolve.py` y `scripts/sam.py`; (c) lo que crea esta spec: `.claude/hooks/night-mode-guard.sh` y cualquier fichero del guard nocturno. S3 añade (b) y (c) a `GOVERNANCE_EXACT`/`GOVERNANCE_PREFIXES` para que también den tier 4 |
| `tiers` | subconjunto no vacío de `{1,2}` | `3` o `4`, o la lista vacía, hacen inválida la política: no se emite |
| `max_merges` | entero ≥ 1 | techo duro 40 (`config/merge-sprint-policy.conf:5`): un valor mayor se rechaza, no se recorta |
| `max_parks_in_row` | entero ≥ 1 | techo duro 3, como SE-433 |
| `universe` | `"open"` o `"frozen"` | `frozen` lleva la lista no vacía de números de PR abiertas al firmar; `frozen` sin lista se rechaza |
| `reviewers` | ids admitidos como revisoras | al menos dos distintos; ninguno puede ser el id del orquestador (se rechaza al emitir). Que ninguno sea autor de la PR solo se puede comprobar al fusionar (R2.5) |
| `max_reviews_per_pr` | entero | 4 por defecto, máximo 4: dos rondas de dos revisoras (contrapeso C3) |
| `runner_blob`, `classifier_blob`, `f5_blob`, `resolver_blob` | blobs de `origin/main` al firmar | como el manifiesto de SE-433 (`merge-sprint.sh:207-217`) |
| `signers_blob` | blob de `config/operator-grant-signers` en `origin/main` al firmar, si existe | solo con firma ed25519 (AC-12b) |
| `required_checks` | por repo, de la protección viva | no vacío (`:212-213`) |

El **digest de la política** sustituye al digest del manifiesto. El ejecutor lo recalcula en cada paso
y para con anomalía si no coincide.

**Factor de autorización.** El mismo de SE-433 (D1): una pregunta interactiva de la sesión
orquestadora, generada por `policy-question` desde la política, con el texto completo de alcance,
ventana, tope y repos, y una opción de aprobación literal. Se responde una vez, antes de dormir. Si
existe `config/operator-grant-signers` en `origin/main`, la política puede ir además firmada con la
clave ed25519 de la operadora (SE-343, `autonomous-safety-merge-grant.md:61-71`); con firma, el grant
de política no necesita la sesión interactiva. La firma se verifica contra el fichero de firmantes leído
de `origin/main` (`git show origin/main:config/operator-grant-signers`), nunca del árbol de trabajo, y
su blob se congela en la política (`signers_blob`); si el blob de `origin/main` cambia durante la
ventana, STOP por anomalía. Sin respuesta literal o sin firma válida, no hay grant.

### R2 — Qué se comprueba en cada fusión

Por cada PR candidata, en este orden, y otra vez justo antes de `gh pr merge`:

1. **STOP y vigencia.** Ningún STOP (local, global de SE-498 o señal remota de R4). Política vigente:
   digest igual, sin revocar, `merged < max_merges`, y `now` dentro de `[not_before, not_after)`:
   - `now < not_before`: `run` sale **sin STOP** y sin fusionar, con código 7 (`antes_de_ventana`). La
     política sigue vigente y un `run` posterior dentro de la ventana la usa. Lanzarlo unos minutos
     antes no la mata.
   - `now ≥ not_after`: STOP normal `fuera_de_ventana`.
2. **`main` en verde antes de fusionar.** `main_ci` (`merge-sprint.sh:247-249`) sobre el `HEAD` actual
   de `main` devuelve `pass`. `main_ci` agrega los check-runs que **existen** en ese commit: un workflow
   con filtro de rutas que no corrió en ese commit no aparece y no cuenta. Un commit sin ningún
   check-run da `pending`, no `failure`. `fail` (`failure`, `timed_out` o `cancelled`) → STOP de la
   política (R3). `pending` → la pasada espera hasta 30 min (`main_pending_timeout`, configurable,
   máximo 60) sin fusionar nada; si sigue sin `pass`, STOP con motivo `main_pending`. Cierra P5.
3. **Alcance.** Repo y base de la política; `universe: frozen` → número en la lista. Ficheros: la
   lista sale de `git diff --name-status -M` entre la base de fusión y la cabeza, no del texto de la PR.
   - Un renombrado o una copia cuenta con **las dos** rutas, origen y destino; las dos han de pasar.
   - Un cambio cuyo modo, antes o después, sea `120000` (enlace simbólico) o `160000` (submódulo) deja
     la PR fuera, esté donde esté.
   - Los globs se evalúan en Python con `fnmatch.fnmatchcase` sobre la ruta relativa, sin expansión de
     shell. `*` no cruza `/`; `**` cruza directorios.
   - `include` distingue mayúsculas. `exclude` y la exclusión forzosa comparan en minúsculas, como
     `is_governance` (`risk-tier.py:48`): una variación de mayúsculas no saca una ruta de la exclusión.
4. **Tier.** `risk-tier.py` congelado (`classifier_blob`) sobre los ficheros de la cabeza actual; tier
   en `tiers`. Tier 3 o 4 → la PR va a pendientes de la mañana, nunca se fusiona con este grant.
5. **Doble APPROVE sobre la cabeza exacta.** Dos revisiones `APPROVE` registradas en `reviews.jsonl`
   con `sha` igual a la cabeza actual de la PR, con dos valores distintos del campo `reviewer` (ya se
   registra, `merge-sprint.sh:92`; hoy `reviews_ok`, `:97-113`, solo compara `role` y S2 cambia eso),
   distintos del autor y del orquestador, ambos en `reviewers`.

   **Regla de HOLD (C2).** Los HOLD se leen de **todo** `reviews.jsonl` para esa PR, en cualquier
   momento, también antes de `not_before`. La ventana no filtra los HOLD; solo acota el tope de C3.
   Definiciones:
   - Un **HOLD** es una fila `verdict=HOLD` con su `(sha, reviewer)`. Dos filas HOLD de la misma
     revisora sobre la misma cabeza son un solo HOLD.
   - El orden entre cabezas es el de la historia de la PR: Hj es posterior a Hk si Hk es ancestro de
     Hj (`git merge-base --is-ancestor`). Si dos cabezas con revisiones no son comparables (la rama se
     reescribió), la PR queda fuera hasta la mañana: fail-closed.
   - La **cabeza retenida** Hk es la cabeza más antigua de la PR que tiene al menos un HOLD.
     `retenedoras(Hk)` es el conjunto de revisoras que dieron HOLD sobre Hk, aunque otra diera APPROVE
     sobre esa misma cabeza.

   Decisión, sobre la cabeza actual Hc:
   - Sin ningún HOLD en el registro: basta la doble APPROVE sobre Hc.
   - Hay HOLD sobre Hc → fuera hasta la mañana.
   - Hay HOLD sobre alguna cabeza posterior a Hk (otra ronda de rechazo, de quien sea) → fuera hasta la
     mañana.
   - Si no: se fusiona solo si Hc es posterior a Hk y las APPROVE sobre Hc incluyen a **todas** las
     `retenedoras(Hk)`, con al menos dos revisoras distintas en total. Ejemplos:
     - HOLD de R1 sobre H0 → hacen falta R1 y otra sobre Hc.
     - HOLD de R1 y R2 sobre H0 → hacen falta R1 y R2 sobre Hc.
     - HOLD de R2 y APPROVE de R1 sobre H0 → hacen falta R2 y otra sobre Hc. La APPROVE de R1 sobre H0
       no cuenta para Hc.

   Cambiar de revisora no levanta un HOLD. Un HOLD de la tarde pesa igual que uno de la noche.

   Se admite la única equivalencia que no introduce código de la autora: la cabeza que produce el
   propio ejecutor al re-sincronizar con `main` y regenerar derivados (`head_equivalent`, `:375`). La
   equivalencia se comprueba por contenido, no por autoría declarada:
   - El diff entre `merge(H0, main)` y la cabeza nueva solo puede tocar registros y derivados (SAM, mapa
     de capacidades, firma de confidencialidad).
   - Cada derivado ha de ser byte a byte igual a su regeneración con el código congelado sobre ese árbol
     (`derived_equivalent`, `:404-412`). Cada registro ha de coincidir con la salida del resolutor
     congelado (`registry_equivalent`, `:393`).
   - Ningún derivado ni directorio que lo contenga puede ser un enlace simbólico (`no_write_links`,
     `:268`).
   - Cualquier otro fichero cambiado, o un derivado con contenido distinto del regenerado, exige
     revisiones nuevas sobre la cabeza nueva.

   Esto ya es así en `main` para el grant de manifiesto. La política lo reutiliza sin cambios.
6. **CI de la PR.** Checks obligatorios en verde sobre la cabeza S; `gh pr merge --squash
   --match-head-commit S` (`:617`).
7. **`main` en verde después de fusionar.** Se usa el sondeo existente `main_ci_gate` (`:591-595`)
   sobre el commit de fusión. Justo después de fusionar, `main` está en `pending`; eso no es un STOP.
   El gate sondea hasta `pass` o `fail`, y el número de sondeos se acota para no superar
   `main_pending_timeout`. `fail`, o `pending` al agotar el plazo, → STOP `main_<estado>`.
8. **Auditoría.** Entrada `MERGED` en el ledger encadenado con el id y el digest de la política (R5).

Una PR que no cumple 3-6 **no para la política**: se queda fuera en esa pasada y se vuelve a evaluar en
la siguiente. Esto es lo que resuelve #1478: HOLD sobre H0, la autora arregla, la revisora que dio el
HOLD y otra aprueban H1, y la PR entra en la pasada siguiente sin despertar a nadie. Si alguien vuelve
a dar HOLD sobre H1 o una cabeza posterior, la PR espera a la mañana.

**Códigos de salida de `run --policy`.** Los de SE-433 (`merge-sprint.sh:12-13`), más uno:

| Código | Cuándo |
|---|---|
| 0 | Terminado o parado con STOP normal (`fuera_de_ventana`, `max_merges`, `max_parks_in_row`, `main_*`, STOP manual, etiqueta `savia-stop`) |
| 5 | Anomalía (digest, blobs, firmantes, merge externo, base cambiada, checks reducidos, error de lectura) o política ya parada (`anomaly`, `stop_gate`, `:551-558`) |
| 6 | En pausa: una PR espera al juez de cambios (§2.7), como hoy |
| 7 | Antes de la ventana: no hace nada y no escribe STOP |
| 3/4 | Sin grant de política, cerrojo o datos manipulados, como hoy |

### R3 — Cuándo se para todo (fail-closed)

| Evento | Acción |
|---|---|
| `main_ci` en `fail` (`failure`, `timed_out`, `cancelled`) antes o después de una fusión, por la causa que sea, o en `pending` (también sin check-runs) más allá de `main_pending_timeout` | STOP de la política con motivo `main_<estado>`; no se reanuda sin firma nueva (ver Riesgos: una caída transitoria de la CI acaba la noche) |
| Política alterada, digest distinto, blobs del ejecutor, del clasificador o de los firmantes distintos | STOP (anomalía) |
| `now ≥ not_after`, `max_merges` alcanzado, `max_parks_in_row` seguidos | STOP normal |
| `now < not_before` | Nada: salida 7, sin STOP; la política sigue vigente |
| Merge externo, base cambiada, checks obligatorios reducidos | STOP (anomalía), como SE-433 (`autonomous-safety-merge-sprint.md:98`) |
| Error al leer GitHub, el registro o el ledger | STOP; nunca «se asume verde» |

Parar es seguro y no se revierte nada. Un STOP con motivo deja el fichero STOP con ese motivo
(`halt`, `:546-548`) y el motivo va al informe de la mañana.

### R4 — Revocación

- `merge-sprint.sh stop` y `revoke` (`:975-976`) valen igual para la política.
- El STOP global de SE-498, cuando exista, se consulta en el paso 1 de R2.
- **Señal remota sin terminal.** La operadora trabaja desde el móvil. Una etiqueta `savia-stop` en
  cualquier issue o PR del repo detiene la política en la siguiente comprobación. Solo cuenta la etiqueta:
  poner etiquetas exige permiso de triage o superior, así que un tercero anónimo no puede parar la
  noche (un issue con ese título, que cualquiera puede abrir en un repo público, no cuenta). Cualquiera
  con ese permiso puede ponerla, también un agente: no importa, porque solo resta. Quitarla no reanuda nada; solo una firma nueva reanuda.
- **Ampliar es firmar de nuevo.** No hay `extend`, `prorrogar` ni edición de la política. Un fichero de
  política cambiado da digest distinto y STOP. Una política nueva invalida la anterior (un solo grant
  de política vigente por repo).

### R5 — Auditoría de la mañana

`merge-sprint.sh report --policy <id>` genera un informe local, legible en el móvil, con:

- política firmada (texto completo y digest), hora de firma, factor (respuesta o firma ed25519);
- por cada fusión: PR, título, tier, SHA revisado y fusionado, ids y hashes de las dos revisiones, ids
  de la CI de la PR y de `main`, commit de fusión, hora;
- PR evaluadas y no fusionadas, con el motivo de la última pasada (fuera de alcance, tier 3, sin doble
  APPROVE, HOLD, cabeza nueva sin revisar, CI roja);
- motivo del STOP final, si lo hubo;
- `verify-ledger` íntegro o no;
- la lista de pendientes de la mañana (R6).

Nada de esto se versiona en el repo (`autonomous-safety-merge-sprint.md:115-118`).

### R6 — Modo nocturno: ningún aviso de permiso

Mientras hay un grant de política vigente, o `SAVIA_NIGHT_MODE=1`, queda **prohibida** toda acción que
pueda disparar un aviso de permiso o una pregunta. Lista cerrada en S3, como mínimo:

| Acción | Por qué dispara |
|---|---|
| Emitir cualquier grant (`merge-sprint.sh grant`, `operator-grant.sh grant`, `policy-grant`) | Regla «ask» (`autonomous-safety-merge-sprint.md:125`) |
| Editar settings de Claude Code u OpenCode (`.claude/settings*.json`, configuración de `.opencode/`) | Lo bloquea el clasificador; además es tier 4 |
| `AskUserQuestion` (en OpenCode, la herramienta de preguntas) | Bloquea al orquestador hasta que alguien conteste |
| `gh pr create` con una base distinta de `main` o hacia un repo sin regla de rama | Repos o bases sin ruleset piden permiso |
| `push-pr.sh --merge` y `gh pr merge` fuera del ejecutor | Merge one-shot con grant (SE-343) |

En su lugar, la acción se escribe en la **lista de pendientes de la mañana**,
`~/.savia/night/pendientes-<fecha>.md` (fuera del repo), con: hora, quién la pidió, qué, por qué y la
orden exacta lista para ejecutar o la pregunta con sus opciones y recomendación. El guard responde
`deny` (no `ask`, porque en una sesión sin nadie `ask` equivale a quedarse parada) con el mensaje «modo
nocturno: anotado en pendientes de la mañana» y la ruta.

Las tareas de tier 3 que R2.4 aparta van a la misma lista.

**Límite declarado del guard.** Para Bash, el guard compara el texto de la orden con una lista de
patrones. Una orden envuelta en un intérprete (`bash -c`, `sh -c`, `eval`, `python -c`), en variables
o en alias puede no casar. Para reducirlo, en modo nocturno el guard normaliza la orden: quita
comillas y une los argumentos de `bash|sh|zsh -c` y `eval`. Después **niega por defecto** cualquier
Bash cuyo texto normalizado contenga `gh pr merge`, `gh pr create`, `merge-sprint.sh grant`,
`operator-grant.sh grant` o `policy-grant`. Las órdenes internas del ejecutor no pasan por el hook:
`merge-sprint.sh run --policy` no contiene esos textos y no se niega.
Aun así, no promete «ningún aviso» frente a una orden ofuscada a propósito. Lo que impide un merge
o un grant no autorizado siguen siendo los permisos `ask` del frontend, que el guard no sustituye.
Si una orden ofuscada se le escapa al guard, el coste es un aviso que despierta a la operadora, no un
merge sin grant.

## Contrapesos (lo que compensa que nadie mire la lista)

- **C1. Dos revisoras, no una.** P6: una APPROVE basta cuando la operadora ve la lista. Sin lista, cada
  fusión necesita dos revisoras independientes entre sí y de la autora.
- **C2. Un HOLD solo lo levanta quien lo dio, y solo una ronda.** Un HOLD se levanta con doble APPROVE
  sobre una cabeza posterior que incluya a todas las revisoras que dieron HOLD sobre la cabeza
  retenida (R2.5). Un HOLD sobre cualquier cabeza posterior saca la PR hasta la mañana. Los HOLD se leen
  de todo el registro, no solo de la ventana: un HOLD de antes de firmar no se borra al firmar. Sin esto, el orquestador podría cambiar de revisora o arreglar
  y relanzar hasta obtener dos APPROVE sobre un cambio que alguien rechazó (amenaza A3, `SE-433:72`).
- **C3. Tope de revisiones por PR.** Más de `max_reviews_per_pr` (4: dos rondas de dos) revisiones
  registradas en la ventana sacan la PR. Cuenta cada fila `(sha, reviewer)` distinta, sea APPROVE o
  HOLD. Limita el «relanzar revisoras hasta que aprueben». HOLD+HOLD sobre H0 y APPROVE+APPROVE sobre
  H1 suman 4 y caben. Una tercera opinión sobre H1 suma 5 y saca la PR: es justo el relanzamiento que
  C3 limita, aunque nadie lo haga de mala fe. La PR no se pierde, va a la mañana.
- **C4. Sin tier 3.** Tier 3 exige que la operadora vea la PR por número (`autonomous-safety-merge-sprint.md:106-108`). Eso no cabe en una regla.
- **C5. Rutas, no repos enteros.** El alcance se firma por globs de rutas; las de gobernanza siempre fuera.

Límite declarado: las identidades de las revisoras siguen siendo autodeclaradas
(`autonomous-safety-merge-sprint.md:133-136`). C1-C3 hacen más caro el fraude de veredictos, no lo
impiden. Un agente con shell del mismo usuario puede saltarse el ejecutor (A4): lo contienen los
permisos del frontend.

## Savia Space y Savia Labs

Encajan como entradas de `repos[]` solo si cada repo cumple lo mismo que Savia: protección de rama con
checks obligatorios (sin ellos, `check_required` falla cerrado, `:577-581`), un clasificador de tier
propio congelado en la política y registro de revisiones del ejecutor. Por defecto quedan fuera.

- **Savia Space.** Las PR de sincronización (cuyo árbol debe coincidir con un commit de `main` de Savia
  ya fusionado y en verde) son tier 1 por construcción y son el mejor candidato. Se añaden en S5.
- **Savia Labs.** Investigación en Markdown. Encaja con `include` acotado a sus rutas de informes y
  tier 1. Sin clasificador propio, excluida.

## Criterios de aceptación

Cada AC tiene test BATS con `gh` simulado y un caso que falla con el código anterior.

- **AC-1** `policy-plan` rechaza (exit ≠ 0, no escribe la política) una política:
  - con `tiers` vacío o que contenga 3 o 4;
  - con `not_after` explícito que dé una ventana > 12 h (caso límite: 12 h exactas se aceptan, 12 h y
    1 s se rechazan, 18 h se rechazan);
  - sin `max_merges`, con `max_merges` > 40 o < 1;
  - con `max_parks_in_row` > 3;
  - con `max_reviews_per_pr` > 4;
  - con menos de dos `reviewers` distintos, o con el id del orquestador entre ellos;
  - con `universe: frozen` sin lista;
  - con `required_checks` vacío en algún repo.

  Positivo: sin `not_after`, emitida a las 22:00 locales, la ventana acaba a las 08:00. Emitida a las
  18:00, acaba a las 06:00 (12 h). Las dos se aceptan.
- **AC-2** Con política vigente, una PR tier 2 con dos APPROVE sobre su cabeza, CI verde y `main` verde
  se fusiona y deja `MERGED` en el ledger con `policy_id` y digest.
- **AC-3 (negativo, tier 3)** Una PR que cumple todo salvo que `risk-tier.py` da tier 3 no se fusiona
  con el grant de política y queda con motivo `tier_3` en el estado de la pasada (S2). Que además
  aparezca en la lista de pendientes de la mañana se prueba en S3 (AC-3b).
- **AC-4 (negativo, cabeza cambiada)** Una PR sin HOLD previo, con dos APPROVE sobre H0 y un commit de
  la autora que lleva la cabeza a H1, no se fusiona; con dos APPROVE nuevas sobre H1, se fusiona en la
  pasada siguiente sin grant nuevo.
- **AC-4b (caso #1478)** HOLD de la revisora R1 sobre H0; la autora lleva la cabeza a H1; APPROVE de R1
  y de R2 sobre H1 → se fusiona en la pasada siguiente sin grant nuevo. Negativos: APPROVE de R2 y R3
  sobre H1 (sin R1) → no se fusiona; un HOLD de cualquiera sobre H1 o H2 → no se fusiona en toda la
  ventana.
- **AC-4d (negativo, HOLD de antes de la ventana)** HOLD de R1 sobre H0 registrado antes de
  `not_before`; ya en la ventana, APPROVE de R2 y R3 sobre H0, o sobre H1 → no se fusiona. Con APPROVE
  de R1 y R2 sobre H1, sí. Falla con una implementación que filtre los HOLD por la ventana.
- **AC-4e (definición de HOLD)** Cuatro casos con resultado fijo:
  - HOLD de R1 y R2 sobre H0, APPROVE de R1 y R2 sobre H1 → se fusiona.
  - HOLD de R1 y R2 sobre H0, APPROVE de R1 y R3 sobre H1 → no (falta R2).
  - HOLD de R2 y APPROVE de R1 sobre H0, después APPROVE de R1 y R2 sobre H1 → se fusiona.
  - El caso anterior más una quinta revisión sobre H1 en la ventana → no (C3).

  El tercer caso falla con una implementación que exija todas las revisoras de H0, no solo las que
  dieron HOLD.
- **AC-4c (negativo, re-sync disfrazado)** Una cabeza nueva que mezcla `main` y regenera derivados no
  hereda las APPROVE de la cabeza anterior si además:
  - cambia un fichero no derivado; o
  - deja un derivado con un contenido distinto del que regenera el código congelado (por ejemplo, una
    `.confidentiality-signature` editada a mano).

  La misma operación, con los derivados idénticos a su regeneración, sí las hereda.
- **AC-5 (negativo, ventana)** Con `now ≥ not_after` no se fusiona nada y `run` sale con código 0 y STOP
  `fuera_de_ventana`; caso límite: `now == not_after` no fusiona. Con `now < not_before`, `run` sale con
  código 7, no fusiona y **no** escribe STOP. Un `run` posterior dentro de la ventana fusiona con la
  misma política.
- **AC-6 (negativo, `main` en rojo antes)** Con `main` en `failure` antes de la primera fusión, no se
  fusiona ninguna PR y la política queda parada con motivo `main_fail`. Falla con el código actual,
  que solo comprueba `main` después (`:591-595`). Con `main` en `pending` que pasa a `success` antes de
  `main_pending_timeout`, se fusiona; con `pending` más allá del plazo, STOP `main_pending` sin fusión.
  Con un `HEAD` de `main` cuyos check-runs existentes están todos en `success` y en el que falta un
  workflow con filtro de rutas que no corrió, se fusiona.
- **AC-7 (negativo, regresión tras fusión)** Si `main` no queda en verde tras una fusión (`fail`, o
  `pending` al agotar `main_pending_timeout`), se para todo, no se revierte y las PR restantes no se
  tocan. Positivo: `pending` en el primer sondeo y `pass` en el segundo no para nada.
- **AC-8 (negativo, ampliar)** Cambiar cualquier campo del fichero de política (ventana, tope, repos,
  rutas, tiers) hace que `policy-verify` (S1) dé anomalía por digest. No existe subcomando que lo
  amplíe. Sin respuesta o firma nueva no hay otro grant. Que `run --policy` pare con exit 5 por ese
  motivo se prueba en S2 (AC-8b).
- **AC-9 (negativo, una revisora)** Dos APPROVE con el mismo `reviewer` (aunque tengan `role` distinto),
  o una de ellas del autor o del orquestador, o de un `reviewer` fuera de `reviewers`, no cuentan como
  doble APPROVE. Falla con el `reviews_ok` actual, que solo compara `role`.
- **AC-10 (negativo, HOLD sobre la cabeza actual)** Una PR con dos APPROVE y un HOLD sobre la misma
  cabeza no se fusiona; tampoco si supera `max_reviews_per_pr` revisiones en la ventana.
- **AC-11 (negativo, alcance)** Una PR con un fichero fuera de `include`, o en una ruta de exclusión
  forzosa ya existente (`.claude/settings.json`, `.opencode/`, `.github/workflows/`, `.claude/hooks/`,
  `scripts/confidentiality-scan.sh`), no se fusiona aunque la política la incluya en `include`.
- **AC-11b (S3, rutas nuevas)** `risk-tier.py` da tier 4 para `.claude/hooks/night-mode-guard.sh`, para
  `.claude/hooks/<otro>.sh`, `.claude/agents/<revisora>.md`, `scripts/confidentiality-scan.sh` y
  `scripts/validate-ci-local.sh`. Falla con el `risk-tier.py` actual, que da tier 1 o 2 a varias de
  ellas.
- **AC-11c (negativo, semántica de rutas)** No se fusiona una PR que:
  - renombra un fichero desde una ruta excluida a una ruta de `include`;
  - añade un enlace simbólico (modo `120000`) dentro de `include`;
  - añade un submódulo (modo `160000`);
  - toca `.Claude/Settings.json` (variación de mayúsculas de una ruta forzosa).

  Positivo: un renombrado entre dos rutas de `include` se fusiona.
- **AC-12** La etiqueta `savia-stop` en cualquier issue o PR del repo detiene la política antes de la
  fusión siguiente (exit 0, STOP `savia_stop`); quitarla no la reanuda. Negativo: un issue abierto
  titulado `savia-stop` sin la etiqueta no para nada.
- **AC-12b (firmantes congelados)** Una política firmada con una clave que solo está en el
  `config/operator-grant-signers` del árbol de trabajo, y no en el de `origin/main`, no da grant; si el
  blob de firmantes de `origin/main` cambia durante la ventana, STOP por anomalía.
- **AC-13 (modo nocturno)** Con `SAVIA_NIGHT_MODE=1`, el guard niega `AskUserQuestion`, `merge-sprint.sh
  grant`, la edición de `.claude/settings.json` y `gh pr create --base` distinta de `main`, y escribe
  una entrada por cada una en la lista de pendientes; sin modo nocturno, no interviene. Entrada por
  stdin (JSON), igual en Claude Code y en OpenCode. Negativo de evasión: `bash -c "gh pr merge 12"` y
  `eval 'gh pr create --base dev'` también se niegan en modo nocturno.
- **AC-3b (S3)** La PR de AC-3 aparece en la lista de pendientes de la mañana con motivo `tier_3`.
- **AC-14** `report --policy` lista fusiones, no fusionadas con motivo, STOP y pendientes, y falla si
  `verify-ledger` falla.
- **AC-15** Error de lectura de GitHub en cualquier paso de R2 → STOP, nunca fusión.

## Métricas

| Métrica | Antes (noche 04-05) | Objetivo |
|---|---|---|
| Avisos de permiso y preguntas a la operadora entre la firma y el fin de la ventana | 4 (3 + 1) | 0 |
| PR aparcadas solo por cabeza nueva con revisión nueva disponible | ≥ 1 (#1478) | 0 |
| Fusiones sobre `main` en rojo | posible (P5) | 0 |

## Fuera de alcance

- Tier 3 y 4 en modo nocturno, en cualquier forma.
- Cambiar SE-362, el juez de SE-433 o el grant de un PR de SE-343.
- Autenticidad criptográfica obligatoria de la respuesta: sigue dependiendo del harness, como SE-433, salvo con firma ed25519.
- Implementar el STOP global (SE-498); aquí solo se consulta si existe.
- Cambiar los permisos del frontend: los cambia la operadora en sus settings.

## Dependencias

- SE-433 v2 y SE-500 S2 en `main` (ejecutor, re-sync, código congelado).
- La enmienda de `docs/rules/domain/autonomous-safety-merge-sprint.md` y `autonomous-safety.md` es tier 4: la fusiona la operadora.
- SE-498 (opcional para R4).

## Plan por slices

| Slice | Contenido | AC |
|---|---|---|
| S1 | `policy-plan`, `policy-question`, `policy-grant`, `policy-verify` (digest, ventana y firmantes de `origin/main`); sin `run` ni fusiones | AC-1, AC-8, AC-12b |
| S2 | `run --policy`: bucle por pasadas, ventana y código 7, gate de `main` previo (con espera de `pending`), doble APPROVE por `reviewer` distinto (`reviews_ok` pasa a contar `reviewer`, no solo `role`; el esquema de `reviews.jsonl` no cambia porque ya guarda `reviewer`), regla de HOLD sobre todo el registro, equivalencia por contenido, tope de revisiones, alcance por rutas con exclusión forzosa, STOP | AC-2, AC-3, AC-4, AC-4b, AC-4c, AC-4d, AC-4e, AC-5, AC-6, AC-7, AC-8b, AC-9, AC-10, AC-11, AC-11c, AC-15 |
| S3 | Guard de modo nocturno (Claude Code + plugin `savia-gates`) con normalización de intérpretes, rutas de exclusión forzosa (b) y (c) en `risk-tier.py`, lista de pendientes; señal `savia-stop` solo por etiqueta | AC-3b, AC-11b, AC-12, AC-13 |
| S4 | `report --policy` y enmienda de las reglas `autonomous-safety*` | AC-14 |
| S5 | Savia Space y Savia Labs como repos de la política | AC-2 y AC-11 por repo |

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La regla deja pasar una PR que la operadora no habría aprobado | C1-C5; tope de fusiones; informe de la mañana; revert manual posible |
| Bucle de revisión hasta obtener APPROVE | C2 y C3; el registro encadenado muestra cada intento |
| `main` roto por causa externa para el sprint toda la noche | Es lo correcto: fusionar sobre `main` roto es peor. El motivo llega a pendientes con la causa |
| Una caída transitoria de la CI de `main` (infra de GitHub, runner caído) acaba la noche aunque no sea culpa de ninguna PR (la queja de P4) | Decisión de producto aceptada: `pending` se espera hasta `main_pending_timeout`; `failure` no se reintenta, porque desde el ejecutor no se distingue con fiabilidad un fallo de infra de uno real, y equivocarse fusiona sobre `main` roto. El coste es una noche sin fusiones, no una fusión mala |
| El guard nocturno bloquea algo legítimo | Va a pendientes con la orden lista; nada se pierde |
| Divergencia entre el guard bash y el plugin TS | Mismos fixtures en ambos tests (AC-13) |

## Rollback

Borrar el grant de política (`revoke`) devuelve al grant de manifiesto de SE-433, que no cambia. El
guard nocturno se desactiva quitando `SAVIA_NIGHT_MODE`; sin grant de política vigente no actúa.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Ejecutor (`merge-sprint.sh policy-*`, `run --policy`, `report --policy`) | bash, sin binding | igual, bash |
| Guard de modo nocturno | `.claude/hooks/night-mode-guard.sh` en PreToolUse (`AskUserQuestion`, `Bash`, `Edit`, `Write`) | función del plugin `savia-gates` en `tool.execute.before` (herramienta de preguntas, bash, edición) |
| Lista de pendientes | `~/.savia/night/pendientes-<fecha>.md` | la misma ruta |
| Permiso del frontend | `ask` sobre `policy-grant` en los settings de la operadora | permiso `ask` equivalente en su configuración local |

### Verification protocol

- [ ] El ejecutor pasa los mismos BATS en ambos motores (no depende del frontend).
- [ ] El guard tiene tests con el mismo JSON de entrada para el hook bash y para el plugin TS.
- [ ] El plugin `savia-gates` registra el guard antes que cualquier sandbox que pueda dejar pasar la orden.

### Portability classification

- [x] **DUAL_BINDING**: el ejecutor es PURE_BASH; el guard nocturno nace en Claude Code y en OpenCode en S3.

## Aprobación

Pendiente de la operadora. Esta spec no cambia ningún `status` ni ninguna regla hasta su aprobación.
