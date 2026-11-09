---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-11-01
author: Savia
phase: D
risk: L3
depends_on: [SE-213, SCL-001, SE-364]
related_specs: [SE-162, SE-213, SE-364, SE-486, SE-488, SCL-001, SCL-006, SE-489]
origin: "Investigación externa de repositorios de IA difundidos públicamente (2026-11-01), líneas SAVIA-RESEARCH-04 y 05 (validaciones V5 y V6). Estudio solo de lectura de MEX, Graphify y Agentic Context Engine, contrastado con main 6b0658b28."
resource: https://github.com/mex-memory/mex
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-497 — Conocimiento vinculado a código con deriva, y aprendizaje sin autoautoridad

## Problema

Dos huecos distintos con una raíz común: Savia guarda conocimiento sobre sí misma y sobre el código, pero no sabe cuándo ese conocimiento deja de corresponder a lo que describe, y deja que una métrica favorable haga de autoridad.

**Parte 1 — deriva.** Las notas técnicas (reglas de `docs/rules/domain/`, SKILL.md, notas de la cúpula savia-docs) describen funciones y scripts concretos en prosa. Si el código cambia, la nota sigue sirviéndose igual. Punto de partida verificado en main:

- El grafo de conocimiento (`scripts/knowledge-graph.py`, SE-162) tiene entidades de tipo `spec`, `rule`, `skill`, `project`… pero **ningún nodo de símbolo de código**. SE-213 añadió `confidence` y `provenance` a las entidades, no a las aristas, y no hay hash de lo que se describe.
- codebase-memory y codegraph indexan símbolos, pero son herramientas opcionales por instalación y no enlazan con notas.
- SE-486 (PROPOSED) deriva `UNREVIEWED` cuando **se edita la nota**; no cuando cambia el código que la nota describe.

**Parte 2 — aprendizaje.** El bucle SCL-001 ya separa propuesta (`INFERRED`, sombra) de activación (`human_authored`), y eso se conserva. Pero hay cinco huecos verificados:

1. `scripts/learning-lifecycle.sh` solo aplica el gate de regresión canary→active **si se pasan las dos métricas**; si se omiten, el gate no corre (fail-open). Las métricas, además, son números que declara quien llama, sin recibo.
2. `--human-trailer` acepta cualquier cadena no vacía: un agente puede escribirla.
3. `scripts/learning-rollback.sh` solo restaura cambios **sin commitear** (`git checkout -- <fichero>`); una activación ya commiteada da NOOP. La reversión no está garantizada.
4. `scripts/learning-autonomy.sh` (SCL-006) concede L2 con `p_consistent ≥ 0,70` **sin aprobación humana**; `/playbook-evolve --auto` aplica cambios de riesgo bajo sin confirmación; `instincts-protocol.md` solo exige confirmación por debajo del 50 % de confianza; `skill-lifecycle.md` llama «aprobado para adopción» a un consenso de jueces ≥ 0,75. En los cuatro casos una cifra hace de autoridad.
5. Las propuestas (LP) no tienen ámbito, caducidad, test de no regresión ni nivel de confianza.

## Qué decide esta spec

- **Una edición no es una falsedad.** La deriva es una señal de revisión: marca, no oculta ni borra. Solo una persona vuelve a dar por buena una nota (patrón de MEX).
- **Cada vínculo dice cómo se obtuvo**: `EXTRACTED` (leído del fuente), `INFERRED` (resuelto por heurística o modelo), `AMBIGUOUS` (varios candidatos o ninguno único; nunca se elige uno al azar). La confianza de un camino es la de su salto más débil (patrón de Graphify).
- **El aprendizaje produce propuestas, nunca autoridad.** Una mejora estadística puede **bajar** un techo o **bloquear** una promoción; nunca **conceder** nada. Promover exige validación independiente **y** revisión humana verificable.
- **Conocimiento, capacidad y autoridad son tres cosas.** Una LP puede cambiar texto de criterio o lección (conocimiento) o una skill o script (capacidad). Nunca puede tocar artefactos de autoridad.
- **Se reutiliza lo existente**: SCL-001 (ciclo de vida y cúpula SaviaLearning), SE-364 (corpus de evidencia), SE-213 (confianza en el grafo), SE-486 (admisión en Vaults), SE-488 (aprobación por fusión de PR). No se crea un segundo sistema de memoria ni de lecciones.

## Parte 1 — Conocimiento vinculado a código con deriva

### R1 — `symbol_ref` en el frontmatter de las notas técnicas

```yaml
code_refs:
  - symbol_ref: "scripts/learning-lifecycle.sh::main"   # ruta relativa al repo :: nombre cualificado
    body_hash: "sha256:…"        # hash normalizado del cuerpo (R2)
    identity: "sha256:…"         # firma: tipo + nombre + parámetros
    provenance: EXTRACTED        # EXTRACTED | INFERRED | AMBIGUOUS
    baseline_reviewed_by: "<id de perfil>"   # vacío si nadie lo ha revisado
    baseline_reviewed_at: "2026-11-01"
```

