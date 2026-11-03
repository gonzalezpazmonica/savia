---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L4
related_specs: [SE-053, SE-079, SE-222, SE-378, SE-387, SE-404, SE-433, SE-488]
origin: "Fricción medida en el merge-sprint del 2026-11-02: tras cada merge, las demás PR quedan en conflicto por el registro de planificación y hay que re-revisar con LLM cambios administrativos. Encargo de la orquestadora, plan intensivo. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-500 — Merge-sprint sin realineación manual: fragmentos de planificación, integración en línea y plan ordenado

## Problema (verificado en origin/main 4579370d8)

Cada spec nueva se registra editando dos ficheros compartidos: `docs/propuestas/planning-state.json` (una iniciativa más en `initiatives`) y `docs/propuestas/LOG.md` (una entrada más al principio). Dos PR que registran specs distintas tocan las mismas líneas de esos dos ficheros. En cuanto `run` fusiona una, la siguiente choca con `main`.

`run` re-sincroniza cada PR con `main` (`resync`, `scripts/merge-sprint.sh:258`), pero solo admite conflictos en los derivados de `DERIVED_RE` (`scripts/merge-sprint.sh:235`): `.scm/`, `.confidentiality-signature`, `docs/rules/INDEX.md` y `docs/rules/domain/rule-manifest.json`. El registro de planificación no está en esa lista, así que:

1. `resync` aborta el merge y la PR se aparca con `conflicto_real`, aunque el «conflicto» sea juntar dos entradas independientes.
2. Si alguien integra a mano (hoy, con un integrador local fuera del repo y un resolutor de planificación), el árbol del head ya no es `merge(revisado, main)` salvo derivados. `head_equivalent` (`scripts/merge-sprint.sh:247`) falla y la PR necesita revisión nueva con LLM sobre un cambio administrativo, y otro grant.

Hay además un hueco frente a SE-433 §2.6: la spec exige que «cada derivado se regenera con el código de `origin/main` y debe coincidir», pero `head_equivalent` se limita a **ignorar** las diferencias en derivados (`scripts/merge-sprint.sh:252-254`), sin regenerarlos ni compararlos. Y `resync` ejecuta los generadores de la rama de la PR, no los de `main` (límite ya declarado en `autonomous-safety-merge-sprint.md`).

### Medición (2026-10-20 → 2026-11-03)

Fuentes: ledger y registro de revisiones locales de merge-sprint (fuera del repo), `gh pr list/diff` y `git log --first-parent origin/main`.

