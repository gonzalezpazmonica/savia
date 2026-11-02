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
resource: https://github.com/gonzalezpazmonica/pm-workspace/tree/main/scripts
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

`code-refs.py check [--json] [rutas…]` asigna a cada vínculo un estado:

| Estado | Condición |
|---|---|
| `FRESH` | mismo `identity` y mismo `body_hash` |
| `CHANGED` | mismo `identity`, distinto `body_hash` |
| `MOVED` | el símbolo ya no está en la ruta, pero aparece **un único** símbolo con el mismo `identity` y `body_hash` en otra ruta |
| `MISSING` | ni en la ruta ni en ninguna otra |
| `AMBIGUOUS` | más de un candidato; se listan y no se elige |
| `UNVERIFIED` | no hay resolutor, o no existe línea base revisada |

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
- **Banco de deriva** (`tests/fixtures/code-refs/`): repositorio sintético con 4 lenguajes y mutaciones etiquetadas. Hay ≥ 20 casos de cada tipo: solo comentario o formato, cambio de cuerpo, renombrado, traslado, borrado y duplicado. Se mide la precisión y la exhaustividad de cada estado.
- **Banco de respuesta** (`projects/savia-vaults/eval/code-refs-bench/`): ≥ 30 preguntas técnicas sobre el propio repositorio, con respuesta de referencia y las notas que la sostienen. ≥ 10 se plantean tras una mutación real del símbolo. Se mide la exactitud de la respuesta **antes** (notas sin etiqueta de deriva) y **después** (con etiqueta), con el mismo modelo, prompt y semilla, y comparación pareada (`evals-paired-delta.py`). El informe incluye intervalos, no solo porcentajes.
- Ningún umbral se fija en esta spec. Activar el aviso de R4 como bloqueo, o la etiqueta en `vault_rag` por defecto, es decisión de la operadora con estos datos, en una PR aparte.

## Parte 2 — Aprendizaje sin autoautoridad

### R7 — Esquema de propuesta ampliado (LP)

`scripts/learning-proposal.sh` añade al frontmatter, sin romper las LP existentes:

```yaml
scope: { paths: [...], skills: [...], domains: [...] }   # dónde aplica; vacío = rechazo
evidence: [ { source: "se364:<id>|trace:<hash>|commit:<sha>", hash: "sha256:…" } ]   # ≥ 1 fallo verificado
regression_test: "tests/…bats::<nombre>"   # falla antes del cambio y pasa después
expires_at: "2027-02-01"                   # por defecto +90 días; máximo 365
confidence: low|medium|high                # declarada
confidence_basis: "n_evidencias=3, independientes=2"   # cómo se llegó
```

- Las LP anteriores a esta spec siguen legibles. No pueden pasar a `canary` hasta completar los campos.
- `learning-lifecycle.sh --to canary` **rechaza** (exit 6) si falta algún campo, si `scope` está vacío o si `regression_test` no existe.

### R8 — Separación de conocimiento, capacidad y autoridad

- `target` de una LP ∈ {`criterio`, `lesson`, `skill`, `script`}.
- **Lista de rutas de autoridad** (`docs/rules/domain/learning-authority-paths.txt`): reglas de autonomía y merge, `.claude/settings.json`, registro de hooks, perfiles, grants y aprobaciones, niveles L0–L4, `learning-autonomy.sh` y esta propia lista.
- Una LP cuyo `scope.paths` o diff toque esas rutas se rechaza **al capturarse** (exit 7), con mensaje que remite a una spec. Cambiar autoridad es trabajo de spec, no de aprendizaje.

### R9 — Validación independiente con recibo

`scripts/learning-validate.sh <LP>`:

- **Partición estable** del corpus SE-364 en `dev` y `holdout`, por hash del id del caso (80/20). Los casos citados en `evidence` de la LP se excluyen del `holdout` (no se valida con lo que generó la propuesta: patrón train/held-out de ACE).
- Ejecuta el `regression_test`:
  - debe **fallar** en el commit base;
  - debe **pasar** con el cambio;
  - más el `holdout` antes y después.