- Rutas siempre relativas al repositorio; nunca absolutas ni con usuario.
- Una nota sin `code_refs` no cambia de comportamiento.
- La prosa sigue siendo la fuente canónica; el bloque solo ancla.

### R2 — Resolutor determinista con hash normalizado

`scripts/code-refs.py` (stdlib de Python, sin dependencias nuevas):

| Lenguaje | Extracción | Normalización del hash |
|---|---|---|
| Python | módulo `ast` | `ast.dump` del nodo sin docstring ni posiciones: comentarios y formato no cambian el hash |
| Bash | funciones `name()`/`function name`; `::main` = fichero completo | sin líneas de comentario ni espacios sobrantes |
| Markdown | encabezado (`ruta.md::Título de sección`) | texto de la sección sin espacios sobrantes |
| TypeScript y otros | adaptador opcional sobre codebase-memory o codegraph si están instalados | el que dé el adaptador, versionado |

Sin resolutor para un lenguaje, o sin la herramienta opcional, el vínculo queda `UNVERIFIED`. Nunca `FRESH`.

### R3 — Estados de deriva

`code-refs.py check [--json] [rutas…]` asigna a cada vínculo un estado. Las filas se evalúan **en este orden** y gana la primera que se cumple:

| Orden | Estado | Condición |
|---|---|---|
| 1 | `UNVERIFIED` | no hay resolutor para el lenguaje, o el vínculo no tiene `baseline_reviewed_by`. Gana a cualquier comparación de hash: sin línea base revisada no hay nada contra lo que estar `FRESH` |
| 2 | `FRESH` | el nombre cualificado existe en la ruta con el mismo `identity` y el mismo `body_hash` |
| 3 | `CHANGED` | el nombre cualificado existe en la ruta, pero cambia el `identity` (por ejemplo, otros parámetros), el `body_hash`, o ambos |
| 4 | `MOVED` | el nombre ya no está en la ruta y aparece **un único** símbolo con el mismo `identity` y `body_hash` en otra ruta |
| 5 | `AMBIGUOUS` | el nombre ya no está en la ruta y aparecen **dos o más** candidatos con el mismo `identity` y `body_hash`; se listan y no se elige |
| 6 | `MISSING` | el nombre no está en la ruta y no hay ningún candidato en otra |

Consecuencias explícitas:

- **Copiar** el símbolo a otro fichero dejando el original en su ruta da `FRESH`: el vínculo sigue apuntando a un símbolo intacto. «Duplicado» en el banco de R6 significa **mover el original a dos sitios** (desaparece de la ruta y aparece en dos), y eso da `AMBIGUOUS`.
- Renombrar es `MISSING` para el vínculo viejo (el nombre cualificado es parte de la referencia), salvo que el cuerpo y la firma coincidan con un único símbolo de otra ruta.
- `AMBIGUOUS` significa lo mismo en el estado de deriva y en `provenance` (R1): hay varios candidatos y no se elige ninguno. Se mantiene un solo nombre porque es un solo concepto; el campo (`drift` o `provenance`) dice a qué se aplica.

El estado de la nota es el peor de sus vínculos, por este orden: `MISSING`, `AMBIGUOUS`, `CHANGED`, `MOVED`, `UNVERIFIED`, `FRESH`. El resultado es determinista: con el mismo árbol, la misma salida. Si el resolutor falla, el código de salida es distinto de 0 y nada pasa a `FRESH`.

### R4 — Invalidación y revisión humana

- **Invalidar es marcar.** Una nota que no está en `FRESH` se sigue sirviendo con la etiqueta `drift: <estado>` en el grafo, en `vault_rag` (traza y metadatos del hit) y en la salida de `code-refs.py`. No se oculta: solo se descarta si su nivel de admisión (SE-486) lo pide por otra razón.
- **Re-anclar** (`code-refs.py reground <nota> <ref>`): previsualiza por defecto el diff entre el cuerpo anclado y el actual. Con `--apply` escribe el nuevo `body_hash`/`identity` y `baseline_reviewed_by`, sacado del perfil activo.
  - **Se niega** (exit 4) en una rama `agent/*` o con `SAVIA_AUTONOMOUS_RUN=1`. En ese contexto solo puede emitir una propuesta de re-anclaje en `output/code-refs/proposals/`.
  - **La garantía real** es que el commit de re-anclaje entra en main por una PR revisada por una persona (Rule 8). La CLI protege la integridad del cambio; no prueba que lo hiciera una persona (MEX documenta el mismo límite).
- Una ejecución correcta de un agente **nunca** acepta una línea base nueva por sí sola.
- `pr-plan` gana un aviso: si la PR cambia un símbolo anclado y deja su nota en `CHANGED`/`MISSING`, avisa con la lista de notas. Es aviso, no bloqueo, hasta que la operadora decida promoverlo con datos de S3.

### R5 — Grafo de conocimiento