| Métrica | Valor |
|---|---|
| PR fusionadas en `main` | 127 (124 commits first-parent) |
| Commits de `main` que tocan `planning-state.json` o `LOG.md` | 23 |
| Ejecuciones de `run` | 40 |
| Merges hechos por `run` | 62 (1,55 por ejecución) |
| Aparcamientos | 32: `conflicto_real` 17, `ci_roja` 5, `no_abierto` 3, `merge_rechazado` 3, `head_cambiado_requiere_juez` 2, `resync_fallo` 1, `tier_3` 1 |
| PR distintas aparcadas por `conflicto_real` | 13, de ellas 6 tocan el registro |
| Tiempo de pared de `run` | 798 min en total, mediana 16 min por ejecución |
| PR revisadas sobre más de un SHA (re-revisión) | 23 de 87; 8 de ellas tocan el registro (cota superior de las evitables) |
| Sprint del 2026-11-02 | 4 grants y 5 merges en el día; el último manifiesto tenía 5 candidatas y fusionó 2. De las 5 PR distintas aparcadas por conflicto ese día, 4 (#1449, #1453, #1454, #1456) eran PR de spec cuyo único choque era el registro |
| PR abiertas hoy | 11, de ellas 7 tocan el registro |

Lectura: el registro de planificación no explica todos los conflictos (la mitad de las aparcadas por conflicto en dos semanas tenía choques de código), pero sí casi todos los de las PR de solo spec, que son las más frecuentes en el plan intensivo y las que obligan a re-grant y re-revisión sin que cambie nada revisable.

## Objetivo

Que una PR cuyo único solapamiento con las demás es el registro de planificación o un derivado se fusione en el mismo sprint, sin intervención y sin re-revisión con LLM, manteniendo intactos los invariantes de SE-433. Que los conflictos de código real se aparquen con motivo concreto y que `plan` los anticipe antes del grant.

Tres slices independientes, en este orden. Cada una aporta por separado.

## S1 — Fragmentos de planificación

Mismo patrón que `CHANGELOG.d/` (SE-053): cada PR añade ficheros nuevos y no edita ninguno compartido.

### Formato

- `docs/propuestas/planning.d/SE-NNN.json`: un objeto JSON con el registro completo de la iniciativa, con el mismo esquema que un elemento de `initiatives`. El nombre debe ser `^SE-[0-9]+\.json$` y coincidir con `id`.
- `docs/propuestas/LOG.d/SE-NNN-<ESTADO>.md`: exactamente una entrada, `## YYYY-MM-DD SE-NNN ESTADO` seguida de un párrafo opcional. Nombre y cabecera deben coincidir. Sin otras cabeceras. El nombre debe cumplir `^SE-[0-9]+-(<estados>)\.md$`, donde `<estados>` es la lista cerrada de estados válidos que ya usa la comprobación 2 de `validate`; cualquier otro nombre (espacios, `..`, estado desconocido) falla y no se usa nunca como ruta ni en shell.
- `planning-state.json` y `LOG.md` siguen existiendo como **base consolidada**. Las iniciativas de la base solo cambian por consolidación. Las claves que no son `initiatives` (`route`, `session_plan`, suelos) se siguen editando en la base: cambian poco y su conflicto es real.

### Vista consolidada

`scripts/planning-view.py` (Python stdlib, sin red):

- `state`: base con los fragmentos aplicados en orden numérico de id. Si el id existe en la base, el fragmento la sustituye (transición pendiente de consolidar); si no, se añade.
- `log`: cabecera de `LOG.md`, luego las entradas de `LOG.d/` ordenadas por fecha descendente, id numérico descendente y rango de estado descendente, y luego el cuerpo de la base. Los fragmentos van encima de la base sin comparar fechas: si un fragmento tiene fecha anterior a la entrada más reciente de la base, la vista lo muestra encima igualmente. Es aceptable porque el LOG es append-only y la base solo crece por consolidación, pero `validate` avisa (no falla) de esos casos para que no pasen inadvertidos.
- `consolidate`: escribe la vista en la base y borra los fragmentos aplicados.

Propiedades exigidas: determinista (misma salida byte a byte con independencia del orden del sistema de ficheros y del locale), idempotente (`consolidate` dos veces no cambia nada) y conservadora (`vista(base consolidada, sin fragmentos) == vista(base, fragmentos)`).

La consolidación no es un workflow: la ejecuta `bash scripts/roadmap.sh consolidate` en una PR ordinaria cuando hay más de 30 fragmentos o en el cierre de una era. Se evita así un workflow nuevo en `.github/workflows/` (tier 4) y el push forzado que usa hoy `changelog-consolidate.yml`.

### Escritores y lectores

- `scripts/roadmap.sh` lee siempre la vista: `current`, `next`, `history`, `render` y `validate`. Nuevo subcomando `register SE-NNN --status --priority --phase --title --note --evidence`, que escribe los dos fragmentos.
- `scripts/spec-lifecycle.sh` escribe la entrada en `LOG.d/` en lugar de editar `LOG.md`.
- `scripts/planning-transition.sh` y la comprobación de autoridad de AC de `scripts/validate-ci-local.sh` leen la vista.
- `docs/propuestas/ROADMAP-CURRENT.md` se genera desde la vista.

### Validación (`roadmap.sh validate` sobre la vista)

Las 10 comprobaciones actuales (`scripts/roadmap.sh`, numeradas en el código: 1 ids únicos, 2 estados válidos, 3 IMPLEMENTED con evidencia, 4 APPROVED con aprobación, 5 cobertura del registro en la era canónica, 6 estado de la spec frente al registro, 7 estado vigente registrado en LOG, 8 ruta con WIP y fase válida, 9 cola editorial con estados y fases existentes, 10 entrada que pide aprobar una spec ya aprobada) se evalúan sobre la vista con la misma severidad que hoy sobre la base. En particular, un fragmento que sube el `status` de su spec a APPROVED sin aprobación registrada falla la comprobación 4. Se añaden:

- nombre de fragmento y `id` coinciden; JSON válido con los campos obligatorios; un id no aparece en dos fragmentos;
- cada entrada de `LOG.d/` tiene una sola cabecera que coincide con su nombre;
- `validate --diff origin/main`: en una PR, un cambio en `initiatives` de la base solo es válido si, para cada id cambiado, la misma PR borra su fragmento y el registro nuevo de la base es igual al fragmento de `origin/main` (es decir, es una consolidación pura). Cualquier otro cambio en `initiatives` de la base falla.

### Impacto en G13 y pr-plan

- G13 (`g13_scope_trace`, `scripts/pr-plan-gates.sh`): `planning.d/SE-NNN.json` y `LOG.d/SE-NNN-*.md` cuentan como trazados solo si `SE-NNN` está entre las specs referenciadas por la PR. No es una lista blanca: un fragmento de otra spec falla.
- pr-plan no edita hoy el registro (verificado: ningún gate escribe `planning-state.json` ni `LOG.md`). Solo cambia la pista de reparación de `validate-ci-local.sh`, que pasa a nombrar `roadmap.sh register` y los fragmentos.
- `scripts/risk-tier.py`: los fragmentos están bajo `docs/`, tier 1, como hoy el registro.

### Migración

Una PR: crea los directorios con un `README.md`, `planning-view.py`, los cambios de lectores y escritores, G13 y tests. La base no se toca: hoy ya está consolidada y hay cero fragmentos. Las PR abiertas en ese momento que editan la base siguen chocando; las resuelve S2 o su autora pasando la entrada a fragmento. La regla `autonomous-safety-merge-sprint.md` y el encargo común de los workers pasan a decir «registra la spec con `roadmap.sh register`».

## S2 — Integración en línea dentro de `run`

`run` ya re-sincroniza cada PR con `main` antes de fusionarla (SE-433 v2). S2 cambia qué conflictos sabe resolver, cómo verifica la equivalencia y con qué código regenera.

### Resolutor determinista

`scripts/merge-registry-resolve.py` (Python stdlib), versión en el repo y endurecida del resolutor local que hoy usa la orquestadora:

- **Registros** (lista cerrada, rutas exactas): `docs/propuestas/planning-state.json` y `docs/propuestas/LOG.md`.
  - `planning-state.json`: parte de la versión de `main`; aplica el delta de la PR respecto al merge-base, **restringido a iniciativas** (altas y cambios de las iniciativas que la PR toca). «Que la PR toca» se define como en G13: los ids de las specs referenciadas por la PR. El delta se calcula siempre desde `H0` revisado frente al merge-base, nunca desde `H1`. Rechaza si el delta cambia una iniciativa cuyo id no está entre las referenciadas, si la PR cambia cualquier otra clave, borra una iniciativa, o cambia una iniciativa que `main` también cambió desde el merge-base con otro valor.
  - `LOG.md`: inserta arriba, en orden determinista, las entradas que la PR añade respecto al merge-base. Rechaza si la PR modifica o borra entradas existentes (el LOG es append-only).
  - El resultado debe pasar `roadmap.sh validate` ejecutado con el código de `main`. Si no, rechaza.
- **Derivados regenerables**: `DERIVED_RE` actual más `docs/propuestas/ROADMAP-CURRENT.md` y `docs/propuestas/INDEX.md`. Se regeneran con los generadores de `main`.
- Rechazar significa salir con 2 y la lista de ficheros: `run` aparca la PR con `conflicto_real` y esos ficheros en el ledger. Nunca se consulta un LLM dentro de `run`.

### Código congelado

El resolutor y los generadores que usa `run` se toman del commit de `main` congelado en el manifiesto, extraídos a un directorio temporal, nunca de la rama de la PR. El manifiesto añade `resolver_blob` y `run` lo comprueba como hoy comprueba `runner_blob`. Esto cierra, para registros y derivados, el límite declarado «la re-sincronización ejecuta generadores de la rama del PR».

### Equivalencia ampliada

Sean `H0` el head revisado, `H1` el head tras integrar, `M` el `main` integrado y `T = merge-tree(H0, M)`. Para cada ruta en la que `H1` difiere de `T`:

- si es un derivado, el ejecutor lo regenera con el código congelado sobre `H1` y compara con la **forma canónica** de ese derivado (tabla siguiente). Corrige el hueco de §2.6 descrito arriba;
- si es un registro, el ejecutor recalcula `resolver(merge-base, H0, M)` y debe coincidir byte a byte con `H1` (el resolutor no escribe marcas de tiempo; AC-11b lo prueba);
- cualquier otra ruta no es equivalente: sigue el camino actual (prefiltro y juez, o aparcar).

#### Comparación canónica de derivados

Varios generadores escriben una marca de tiempo, así que una regeneración nunca coincide byte a byte con `H1` (verificado: `scripts/propuestas-index-gen.sh:120-123` escribe `<!-- Last regenerated: … -->` y su propio `--check` filtra esa línea; `scripts/rule-manifest-generate.sh:76` escribe `"generated"` y su comparación lo descarta en la línea 93). La comparación se define por derivado, en una tabla cerrada dentro de `merge-registry-resolve.py` y congelada con `resolver_blob`:

| Derivado | Forma canónica comparada |
|---|---|
| `docs/propuestas/INDEX.md` | Todas las líneas salvo exactamente una que cumpla `^<!-- Last regenerated: [0-9TZ:-]+ -->$`; si hay cero o más de una, no equivalente |
| `docs/rules/domain/rule-manifest.json` | JSON parseado sin la clave de primer nivel `generated`, que debe existir y cumplir `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$`; el resto, igualdad de objetos |
| `.confidentiality-signature` | No se regenera ni se compara: el ejecutor repite la auditoría con el código congelado sobre el diff de `H1` y vuelve a firmar, como fija SE-433 §2.6. Si la auditoría no da PASSED, no equivalente |
| `.scm/`, `docs/rules/INDEX.md`, `docs/propuestas/ROADMAP-CURRENT.md` | Byte a byte: hoy no escriben marca de tiempo |

Cualquier derivado nuevo entra en la tabla con su forma canónica en la misma PR; un derivado sin fila no es equivalente (fail-closed). La normalización solo quita el campo de fecha con formato exacto: texto añadido en esa línea o una segunda línea de fecha hacen que no coincida.

El ledger registra la equivalencia `registry_merge`, el blob del resolutor y los hashes de los registros recalculados.

### Flujo e invariantes

Tras cada merge con CI de `main` en verde, la siguiente PR del manifiesto se integra con `main`, se resuelven registros y derivados, se empuja sin forzar (si la rama se movió, el push falla y la PR se aparca), se espera su CI y se fusiona con `--match-head-commit`. Se mantienen sin cambios: grant con digest exacto, tier 4 fuera (el tier se recalcula sobre todos los ficheros), sin rebase ni push forzado, ledger encadenado, STOP, CI de `main` verde tras cada merge y auto-rebase en pausa por etiqueta.

## S3 — Plan ordenado

- `plan` calcula, para cada par de candidatas, el conflicto previsto con `git merge-tree --write-tree --name-only` entre sus heads, descontando registros y derivados. También el solapamiento de ficheros sin conflicto, solo como aviso.
- La predicción es **heurística**: compara pares, no la secuencia real contra `main` con las anteriores ya fusionadas, así que admite falsos positivos y falsos negativos. No sustituye a `resync` ni a la equivalencia de S2, que siguen decidiendo en `run`; solo ordena y avisa.
- Orden: primero un conjunto de PR sin conflictos entre sí, elegido con un voraz determinista (grado ascendente en el grafo de conflictos y luego número de PR, ambos ascendentes); después las que chocan, por número de PR ascendente.
- Efecto esperado del orden: una PR que choca con otra se aparca con cualquier orden. El orden solo gana cuando hay cadenas de choques (A–B–C: fusionar A y C antes que B evita dos aparcamientos) o un límite de merges por tanda. La mejora de M1 viene sobre todo de S1 y S2; S3 se mide aparte (AC-17b).
- El manifiesto añade `order` (lista de PR) y `collisions` (`{pr, with, files}`), cubiertos por el digest. `run` sigue `order`.
- `plan` imprime el orden y, por cada colisión prevista, «#A chocará con #B en f1, f2». Ese aviso va en la pregunta del grant: la operadora puede excluir PR o pedir antes un trabajador.
- **Esto modifica SE-433 §2.5**, que fija el orden ascendente. Aprobar SE-500 es aceptar ese cambio; el orden sigue congelado bajo el grant.

## Métricas de éxito

| Métrica | Línea base | Objetivo |
|---|---|---|
| M1 Merges frente a candidatas por sprint | 2/5 en el último manifiesto del 2026-11-02; 62 merges y 32 aparcamientos en dos semanas (0,66) | 0 aparcamientos por `conflicto_real` en PR cuyo único choque es registro o derivado; 0,85 o más en total, sin contar CI roja |
| M2 Re-revisiones LLM evitadas | 0 (`registry_merge` no existe); hasta 8 de 23 re-revisiones en dos semanas tocaban el registro | Cada integración administrativa queda como `registry_merge` y no pide revisión nueva |
| M3 Tiempo de pared | 798 min de `run` en dos semanas, mediana 16 min; 4 grants el 2026-11-02 para 5 merges | Un grant por tanda; minutos desde el primer grant hasta el último merge, medidos por `report` |

`merge-sprint.sh report` añade estas tres cifras a partir del ledger.

## Criterios de aceptación

### S1

- [ ] AC-1: `planning-view.py state` y `log` dan la misma salida byte a byte con los fragmentos creados en orden distinto y con `LC_ALL` distinto.
- [ ] AC-2: `consolidate` es idempotente, y la vista antes y después de consolidar es idéntica.
- [ ] AC-3: `roadmap.sh validate` sobre la vista detecta lo mismo que hoy sobre la base: cada una de las 10 comprobaciones tiene un caso negativo con el fallo puesto en un fragmento; entre ellos, un fragmento que cambia el `status` de su spec a APPROVED sin aprobación registrada → FAIL. Un `LOG.d/` con nombre fuera de la regex (estado desconocido, espacios o `..`) → FAIL.
- [ ] AC-4: negativo, fragmento con nombre e `id` distintos, JSON inválido o id duplicado en dos fragmentos → FAIL.
- [ ] AC-5: negativo, una PR que edita una iniciativa de la base sin ser consolidación pura → `validate --diff origin/main` FAIL; positivo, la PR de consolidación pasa.
- [ ] AC-6: `roadmap.sh register` y `spec-lifecycle.sh` escriben solo fragmentos; dos PR que registran specs distintas se fusionan en cualquier orden sin conflicto (test con dos ramas y `git merge`).
- [ ] AC-7: G13 da PASS a un fragmento de la spec referenciada y FAIL a un fragmento de otra spec.
- [ ] AC-8: `planning-transition.sh`, `validate-ci-local.sh` y `ROADMAP-CURRENT.md` leen la vista: una iniciativa solo presente en un fragmento aparece en los tres.

### S2

- [ ] AC-9: dos PR de spec con registro en conflicto en el formato antiguo: tras fusionar la primera, `run` integra la segunda, la resuelve y la fusiona con equivalencia `registry_merge`, sin revisión nueva.
- [ ] AC-10: negativo, colar código en un registro. Una PR que, junto a su alta, cambia `route`, añade una clave nueva, cambia el estado o cualquier campo de una iniciativa de una spec no referenciada por la PR, o borra una → el resolutor rechaza y la PR se aparca con `conflicto_real` y la lista de ficheros.
- [ ] AC-11: negativo, registro manipulado tras resolver: `H1` difiere del resultado recalculado por el ejecutor en un byte → no equivalente, sin merge.
- [ ] AC-11b: el resolutor es determinista: ejecutado dos veces con relojes distintos (`faketime` o `SOURCE_DATE_EPOCH` distintos) y `LC_ALL` distinto da la misma salida byte a byte.
- [ ] AC-12: negativo, derivado manipulado: `.scm/`, `docs/rules/INDEX.md` o `ROADMAP-CURRENT.md` en `H1` difiere de su regeneración con el código congelado → no equivalente, sin merge. Hoy pasa (test que falla antes del cambio).
- [ ] AC-12b: positivo, `docs/propuestas/INDEX.md` y `rule-manifest.json` regenerados en `H1` con otra hora que la del ejecutor → equivalentes. Negativos: una fila de spec cambiada en `INDEX.md`, una regla quitada de `rule-manifest.json`, texto extra en la línea de fecha, dos líneas de fecha o la clave `generated` ausente → no equivalente.
- [ ] AC-12c: `.confidentiality-signature`: con un diff que la auditoría bloquea, `H1` con firma válida de otro diff → no equivalente; con auditoría PASSED, el ejecutor re-firma y la PR es equivalente.
- [ ] AC-12d: negativo, un fichero que coincide con `DERIVED_RE` sin fila en la tabla canónica → no equivalente.
- [ ] AC-13: negativo, conflicto de código real (dos PR que cambian las mismas líneas de un script) → aparcada con `conflicto_real` y ficheros; ningún LLM invocado; el sprint sigue con la siguiente.
- [ ] AC-14: `resolver_blob` distinto del manifiesto → anomalía y STOP; el resolutor de la rama de la PR nunca se ejecuta (test con un resolutor trampa en la rama).
- [ ] AC-15: los invariantes de SE-433 siguen cubiertos: la suite actual de `tests/test-merge-sprint.bats` pasa sin tocar sus aserciones, y hay casos nuevos para push no forzado sobre rama movida, tier 4 entre los ficheros resueltos y STOP durante la integración.
- [ ] AC-16: `report` imprime M1, M2 y M3 desde el ledger.

### S3

- [ ] AC-17: con tres PR #10 (A), #11 (B) y #12 (C), donde A y B cambian el mismo fichero y C es independiente, `plan` da exactamente `order = [12, 10, 11]` (C tiene grado 0; A y B empatan a grado 1 y desempata el número) y avisa «#10 chocará con #11 en f» nombrando el fichero.
- [ ] AC-17b: con una cadena A–B–C (A choca con B, B con C, A y C independientes), `plan` ordena A y C antes que B; en el test de integración, `run` fusiona 2 y aparca 1, frente a 1 fusionada y 2 aparcadas con el orden ascendente A, B, C.
- [ ] AC-18: el orden es determinista: mismas entradas, mismo `order` y mismo digest.
- [ ] AC-19: negativo, colisiones solo en registros o derivados no generan aviso.
- [ ] AC-20: negativo, `order` editado tras el grant → el digest no coincide y `run` no arranca; `run` sigue `order` y no reordena.

## Fuera de alcance

- Cambiar el workflow de auto-rebase (`.github/workflows/auto-rebase-open-prs.yml`) para que use el resolutor. Es tier 4 y va en otra spec si S2 lo justifica.
- Merges en paralelo, merge queue de GitHub, rebase.
- Resolver conflictos de código, con o sin LLM.
- Cambios en el juez de SE-433 §2.7.
- Consolidación automática por workflow.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| El resolutor es superficie nueva dentro del ejecutor | Lista cerrada de rutas, delta restringido a iniciativas, recalculado por el ejecutor con blob congelado, tier 4 |
| Un fallo de la vista oculta una iniciativa | AC-1 a AC-3 y la propiedad conservadora; `validate` corre sobre la vista en CI |
| PR abiertas durante la migración | S2 resuelve el formato antiguo; S1 no reescribe la base |
| El orden de S3 cambia una garantía de SE-433 | Orden congelado en el manifiesto y en el digest, visible en la pregunta del grant |
| G13 más estricto rompe PR legítimas que tocan el fragmento de otra spec | Es el comportamiento buscado: una PR registra solo lo suyo; el override de G13 sigue existiendo |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/planning-view.py`, `scripts/merge-registry-resolve.py` | Invocados por `roadmap.sh` y `merge-sprint.sh` | Los mismos scripts |
| `scripts/merge-sprint.sh`, `scripts/roadmap.sh`, `scripts/pr-plan-gates.sh` | Bash desde la sesión o CI | Bash desde la sesión o CI |
| Skill `merge-plan` (se crea en la PR de S3; no existe todavía) | `.claude/skills/merge-plan/SKILL.md` | La misma vía el enlace `.opencode/skills` |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los scripts no dependen del frontend
- [ ] Tests BATS y pytest cubren el único camino de ejecución
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH**: bash y Python stdlib; ningún binding de frontend.

## Aprobación

Las PR de implementación son tier 4 (tocan `scripts/merge-sprint.sh`). La PR de esta spec solo toca `docs/` y `risk-tier.py` la clasifica en tier 1: nada mecánico la excluye de un grant. Lo que impide que la fusione un agente es que todo merge exige un grant firmado por la operadora (SE-343, SE-433 D7; firma desde el móvil por SE-488) y esta línea: la operadora no la incluye en ningún manifiesto de merge-sprint y la fusiona ella a mano tras aprobarla. Ningún agente la fusiona. La aprobación cubre S1, S2 y S3 y la modificación del orden de SE-433 §2.5 descrita en S3. Cada slice se implementa en su propia PR.