- Escribe un **recibo** JSON en `output/learning-loop/receipts/`: `lp_id`, commit base, commit con el cambio, hash de la lista de casos `holdout`, métricas antes/después, resultado del test antes/después, sesión validadora distinta de la proponente y proveedor independiente si lo hay (opcional).
- `learning-lifecycle.sh --to active` **exige** `--validation-receipt`. Las métricas se leen del recibo, no de flags. Sin recibo, con recibo de otra LP o de otro commit, o con `holdout` vacío: rechazo (exit 5). **El gate deja de poder saltarse omitiendo métricas.**
- Si el corpus SE-364 no da casos (ver «Dependencias»), no hay promoción: exit 5 con el motivo.

### R10 — Promoción solo con revisión humana verificable

- `active` es un **estado derivado**, no un campo que se escribe: una LP está activa si su commit de activación es ancestro de `origin/main` (`git merge-base --is-ancestor`, sin red) **y** su recibo es válido. En una rama `agent/*` queda `pending_activation`.
- Con SE-488 implementada, el recibo de aprobación por fusión sustituye a la comprobación de ancestro. `--human-trailer` deja de aceptar texto libre: debe referenciar ese recibo o el commit de merge.
- `learning-recall.sh --mode effective` solo inyecta LP en estado derivado `active` y no caducadas.

### R11 — Reversible con un commit

- La activación es **un único commit** que solo toca el destino de la LP y su fichero, con el trailer `Learning-Proposal: LP-…`.
- `learning-lifecycle.sh` rechaza la activación si el diff toca otra cosa.
- `learning-rollback.sh --lp <id>` localiza ese commit por el trailer y lo revierte con `git revert`. Registra el motivo en `rollback.jsonl`.
- **Prueba de reversibilidad**: tras el revert, el árbol del destino queda idéntico, byte a byte, al del commit base. Se arregla así el NOOP actual con activaciones ya commiteadas.

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

- **AC-1** Fixture Python: cambiar solo comentarios o formato de una función anclada → `FRESH`; cambiar una sentencia → `CHANGED`. El mismo par para Bash y Markdown.
- **AC-2** Renombrar el símbolo → `MISSING`; trasladarlo intacto a otro fichero → `MOVED`; duplicarlo en dos ficheros → `AMBIGUOUS` con ambos candidatos listados y ninguno elegido.
- **AC-3** Lenguaje sin resolutor, o vínculo sin `baseline_reviewed_by` → `UNVERIFIED`. Resolutor que lanza excepción → exit ≠ 0 y ningún `FRESH` en la salida (fail-closed).
- **AC-4** `check` dos veces sobre el mismo árbol → salida JSON idéntica byte a byte.
- **AC-5** `reground --apply` con `SAVIA_AUTONOMOUS_RUN=1`, o en una rama `agent/x` → exit 4 y fichero sin cambios. Sin `--apply` → solo previsualización, sin escritura.
- **AC-6** Una nota con un vínculo `CHANGED` sigue apareciendo en `vault_rag` con `drift: CHANGED` en el hit. Una nota sin `code_refs` sale idéntica a antes (regresión).
- **AC-7** `knowledge-graph.sh build` crea relaciones `documents` con `provenance`. La migración de `relations` es idempotente (dos builds, mismo recuento). Un camino con un salto `INFERRED` devuelve confianza 0,6, no la media.
- **AC-8** `suggest` sobre una nota con un nombre que resuelve a dos símbolos → `AMBIGUOUS` y no escribe en la nota.
- **AC-9** Banco de deriva ejecutado, con precisión y exhaustividad por estado. Banco de respuesta ejecutado, con exactitud antes/después e intervalos, en un informe versionado y sin datos privados. Los datos se publican sean cuales sean.