- `knowledge-graph.py build` ingiere `code_refs`: entidad `code_symbol` y relación `documents` (nota → símbolo) con `provenance` y `drift`.
- Aristas con confianza: SE-213 se extiende a `relations` con una migración idempotente, igual que hizo con `entities`. `EXTRACTED` = 1,0, `INFERRED` = 0,6, `AMBIGUOUS` = 0,0 por defecto.
- `impact` y `query` devuelven la confianza del camino como **mínimo** de sus saltos y marcan los caminos que atraviesan una nota con deriva.

### R6 — Población inicial y medición antes/después

- `code-refs.py suggest <nota>` propone vínculos desde la prosa (rutas y nombres citados). Lo que encuentra con un candidato único y cita literal de la ruta es `EXTRACTED`; lo resuelto solo por nombre es `INFERRED`; lo que tiene varios candidatos es `AMBIGUOUS`. **Solo propone**: escribe el bloque una persona o una PR revisada.
- **Banco de deriva** (`tests/fixtures/code-refs/`): repositorio sintético con 4 lenguajes y mutaciones etiquetadas. Hay ≥ 20 casos de cada tipo: solo comentario o formato, cambio de cuerpo, cambio de firma, renombrado, traslado, borrado, copia (original intacto) y duplicado (original movido a dos sitios), con los estados esperados de R3. Se mide la precisión y la exhaustividad de cada estado.
- **Banco de respuesta** (`projects/savia-vaults/eval/code-refs-bench/`): ≥ 30 preguntas técnicas sobre el propio repositorio, con respuesta de referencia y las notas que la sostienen. ≥ 10 se plantean tras una mutación real del símbolo. Se mide la exactitud de la respuesta **antes** (notas sin etiqueta de deriva) y **después** (con etiqueta), con el mismo modelo, prompt y semilla, y comparación pareada (`evals-paired-delta.py`). El informe incluye intervalos, no solo porcentajes.
- Ningún umbral se fija en esta spec. Activar el aviso de R4 como bloqueo, o la etiqueta en `vault_rag` por defecto, es decisión de la operadora con estos datos, en una PR aparte.

## Parte 2 — Aprendizaje sin autoautoridad

### R7 — Esquema de propuesta ampliado (LP)

`scripts/learning-proposal.sh` añade al frontmatter, sin romper las LP existentes:

```yaml
scope: { paths: [...], skills: [...], domains: [...] }   # dónde aplica; vacío = rechazo
evidence: [ { source: "se364:<id>|trace:<hash>|commit:<sha>", hash: "sha256:…" } ]   # ≥ 1 fallo verificado
regression_test: "tests/…bats::<nombre>" | "eval:<case_key>"   # falla antes del cambio y pasa después (tipo según target, ver abajo)
expires_at: "2027-02-01"                   # por defecto +90 días; máximo 365
confidence: low|medium|high                # declarada
confidence_basis: "n_evidencias=3, independientes=2"   # cómo se llegó
```

- Las LP anteriores a esta spec siguen legibles. No pueden pasar a `canary` hasta completar los campos.
- `learning-lifecycle.sh --to canary` **rechaza** (exit 6) si falta algún campo, si `scope` está vacío o si `regression_test` no existe.
- **Tipo de `regression_test` según `target`** (R8):
  - `skill` y `script`: un test BATS o pytest (`tests/…::<nombre>`) que ejercita el comportamiento.
  - `criterio` y `lesson` (texto): un caso de evaluación fijado (`eval:<case_key>`, R9) que reproduce el fallo de la evidencia, ejecutado con modelo, prompt y semilla fijos, con y sin la LP inyectada. Un test que solo comprueba que el texto existe en el fichero **no vale**: `learning-validate.sh` lo marca `INVALID_TEST` (no ejercita el comportamiento).

**Tabla de códigos de salida de `learning-lifecycle.sh`** (se documenta completa en la cabecera del script):

| Código | Significado | Estado |
|---|---|---|
| 0 | transición aplicada | existe |
| 1 | transición no válida | existe |
| 2 | uso | existe |
| 3 | fichero no encontrado | existe |
| 4 | falta autoría humana (`--human-trailer` ausente o con formato inválido, R10) | existe; R10 endurece el formato |
| 5 | regresión de métrica canary | hoy está documentado pero no se usa (la regresión revierte a `proposed` y sale 0). Pasa a ser real: regresión según un recibo **ya validado** → revierte a `proposed` y sale 5 (el recibo se valida antes, R9) |
| 6 | LP incompleta para `canary` (R7) | nuevo |
| 8 | recibo de validación ausente, inválido o que no corresponde (R9) | nuevo |

El código 7 (ruta de autoridad, R8) lo devuelve `learning-proposal.sh` al capturar, no `learning-lifecycle.sh`; no se reutiliza ningún código para dos causas.

### R8 — Separación de conocimiento, capacidad y autoridad

- `target` de una LP ∈ {`criterio`, `lesson`, `skill`, `script`}.
- **Lista de rutas de autoridad** (`docs/rules/domain/learning-authority-paths.txt`): reglas de autonomía y merge, `.claude/settings.json`, registro de hooks, perfiles, grants y aprobaciones, la definición de niveles L0–L3 (`loop-phasing.md`, SCL-006), esta propia lista y **los gates del propio aprendizaje**: `learning-autonomy.sh`, `learning-lifecycle.sh`, `learning-validate.sh`, `learning-rollback.sh`, `learning-proposal.sh`, `learning-recall.sh`, `learning-recall-hook.sh`, `code-refs.py` y el directorio de recibos `output/learning-loop/receipts/`. Una LP no puede proponer debilitar el gate que la valida.
- Una LP cuyo `scope.paths` o diff toque esas rutas se rechaza **al capturarse** (exit 7), con mensaje que remite a una spec. Cambiar autoridad es trabajo de spec, no de aprendizaje.
- **Normalización antes de comparar**: cada ruta de `scope.paths` y del diff se resuelve con `realpath -m` relativo a la raíz del repo (elimina `../`, `./` y enlaces simbólicos que ya existen en el árbol) y se compara también en minúsculas contra la lista. Una ruta que sale de la raíz del repo, o que no se puede resolver, se rechaza (fail-closed).
- **Symlinks en el diff**: `realpath` no resuelve un enlace que el propio diff crea, porque aún no está en el árbol base. Por eso se rechaza (exit 7) cualquier LP cuyo diff añada, modifique o cambie de tipo un enlace simbólico (modo git `120000`), apunte a donde apunte.

### R9 — Validación independiente con recibo

`scripts/learning-validate.sh <LP>`:

- **Clave estable de caso.** Los ids del corpus de SE-364 son posicionales (`ev-{i:03d}` en `evidence-capture.py`): regenerar el corpus o insertar un caso cambia ids. Por eso la partición **no** usa el id: usa `case_key = sha256(source + "\0" + input + "\0" + output_rejected)` normalizado (sin espacios sobrantes). Dos casos con el mismo contenido son el mismo caso.
- **Partición estable** del corpus en `dev` y `holdout` (80/20) por `case_key`. Los casos citados en `evidence` de la LP se excluyen del `holdout` (no se valida con lo que generó la propuesta: patrón train/held-out de ACE). El recibo **congela** la lista de `case_key` del `holdout`; una validación posterior de la misma LP reutiliza esa lista, no la recalcula.
- Ejecuta el `regression_test`:
  - debe **fallar** en el commit base, ejecutado **con el fichero del test del cambio superpuesto al árbol base** (un test nuevo no existe en la base; «no encontrado» no cuenta como fallo). Si con el test superpuesto el resultado es «no encontrado», error de entorno o pasa, el veredicto es `INVALID_TEST`;
  - debe **pasar** con el cambio;
  - más el `holdout` antes y después.
- Escribe un **recibo** JSON en `output/learning-loop/receipts/` con:
  - `lp_id` y `lp_hash`: sha256 del fichero de la LP **sin los campos que escribe el ciclo de vida** (`lifecycle`, `validation_receipt`, `human_trailer` y cualquier otro que escriba `learning-lifecycle.sh`; la lista exacta se fija como constante en el script y en este recibo, `lp_hash_excluded_fields`). Así activar la LP no cambia su `lp_hash`;
  - commit base y **`target_blobs`**: lista ordenada de `(ruta, id de blob git)` de los ficheros destino **después** del cambio. El recibo se liga al **contenido** resultante, no al commit: así sobrevive a una fusión squash o rebase, que crean otro commit con el mismo contenido;
  - lista congelada de `case_key` del `holdout`, métricas antes/después, resultado del test antes/después;
  - identidad del perfil validador y sesión validadora distinta de la proponente, y proveedor independiente si lo hay (opcional);
  - `receipt_hash`: sha256 del recibo canonicalizado (claves ordenadas) **sin el propio campo `receipt_hash`**, que la activación cita en un trailer (R11).
- **Recálculo al promover.** `learning-lifecycle.sh --to active` **exige** `--validation-receipt` y no se fía de él: recalcula `lp_hash`, los `target_blobs` del árbol que se va a activar y el `receipt_hash`, y comprueba que la lista de `holdout` no está vacía y no contiene casos de `evidence`. Las métricas se leen del recibo, no de flags. Sin recibo, con recibo de otra LP, de otro contenido destino, con hash alterado o con `holdout` vacío: rechazo (exit 8). **El gate deja de poder saltarse omitiendo métricas.**
- **Orden de comprobación**: primero se valida el recibo entero (exit 8 ante cualquier fallo); solo con un recibo válido se evalúan sus métricas, y una regresión da exit 5. Un recibo con una métrica editada a mano es exit 8, nunca 5, porque su hash ya no cuadra.
- **Límite declarado.** El recibo es un fichero que puede escribir quien tenga shell; la «sesión validadora distinta» la declara quien llama. El recálculo impide reutilizar un recibo para otro contenido o editarlo a mano sin que cambie su hash, pero no prueba que la validación la hiciera otra entidad. La garantía de autoridad sigue siendo la revisión humana de R10, no el recibo.
- Si el corpus SE-364 no da casos (ver «Dependencias»), no hay promoción: exit 8 con el motivo.

### R10 — Promoción solo con revisión humana verificable