**Parte 2**

- **AC-10** `--to canary` de una LP sin `scope`, sin `expires_at` o con `regression_test` inexistente → exit 6. Una LP anterior a esta spec se sigue leyendo sin error.
- **AC-11** LP con `scope.paths` sobre `.claude/settings.json` → rechazo en la captura (exit 7). Lo mismo para una ruta de `learning-authority-paths.txt` alcanzada por un enlace relativo (`../`).
- **AC-12** `--to active` sin `--validation-receipt` → exit 5, **también** sin flags de métricas (hoy pasa). Recibo de otra LP, de otro commit base o con `holdout` vacío → exit 5.
- **AC-13** `learning-validate.sh` con un `regression_test` que ya pasa en el commit base → recibo con veredicto `INVALID_TEST` y sin promoción posible. Los casos de `evidence` no aparecen en el `holdout` del recibo.
- **AC-14** LP marcada `active` en una rama cuyo commit no es ancestro de `origin/main` → estado derivado `pending_activation`, y `learning-recall.sh --mode effective` no la inyecta. `--human-trailer "cualquier-cosa"` ya no basta.
- **AC-15** Activación de una LP y luego `learning-rollback.sh --lp <id>` → el destino queda byte a byte igual que en el commit base. Hay una entrada en `rollback.jsonl`. Activación cuyo diff toca otro fichero → rechazo.
- **AC-16** LP con `expires_at` vencido → estado `expired`, sin inyección en recall y listada en `learning-report.sh`.
- **AC-17** `learning-autonomy.sh --p-consistent 0.9 --requested L2` sin otorgamiento humano → DENIED (hoy GRANTED). Con otorgamiento L1 y `p = 0,9` → concede L1, no más. Con `p = 0,4` y otorgamiento L3 → L0 (la cifra baja el techo).
- **AC-18** Test guardián de R13 en verde. Mutar `learning-autonomy.sh` para que vuelva a conceder L2 solo por `p` lo pone en rojo.
- **AC-19** Tests multioperador con dos perfiles sintéticos en verde, sin rutas absolutas ni identidades reales en fixtures.

Cada AC tiene un test BATS o pytest que falla contra main y pasa con el cambio, con su caso negativo.

## Plan por slices

| Slice | Contenido | AC | Riesgo |
|---|---|---|---|
| S1 | `code-refs.py`: resolutores Python, Bash y Markdown, hash normalizado, estados, `check` | 1–4 | L1 |
| S2 | `reground` con negativa autónoma, `suggest`, aviso en `pr-plan`, grafo (R5) | 5, 7, 8 | L2 |
| S3 | Etiqueta de deriva en `vault_rag`, bancos y medición | 6, 9 | L2 |
| S4 | Esquema LP ampliado y separación de autoridad | 10, 11 | L2 |
| S5 | `learning-validate.sh`, recibos, estado derivado `active`, caducidad | 12–14, 16 | L3 |
| S6 | Activación de un commit y rollback por trailer | 15 | L2 |
| S7 | R13: autonomía como techo, playbook-evolve, instintos, skill-lifecycle, test guardián | 17–19 | L3 |

S1 a S3 y S4 a S7 son independientes entre sí. S7 necesita la aprobación expresa del cambio sobre SCL-006.

## Dependencias

- **SE-364**: `to_evals()` en `scripts/evidence-capture.py` filtra `status == "open"`, aunque su docstring habla de casos cerrados. R9 consume el corpus. Si ese filtrado no se corrige o se justifica en SAVIA-RESEARCH-02, S5 queda bloqueada y falla cerrada (sin recibo, no hay promoción). No se corrige aquí.
- **SE-486** (PROPOSED): S3 respeta su admisión si se aprueba. Si no, la etiqueta solo va en la traza de `vault_rag`.
- **SE-488** (PROPOSED): R10 usa la comprobación de ancestro hasta que exista su recibo.

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