- **Lo que se escribe es la intención; `active` se deriva.** `learning-lifecycle.sh --to active` escribe en la LP `lifecycle: activation_requested` y `validation_receipt: <receipt_hash>`. Nunca escribe `active`.
- **Estado derivado** (lo calcula `learning-lifecycle.sh status <LP>` y lo consume recall), por este orden:
  1. `expired` si `expires_at` ya pasó (R12);
  2. `rolled_back` si en `origin/main` hay un commit con el trailer `Learning-Rollback: <lp_id>` (R11) **posterior** al último commit de activación de esa LP;
  3. `active` si se cumplen **las cuatro**: (a) en el historial de `origin/main` hay un commit con los trailers `Learning-Proposal: <lp_id>` y `Validation-Receipt: <receipt_hash>` (`git log origin/main --format=… --grep`, sin red); (b) los blobs de los ficheros destino en ese commit coinciden con `target_blobs` del recibo; (c) los blobs de esos ficheros **en la punta actual** de `origin/main` siguen coincidiendo con `target_blobs`; (d) el recibo se recalcula válido (R9). La condición (c) cierra el hueco del revert: un `git revert` (o cualquier cambio posterior del destino) deja el commit de activación en el historial con sus trailers, pero cambia los blobs de la punta, así que la LP deja de ser `active` aunque falte el trailer de rollback;
  4. `pending_activation` en cualquier otro caso con `activation_requested` (por ejemplo, la activación solo existe en una rama `agent/*`, el commit de main no tiene los trailers o tiene otro contenido, o el destino cambió después en main).
- **Por qué funciona tras squash o rebase**: no se exige que el commit validado sea ancestro de main, sino que main contenga un commit con el **mismo contenido destino** y los **trailers** de la LP. La fusión squash de GitHub conserva los trailers en el mensaje y el rebase conserva el commit entero. Si una fusión los pierde, la LP queda `pending_activation` (fail-closed) y se reactiva con un commit en main que los lleve; no hay revalidación implícita.
- **Límite declarado** (como en R4): la comprobación usa la ref local `origin/main`, que alguien con shell puede mover (`git update-ref`, `fetch` desde otro remoto). La spec no lo presenta como control de autoridad. Con SE-488 implementada, el recibo de aprobación por fusión sustituye a la búsqueda en `origin/main` y cierra ese hueco.
- **Límite declarado (contenido concurrente)**: si otra PR cambia un fichero destino entre la validación y la fusión, o después, los blobs no coinciden con `target_blobs` y la LP queda `pending_activation`. Es fail-closed a propósito: el contenido activo ya no es el validado. Se reactiva con un recibo nuevo sobre el contenido actual.
- **`--human-trailer` deja de aceptar texto libre**: la cadena **completa** debe casar con una regex cerrada (`^(sha:[0-9a-f]{40}|se488:[A-Za-z0-9._-]{1,64})$`, commit de merge o id de recibo de SE-488), evaluada sobre el valor entero con `[[ "$v" =~ … ]]` y no línea a línea con `grep`; cualquier valor con salto de línea (`\n`) o retorno de carro (`\r`) se rechaza antes de la regex. Cualquier otro valor → exit 4. Además, ningún valor de usuario (`--human-trailer`, `--actor`, `--reason`) se interpola en una expresión de `sed` ni se concatena en JSON: el fichero se reescribe con un editor que trata el valor como dato y el ledger se serializa con un codificador JSON. Hoy `learning-lifecycle.sh` interpola `$HUMAN_TRAILER` en una expresión de sustitución de `sed`, lo que permite ejecutar órdenes, y mete `$ACTOR` y `$REASON` sin escapar en el JSON del ledger. Esta parte es el slice S0 (ver «Plan por slices»).
- `learning-recall.sh --mode effective` solo inyecta LP en estado derivado `active`.

### R11 — Reversible con un commit

- La activación es **un único commit** que solo toca el destino de la LP y su fichero, con los trailers `Learning-Proposal: LP-…` y `Validation-Receipt: <receipt_hash>`.
- `learning-lifecycle.sh` rechaza la activación si el diff toca otra cosa.
- `learning-rollback.sh --lp <id>` localiza en la rama actual el commit de activación vigente (el de main tras squash o rebase, si ya está fusionado) y lo revierte con `git revert`. El commit de revert lleva el trailer `Learning-Rollback: <lp_id>`, que R10 usa para derivar `rolled_back`. Registra el motivo en `rollback.jsonl`.
- **Commit candidato**: es un commit con los trailers de activación de la LP **posterior** al último commit con `Learning-Rollback: <lp_id>` (o cualquiera, si nunca hubo rollback). Así, una LP reactivada tras un rollback tiene un único candidato: la reactivación. Si hay cero candidatos, o más de uno (por ejemplo, un squash que repite trailers ya presentes en otro commit sin rollback entre medias), no revierte nada y sale con error: no elige.
- **Prueba de reversibilidad**: con un revert inmediato (sin commits posteriores sobre el destino), el árbol del destino queda idéntico, byte a byte, al del commit base. Si hubo commits posteriores sobre el destino y el revert da conflicto, el script aborta el revert (`git revert --abort`), no deja el árbol a medias y sale con error. Se arregla así el NOOP actual con activaciones ya commiteadas.

### R12 — Caducidad

- Al vencer `expires_at`, la LP pasa al estado derivado `expired`:
  - recall deja de inyectarla;
  - `learning-report.sh` la lista para revisión;
  - no se borra (tombstone, CRIT-024).
- Renovarla exige un recibo nuevo de R9 y la misma revisión de R10.

### R13 — Las cifras no conceden autoridad

| Sitio | Hoy | Tras esta spec |
|---|---|---|
| `learning-autonomy.sh` (SCL-006) | `p ≥ 0,70` concede L2 sin humano | `p_consistent` solo fija un **techo**. Lo concedido es `min(techo, nivel otorgado por una persona)`; sin otorgamiento registrado, L1 como máximo. **Cambia SCL-006** y requiere su aprobación expresa. |
| `/playbook-evolve --auto` | aplica cambios de riesgo bajo | genera LP (R7) y no aplica nada. `--auto` solo automatiza la redacción. |
| `instincts-protocol.md` | sin confirmación desde el 50 % | la confianza **ordena** sugerencias; ningún instinto ejecuta sin confirmación |
| `skill-lifecycle.md` | consenso ≥ 0,75 = «aprobado para adopción» | «apto para revisión humana»; adoptar = PR revisada |

Un test guardián recorre estos cuatro sitios y falla si reaparece una concesión derivada solo de una cifra.

## Multioperador

- Nada depende de una persona concreta. `baseline_reviewed_by` y la revisión salen del perfil activo; sin perfil, `reground --apply` y la activación se niegan.
- Funciona **sin** codebase-memory ni codegraph (R2 con stdlib; el resto, `UNVERIFIED`), **sin** SaviaVaults (fallback a `docs/learning-proposals/`) y **sin** proveedor independiente (validadora = otra sesión).
- Los tests usan dos perfiles sintéticos: un vínculo revisado por uno no cuenta como revisado por el otro en su instalación, y los recibos llevan la identidad del perfil.

## Criterios de aceptación

**Parte 1**

- **AC-1** Fixture Python: cambiar solo comentarios o formato de una función anclada → `FRESH`; cambiar una sentencia → `CHANGED`; cambiar los parámetros con la misma ruta y nombre → `CHANGED`. El mismo par para Bash y Markdown. Los fixtures de `FRESH` llevan `baseline_reviewed_by`.
- **AC-2** Renombrar el símbolo → `MISSING`; trasladarlo intacto a otro fichero → `MOVED`; moverlo a dos ficheros (desaparece de la ruta original) → `AMBIGUOUS` con ambos candidatos listados y ninguno elegido; copiarlo a otro fichero dejando el original → `FRESH`.
- **AC-3** Lenguaje sin resolutor, o vínculo sin `baseline_reviewed_by` aunque los hashes coincidan → `UNVERIFIED` (nunca `FRESH`). Resolutor que lanza excepción → exit ≠ 0 y ningún `FRESH` en la salida (fail-closed).
- **AC-4** `check` dos veces sobre el mismo árbol → salida JSON idéntica byte a byte.
- **AC-5** `reground --apply` con `SAVIA_AUTONOMOUS_RUN=1`, o en una rama `agent/x` → exit 4 y fichero sin cambios. Sin `--apply` → solo previsualización, sin escritura.
- **AC-6** Una nota con un vínculo `CHANGED` sigue apareciendo en `vault_rag` con `drift: CHANGED` en el hit. Una nota sin `code_refs` sale idéntica a antes (regresión).
- **AC-7** `knowledge-graph.sh build` crea relaciones `documents` con `provenance`. La migración de `relations` es idempotente (dos builds, mismo recuento). Un camino con un salto `INFERRED` devuelve confianza 0,6, no la media.
- **AC-8** `suggest` sobre una nota con un nombre que resuelve a dos símbolos → `AMBIGUOUS` y no escribe en la nota.
- **AC-9** Banco de deriva ejecutado, con precisión y exhaustividad por estado. Banco de respuesta ejecutado, con exactitud antes/después e intervalos, en un informe versionado y sin datos privados. Los datos se publican sean cuales sean.

**Parte 2**

- **AC-10** `--to canary` de una LP sin `scope`, sin `expires_at` o con `regression_test` inexistente → exit 6. Una LP anterior a esta spec se sigue leyendo sin error.
- **AC-11** LP con `scope.paths` sobre `.claude/settings.json` → rechazo en la captura (exit 7). Lo mismo para una ruta de `learning-authority-paths.txt` alcanzada por un enlace relativo (`../`), por un enlace simbólico dentro del repo o con otras mayúsculas. Una ruta que sale de la raíz del repo → rechazo. LP con `target: script` cuyo diff toca `scripts/learning-lifecycle.sh` (gate del aprendizaje) → exit 7. LP cuyo diff crea un symlink nuevo, aunque apunte a una ruta inocua → exit 7. Caso negativo: LP sobre una skill normal sin symlinks → aceptada.
- **AC-12** `--to active` sin `--validation-receipt` → exit 8, **también** sin flags de métricas (hoy pasa). Recibo de otra LP, de otro contenido destino (`target_blobs`), con una métrica editada a mano (cambia `receipt_hash`) o con `holdout` vacío → exit 8. Regresión de métrica según un recibo válido → vuelve a `proposed` y exit 5 (hoy sale 0). Recibo con una métrica de regresión editada a mano → exit 8, no 5. Ciclo completo validar → `--to active` (escribe `lifecycle` y `validation_receipt`) → recálculo: el `lp_hash` coincide con el del recibo y el `receipt_hash` se recalcula igual.
- **AC-13** `learning-validate.sh` con un `regression_test` que ya pasa en el commit base (con el test superpuesto) → veredicto `INVALID_TEST` y sin promoción posible. Un test nuevo que falla de verdad en la base con el fichero superpuesto → válido; uno cuyo fallo en la base es «no encontrado» → `INVALID_TEST`. Para `target: lesson`, un test que solo busca el texto en el fichero → `INVALID_TEST`. Los casos de `evidence` no aparecen en el `holdout` del recibo. Regenerar el corpus con los casos en otro orden no cambia la partición.
- **AC-14** LP con `activation_requested` cuyo commit de activación solo existe en una rama `agent/*` → estado derivado `pending_activation`, y `learning-recall.sh --mode effective` no la inyecta. La misma activación fusionada en un repo de prueba por squash (otro commit, mismo contenido y trailers) → `active`. Fusionada por squash sin los trailers → `pending_activation`. `--human-trailer "cualquier-cosa"` → exit 4. `--human-trailer` con dos líneas, la primera válida (`sha:<40 hex>`) y la segunda no → exit 4. `--human-trailer` con una carga que use el comando de ejecución de GNU sed, y `--actor` y `--reason` con comillas, barras y saltos de línea → exit 4 o valor escrito literal, sin ejecutar nada (fichero centinela no creado) y ledger que sigue siendo JSON válido. Caso negativo: `sha:<40 hex>` en una sola línea → aceptado.
- **AC-15** Activación de una LP y luego `learning-rollback.sh --lp <id>` (revert inmediato) → el destino queda byte a byte igual que en el commit base. Hay una entrada en `rollback.jsonl`. Activación cuyo diff toca otro fichero → rechazo. En un repo de prueba: activar, fusionar en `origin/main` (`status` = `active`), revertir y fusionar el revert → `status` = `rolled_back` y `learning-recall.sh --mode effective` no la inyecta. Revert manual sin trailer `Learning-Rollback` → `status` ≠ `active` (por la condición (c) de R10). Reactivar tras el rollback → un único candidato y `status` = `active`. Rollback con un conflicto por commits posteriores sobre el destino → error, árbol sin cambios.
- **AC-16** LP con `expires_at` vencido → estado `expired`, sin inyección en recall y listada en `learning-report.sh`.
- **AC-17** `learning-autonomy.sh --p-consistent 0.9 --requested L2` sin otorgamiento humano → DENIED (hoy GRANTED). Con otorgamiento L1 y `p = 0,9` → concede L1, no más. Con `p = 0,4` y otorgamiento L3 → L0 (la cifra baja el techo).
- **AC-18** Test guardián de R13 en verde. Mutar `learning-autonomy.sh` para que vuelva a conceder L2 solo por `p` lo pone en rojo.
- **AC-19** Tests multioperador con dos perfiles sintéticos en verde, sin rutas absolutas ni identidades reales en fixtures.

Cada AC tiene un test BATS o pytest con su caso negativo. Los que prueban comportamiento nuevo fallan contra main y pasan con el cambio. Excepciones declaradas: la mitad de regresión de AC-6 (una nota sin `code_refs` sale idéntica) protege lo que ya existe y pasa también contra main; AC-9 se cumple con el informe publicado, no con un test; AC-19 se cumple cuando la suite multioperador está en verde.

## Plan por slices

| Slice | Contenido | AC | Riesgo |
|---|---|---|---|
| S0 | `learning-lifecycle.sh`: `--human-trailer` con regex cerrada sobre la cadena completa, sin interpolación en `sed` y ledger con codificador JSON (parte de R10) | parte de 14 | L2 |
| S1 | `code-refs.py`: resolutores Python, Bash y Markdown, hash normalizado, estados, `check` | 1–4 | L1 |
| S2 | `reground` con negativa autónoma, `suggest`, aviso en `pr-plan`, grafo (R5) | 5, 7, 8 | L2 |
| S3 | Etiqueta de deriva en `vault_rag`, bancos y medición | 6, 9 | L2 |
| S4 | Esquema LP ampliado y separación de autoridad | 10, 11 | L2 |
| S5 | `learning-validate.sh`, recibos, estado derivado `active`, caducidad | 12–14, 16 | L3 |
| S6 | Activación de un commit y rollback por trailer | 15 | L2 |
| S7 | R13: autonomía como techo, playbook-evolve, instintos, skill-lifecycle, test guardián | 17–19 | L3 |

S0, S1 a S3 y S4 a S7 son independientes entre sí. S7 necesita la aprobación expresa del cambio sobre SCL-006.

Prioridad: S0 va antes que cualquier otro slice: es la corrección más barata y cierra una inyección de órdenes. Después, S5 y S7 dentro de la parte 2. Esta spec documenta en un repo público debilidades activas de los gates de aprendizaje (gate saltable omitiendo métricas, trailer humano libre e interpolado en `sed`, L2 sin persona); son de autogobierno interno y no se explotan desde fuera, pero la ventana debe ser corta.

## Dependencias

- **SE-364**: `to_evals()` en `scripts/evidence-capture.py` filtra `status == "open"`, aunque su docstring habla de casos cerrados. R9 consume el corpus. Si ese filtrado no se corrige o se justifica en SAVIA-RESEARCH-02, S5 queda bloqueada y falla cerrada (sin recibo, no hay promoción). No se corrige aquí. Los ids posicionales del corpus no bloquean: R9 usa su propia `case_key` de contenido.
- **SE-486** (PROPOSED): S3 respeta su admisión si se aprueba. Si no, la etiqueta solo va en la traza de `vault_rag`.
- **SE-488** (PROPOSED): R10 busca la activación por trailers y contenido en `origin/main` hasta que exista su recibo de aprobación por fusión, que entonces la sustituye.

## Fuera de alcance

- Extraer relaciones semánticas con LLM, o un grafo de llamadas completo: se reutiliza codebase-memory/codegraph cuando está, no se reconstruye.
- Adoptar MEX, Graphify o ACE como dependencias: solo se toman los patrones. No se ejecutó ninguno de los tres.
- Corregir SE-364 (`to_evals`). Cambiar los umbrales de SCL-006 (R13 solo cambia **qué** concede, no los cortes).
- Ocultar o borrar notas por deriva. Auto-re-anclar.

## Rollback

Cada slice es una PR aparte; revertirla devuelve el comportamiento anterior. `code_refs` en el frontmatter es aditivo: sin el script, las notas no cambian. Las LP con los campos nuevos siguen siendo Markdown legible por la versión anterior.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/code-refs.py`, `learning-validate.sh` y cambios en `learning-*.sh` | invocados por comandos y por `pr-plan` | mismos scripts vía AGENTS.md |
| Etiqueta de deriva en `vault_rag` | servidor MCP de Savia Vaults | el mismo servidor MCP |
| `learning-recall-hook.sh` (existente) | hook registrado en settings.json | plugin `savia-gates` (ya dual); solo cambia el filtro de estado |

### Verification protocol

- [ ] Los scripts dan la misma salida bajo ambos frontends: no leen nada del frontend.
- [ ] Ningún hook nuevo. El hook de recall, ya dual, se prueba con la misma entrada JSON por stdin en ambos caminos.
- [ ] Tests BATS y pytest sin dependencia de frontend.

### Portability classification

- [x] **PURE_BASH**: bash más Python stdlib, y el servidor MCP de Vaults, que ya es común a ambos frontends.

## Referencias

- MEX (`mex-memory/mex`): grounding a nodos de código con fingerprint de identidad y hash de cuerpo; veredictos fresh/changed/moved/missing/ambiguous; «drift is a review signal»; el re-anclaje exige revisión.
- Graphify (`Graphify-Labs/graphify`): aristas `EXTRACTED`/`INFERRED`, confianza de camino igual al salto más débil, nombres ambiguos rechazados con candidatos.
- Agentic Context Engine (`kayba-ai/agentic-context-engine`): Reflector sobre trazas y separación train/held-out. Su SkillManager actualiza el Skillbook sin persona en medio: es el antipatrón que R9–R13 impiden.
- `docs/rules/domain/knowledge-graph.md`, `docs/rules/domain/scl-001-learning-loop.md`, `docs/rules/domain/instincts-protocol.md`, `docs/rules/domain/skill-lifecycle.md`, `docs/specs/SCL-006-autonomia-graduada.spec.md`.

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Parte 2, R7**: el esquema de la lección lo define SE-473. R7 se reduce a referenciarlo y añadir `regression_test` y `confidence`. Esta spec conserva el paso de una LP a `active`: recibo, `human_trailer` verificable, rollback y R13.
- **Dependencias**: añadir SE-494 (corrige `to_evals()` de SE-364, que bloquea S5). SE-488 ya está APPROVED; el texto que la trata como PROPOSED queda obsoleto.
- **Target `skill`**: la propuesta de skill de SE-409 S1 sale como LP por este camino, no por un canal aparte.
- **Relación con SE-515**: una obligación `guarded` o `review_required` exige la aprobación auténtica que define esta Parte 2. Mientras no esté implementada, SE-515 no pasa de `advisory`.
- **R13 y SCL-006**: confirmado en main que `learning-autonomy.sh` solo lo consume el orquestador como informe y nadie aplica el nivel. El riesgo es de etiqueta, no de permisos concedidos hoy.
