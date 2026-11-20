---
status: APPROVED
priority: P3
developer_type: agent-single
created: 2026-11-13
approved_at: 2026-11-13
author: Savia
phase: A
risk: L4
human_surface: false
related_specs: [SE-511, SE-273, SE-253, SE-362, SE-456, SE-505, SE-172, SE-166]
origin: "Spec pedida por la operadora el 2026-11-13 a partir de una auditoría de agentes sobrantes hecha tras SE-511 S2 (informe privado en Savia Labs). Alcance decidido por ella: paquetes P1 a P4, un slice por paquete (P5, lenguajes, retirado el 2026-11-13). Solo spec: ningún agente se toca todavía."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "worker autónomo; encargo de la orquestadora"
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "Q1-Q3 respondidas y S5 retirada por la operadora (preguntas interactivas, registro de la orquestadora); el paso a APPROVED lo hace la orquestadora cuando la operadora lo confirme en esta PR"
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "APPROVED"
    source: "operadora: pregunta interactiva 2026-11-13 hacia las 21:30 («Todas aprobadas con este mensaje»); registro de la orquestadora, no texto literal; se formaliza al fusionar la PR"
---

# SE-527 — Recorte de agentes sobrantes (14 de 90, en cuatro slices)

> **Qué es y qué no es.** Es una propuesta de mantenimiento: menos ficheros, menos filas de routing, menos recuentos y menos tests anclados a agentes que casi seguro no se usan. **No es una reducción de contexto**: SE-511 ya recortó el contexto fijo por turno y este recorte no lo mueve de forma apreciable (ver «Problema»).

## Problema (verificado en origin/main 65faf5138, 2026-11-13)

El catálogo tiene **90 agentes** en `.opencode/agents/` (fuente de verdad) y **75 espejos** en `.claude/agents/`. Una auditoría de uso y solape sobre los 90 dio:

- **Solo 15 agentes tienen una invocación real en 90 días.** 53 no tienen ninguna y siguen citados por algo vivo (comando, skill, script, regla, fila de routing); 22 no tienen ninguna y parecían retirables o fusionables con otro. De esos 22, los seis desarrolladores por lenguaje **salen de la spec** (ver D5, «Por qué S5 sale de la spec»). Quedan 16: 4 retiradas y 12 fusiones hacia 6 destinos, 2 de ellos nuevos: neto −14 (90 → 76).
- **Los datos son cortos y eso limita lo que se puede afirmar.** Los registros de Claude Code solo llegan hasta el 3 de octubre (41 días, no 90); los de OpenCode cubren los 90. La telemetría propia no sirve: guarda el nombre del encargo, no el tipo de agente. Las ráfagas de los tribunales en `output/` son pruebas y no cuentan. Y **los jueces que lanza un orquestador por `Task` dentro de una sesión no dejan huella**: un cero en un juez significa «no consta», no «nunca corrió». Por eso la regla de la auditoría es conservadora (sin uso pero con referencia viva → revisar, nunca retirar) y esta spec solo propone lo que además tiene solape demostrado.
- **El ahorro es de mantenimiento, no de contexto.** Las descripciones de los 75 agentes de Claude Code suman unos 17,7 k caracteres (≈4,4 k tokens). Los 7 recortables que tienen espejo allí (`pdf-digest`, `word-digest`, `pptx-digest`, `fix-assigner`, `frontend-test-runner`, `test-engineer`, `reconciler`) pesan ≈1,7 k caracteres: **≈0,4 k tokens por sesión**, y solo en Claude Code. Los 4 retirados del paquete P1 existen solo en OpenCode y no cambian nada en Claude Code. Quien lea esta spec como «ahorro de tokens» la está leyendo mal.
- **El beneficio real**: 16 ficheros de agente menos (más sus espejos), menos filas en `config/judge-routing.yaml`, menos recuentos «90» repartidos por README, `CLAUDE.md` y `docs/readme/`, menos tests anclados a nombres de agente y menos referencias que se pudren.

### Qué mide la auditoría y qué no (límites que esta spec hereda)

1. Invocaciones reales = campo `subagent_type` de las llamadas a `Agent`/`Task` en transcripciones de Claude Code (desde el 3 de octubre) y en la base de OpenCode (desde mediados de julio). 90 días = desde el 15 de agosto.
2. Una referencia funcional es un fichero de comandos, skills, hooks, scripts, reglas, settings o manifiestos que cita al agente, sin contar registros genéricos (catálogo autogenerado, README, otros agentes).
3. Solape = vocabulario compartido de las instrucciones (≥ 45 %) o misma función en otra variante, con las mismas herramientas y el mismo nivel de permiso. Es una señal, no una prueba de equivalencia: por eso cada slice se valida con tareas (D3).
4. La auditoría **descartó** fusionar `hallucination-judge` con `hallucination-fast-judge` (cuerpos y presupuestos distintos), `cognitive-judge` con `correctness-judge` y `security-guardian` con `confidentiality-auditor`. Esta spec no los toca.

## Qué decide esta spec

### D1 — Cuatro slices, en este orden y en serie

Un slice = un paquete = una PR. Se fusionan de uno en uno (nunca apiladas, ninguna PR parte de la rama de otra) y cada una arranca desde `origin/main` con los recuentos del paquete anterior ya aplicados. El orden es por riesgo creciente; **S4 va el último y no arranca hasta que S1–S3 estén fusionadas y medidas**.

| Slice | Paquete | Qué | Neto | Riesgo funcional | Tier (`scripts/risk-tier.py`) |
|---|---|---|---|---|---|
| S1 | P1 retirar sin uso | Retirar `fiction-framing-judge`, `structural-framing-judge`, `tabular-analyst`, `configurator` | −4 | Bajo | **4** |
| S2 | P2 Coherence Court | `coherence-factual-judge`, `coherence-objectives-judge`, `coherence-scope-judge`, `coherence-premise-drift-judge` → nuevo `coherence-stage-judge` (4 modos) | −3 | Bajo-medio | **4** |
| S3 | P3 digests | `pdf-digest`, `word-digest`, `pptx-digest`, `archive-digest` → nuevo `document-digest` (formato como parámetro) | −3 | Medio | **4** |
| S4 | P4 ayudantes de Court, tests y drift | `fix-assigner` → `court-orchestrator`; `frontend-test-runner` → `test-runner`; `test-engineer` → `test-architect`; `reconciler` → `drift-auditor` | −4 | Medio | **4** |

Total −14: 90 → 76 (S5 se retiró entero). Si solo se acepta S1, 90 → 86.

**Tier.** Calculado con `python3 scripts/risk-tier.py --diff <ficheros del slice>` sobre una muestra de ficheros de cada slice: sale **tier 4 («humano requerido», «path de gobernanza»)** siempre que el diff incluya un fichero de `.opencode/agents/`, y los cuatro slices lo incluyen (la fuente de verdad del catálogo está ahí). Una muestra con solo espejos de `.claude/agents/` y documentación da tier 2 o 1; no sirve, porque ningún slice puede dejar de tocar `.opencode/agents/`. Consecuencia (SE-362): **cada PR de este recorte lleva revisión humana explícita de esa PR concreta y no entra en un merge-sprint por lotes de tier 1/2**. El tier real de cada PR se vuelve a calcular con su diff final y se escribe en su body.

### D2 — Qué se actualiza en cada slice (lista de comprobación común)

Cada slice toca, según corresponda, **todo** esto y deja un `grep -w` por cada nombre retirado sin resultados fuera de la historia (D4, AC-S0):

1. **Agente**: `.opencode/agents/<x>.md` y su espejo `.claude/agents/<x>.md` (generado con `scripts/agents-opencode-convert.sh`; el espejo no se edita a mano), `.claude/AGENTS-INDEX.md`, árboles `decision-trees/` que lo nombren.
2. **Catálogo e índices generados**: `docs/rules/domain/agents-catalog.md` (`scripts/agents-catalog-sync.sh`), `docs/llms-full.txt` (`scripts/llms-txt-generate.sh`), `docs/RESOLVER.md` (`scripts/resolver-md-generate.sh`), `AGENTS.md` y `docs/AGENTS.md`, `vault/00-Index/Agents.md`, `docs/agent-invocation-graph.md`, contrato `contracts/capabilities/agent.<x>.yaml` si existe.
3. **Comandos y skills** que lo despachan por nombre (por slice abajo).
4. **Routing**: `config/judge-routing.yaml` (una fila por juez; `scripts/judge-routing-verify.sh` y `tests/test-se273-s1-judge-routing.bats` comparan nº de agentes, modos y rationales: fila, rationale y modo cambian a la vez).
5. **Recuentos**: el «90» de `CLAUDE.md` (línea de estructura y línea del catálogo), `README.md` y sus traducciones, `docs/readme/*`, `docs/readme_en/*`, `docs/llms-full.txt`. Aviso: el «90» cuenta el catálogo de `.opencode/agents/`, no los ficheros de `.claude/agents/` (75). El slice actualiza el número a la cifra de catálogo que corresponda y no cambia la semántica. `CLAUDE.md` se carga en cada turno: tras tocarlo se vuelve a pasar `tests/test-se511-s2-savia-core.bats` (AC-6 compara solo la sección de seguridad con `tests/evals/se511-d4/variants/B2.md`) y la medición de `scripts/context-fixed-measure.sh`, que no puede subir. **Los textos congelados de la validación de SE-511 (`tests/evals/se511-d4/variants/*.md` y su `meta.json`) no se editan**: son evidencia de otra decisión y contienen el «90» antiguo.
6. **Permisos**: `scripts/validate-agent-permissions.sh` y `docs/agent-permissions-excess-baseline.txt` (la baseline solo puede encoger: ninguna fusión añade un par) y `docs/rules/domain/agent-permission-levels.md`. Ninguna fusión sube el nivel de permiso del destino ni le añade herramientas.
7. **Allowlist de lados**: `docs/agents-sync-allowlist.md` y `tests/bats/test-se253-agent-sync.bats`: se quitan las filas de los agentes que solo existían en OpenCode y se añaden las de los nuevos que solo existan en un lado.
8. **Tests anclados al agente**: se retiran o se reescriben, **nunca se desactivan** (causa raíz, SE-456). Cada test que se reescribe sigue pudiendo fallar: se demuestra con una mutación o contra el código anterior.
9. **Capability map, SAM y entropía**: `generate-capability-map.py`, `sam.py generate` (FRESH) y `capability-entropy.py --check` (esta reducción baja o mantiene el gate).
10. **Nombres literales en código**: `scripts/agent-frontmatter-update.py`, `scripts/kg-extract.py`, `scripts/skill-suggest.sh`, `scripts/agents-catalog-sync.sh` y los demás scripts que el `grep -w` encuentre.

### D3 — Validación: el método de SE-511, sin inventar otro

SE-511 decidió su recorte con un A/B prerregistrado (D4 y D4b), con el arnés `tests/evals/se511-d4/`: `run.py` (`build`/`run`/`analyze`, `--variant`, `--cases`), `checks.py` (reglas deterministas por caso, sin juez LLM, probadas con un ejemplo que cumple y otro que no), corpus de casos trampa y casos `golden`, dos modelos de Claude (Sonnet y Haiku), 3 repeticiones, remuestreo bootstrap con intervalo de confianza al 95 % y semilla fija, y la regla de decisión `run.py::verdict`. La variante B2 de SE-511 fue la que dio GO en ambos modelos tras un primer intento con REVERT; la lección que se hereda es que **el prerregistro se commitea antes de la primera llamada y lo que se vea después va a «Desviaciones», no se reescribe**.

Cada slice reutiliza ese arnés y esa regla:

- **Variante A**: el agente o agentes actuales como prompt de sistema, tal cual están en `origin/main`. **Variante B**: el agente fusionado (o, en retiradas, la ausencia del agente con el sustituto que se declara). Textos congelados con SHA-256 en un `meta.json` por slice.
- **Corpus por slice**: tareas representativas de **cada agente fusionado** (no solo del destino) y casos trampa de sus límites (herramienta que no debe usar, permiso que no tiene, negativa que debe mantener). Cuando el agente ya tiene un corpus propio, se parte de él (por ejemplo `tests/evals/frontend-test-runner/{golden,adversarial,bypass,edge}.json`). Mínimo: 4 tareas por agente fusionado y 3 casos trampa por slice.
- **Métricas**: cumplimiento (casos trampa resueltos como manda la regla), sobreactuación (casos `golden` con negativas o comprobaciones innecesarias) y tokens de entrada, con Δ % frente a A.
- **Decisión**: la de `run.py::verdict` sin cambios (REVERT si el cumplimiento baja más de 0,05 o la sobreactuación sube más de 0,10; GO si la cota inferior del IC del cumplimiento queda por encima de −0,05, la sobreactuación no sube (diferencia ≤ 0) y la cota superior de su IC queda en 0,10 o menos; NO CONCLUYENTE en otro caso). **Solo GO autoriza fusionar el slice.** NO CONCLUYENTE no se fusiona: se amplía el corpus con un prerregistro nuevo, no se repite hasta que salga GO.
- **Los límites de SE-511 aplican y se escriben en cada informe**: solo texto, sin herramientas ni sistema de ficheros, reglas léxicas, dos modelos de Claude, A y B no medidas simultáneamente. Con 18 casos el IC es ancho y un NO CONCLUYENTE es probable aunque B no empeore (ya pasó en D4).
- El informe va a `docs/evidence/SE-527-S<n>-validacion.md` y el prerregistro a `docs/evidence/SE-527-S<n>-prerregistro.md`, con el commit medido. Sin informe con GO la PR no sale de borrador.

### D4 — Reversión

Cada slice es una PR independiente y se revierte con `git revert` de su merge: restaura los ficheros de agente, los espejos, las filas de routing, los recuentos y los tests. Los ficheros generados (catálogo, índices, capability map, SAM) se regeneran con sus scripts tras el revert. No hay migración de datos ni estado fuera del repo. Un slice se revierte si, tras fusionarse, aparece una referencia colgante, un test de recuento o estructura en rojo en `main`, o el uso real (`subagent_type`) del nombre retirado en la repetición de la auditoría a los 30 días. La reversión de un slice no afecta a los demás.

### D5 — Por qué S5 sale de la spec

La versión anterior incluía un quinto slice (P5) que fusionaba los desarrolladores por lenguaje (go, java, php, ruby, python, typescript) en un `language-developer`. La operadora lo retiró el 2026-11-13. Dos motivos:

1. **«Sin uso en 90 días» no es una señal válida para ellos.** Los agentes por lenguaje son capacidad de reserva para proyectos de cliente, no algo de uso diario. Que no se hayan invocado en una ventana corta dice que no ha habido un proyecto de ese lenguaje, no que sobren.
2. **El beneficio que quedaba era mínimo y el riesgo no.** Tras la reducción de Q3 a `python` y `typescript`, S5 quitaba un solo fichero (−1) a cambio de arriesgar la calidad de código en los dos lenguajes más usados, con una validación real de 72 ejecuciones.

Los seis agentes por lenguaje se quedan como están. Las reglas por lenguaje siguen en los language packs en cualquier caso. Si más adelante hay datos de uso por lenguaje, se abre una spec nueva; no se reabre esta.

## Slices

### S1 — Retirar sin uso (−4)

- **Agentes.** `fiction-framing-judge` y `structural-framing-judge`: ambos con `mode: disabled` en `config/judge-routing.yaml` desde su tombstone («kept for auditing, never fires»); `tabular-analyst`: la skill `tabular-intelligence` cubre el caso y no tiene referencia funcional; `configurator`: sin referencia funcional, sin superficie en Claude Code, el despacho lo hace `docs/RESOLVER.md`. Los cuatro viven solo en `.opencode/agents/`: Claude Code no cambia.
- **Referencias a actualizar.** `config/judge-routing.yaml` (dos filas disabled), `scripts/judge-routing-verify.sh` y los casos de eval de los jueces de marco (`tests/evals/recommendation-tribunal/cases.jsonl`), `tests/test-se273-s1-judge-routing.bats`, `docs/agents-sync-allowlist.md` y `tests/bats/test-se253-agent-sync.bats`, `tests/bats/test-spec-166-configurator.bats` (se retira junto con el agente; no se deja un test que pase sin agente), `.claude/skills/write-a-skill/SKILL.md`, `docs/RESOLVER.md`, `scripts/skill-suggest.sh`, `scripts/kg-extract.py`, `scripts/agent-frontmatter-update.py`, catálogo, `AGENTS.md`, recuentos (90 → 86).
- **Validación.** La de D3 es de nivel mínimo aquí: no hay agente fusionado cuyas tareas medir. Se comprueba (a) que `/coherence-court` y el Recommendation Tribunal siguen enrutando sin los dos jueces disabled (los tests de routing, con la fila quitada y con una fila sobrante que debe fallar), (b) que `tabular-analyst` y `configurator` tienen su sustituto nombrado (la skill `tabular-intelligence` y `docs/RESOLVER.md`) y que, con un caso de dispatch del arnés por cada uno, el sustituto resuelve la tarea sin sobreactuar, con veredicto GO.
- **Reversión.** `git revert` de la PR; regenerar catálogo e índices.

### S2 — Coherence Court (−3)

- **Agentes.** Los cuatro sub-jueces (`factual`, `objectives`, `scope`, `premise-drift`) pasan a un único `coherence-stage-judge` con cuatro modos. Mismas herramientas (`read`, `glob`, `grep`), mismo tier `mid`, solo `.opencode`; `coherence-court-orchestrator` se queda y pasa a llamar a uno solo con el modo como parámetro.
- **Referencias a actualizar.** `.claude/commands/coherence-court.md`, `docs/rules/domain/coherence-court.md`, `.opencode/agents/coherence-court-orchestrator.md` y su árbol `decision-trees/coherence-court-orchestrator-decisions.md`, su contrato `contracts/capabilities/agent.coherence-court-orchestrator.yaml`, `config/judge-routing.yaml` (4 filas `on-demand` → 1; rationale y modo a la vez), `tests/test-se-350-coherence-court.bats`, `docs/agent-invocation-graph.md`, catálogo e índices, recuentos.
- **Validación.** Corpus: por cada modo, un documento con el defecto que ese juez debe detectar y un documento limpio (`golden`), más un caso de modo equivocado (el juez recibe el modo `scope` y un defecto de `premise-drift`: no debe inventar un hallazgo del modo pedido). Cumplimiento = defecto detectado y señalado en su modo; sobreactuación = hallazgo en el documento limpio. Además, **una ejecución real de `/coherence-court`** antes y después, anotada como evidencia (no como medida estadística).
- **Dependencia con la decisión abierta de los tribunales.** El informe de origen recomienda medir los tribunales con ejecuciones reales antes de tocar sus jueces. S2 es el único slice que toca un tribunal, y por eso lleva la ejecución real; si la operadora prefiere esperar a la repetición de la auditoría a los 30 días (Q2), S2 se pospone sin afectar a S1, S3 y S4.
- **Reversión.** `git revert`; regenerar.

### S3 — Digests documentales (−3)

- **Agentes.** `pdf-digest`, `word-digest`, `pptx-digest` y `archive-digest` (este solo en OpenCode y delega en markitdown, SE-172) → `document-digest`, con el formato como parámetro. Mismas herramientas, nivel L3, pipeline de 4 fases común. `excel-digest` (fórmulas) y `visual-digest` (OCR) **no entran**: entradas distintas. `meeting-digest` y sus dos auxiliares tampoco.
- **Referencias a actualizar.** `scripts/truth-tribunal.sh`, `scripts/pdf-extract-probe.sh`, `docs/rules/domain/image-relevance-filter.md` y `tests/structure/test-image-relevance-filter.bats`, `docs/rules/domain/truth-tribunal-weights.md`, `docs/rules/domain/receipts-protocol.en.md`, `tests/bats/test-se-172-markitdown.bats`, `.claude/agents/excel-digest.md` (cita a sus hermanos), `docs/readme_en/12-commands-agents.md`, `docs/rules/domain/agent-permission-levels.md`, `tests/bats/test-se253-agent-sync.bats`, `tests/evals/test-context-index*.bats`, catálogo, índices, recuentos.
- **Riesgo propio.** Regresión de la extracción de imágenes y OCR contextual, que es lo que cambia de manos en `truth-tribunal.sh` y `image-relevance-filter.md`.
- **Validación.** Corpus: por formato (PDF, DOCX, PPTX, archivo comprimido) 4 tareas con un documento sintético versionado (una tabla, una imagen con texto, una nota al pie o notas del presentador, un caso límite de documento vacío o corrupto), y casos trampa (no extraer lo marcado confidencial, no escribir fuera de la carpeta de digestión). Cumplimiento = estructura de salida correcta y campos clave presentes; sobreactuación = negativas o avisos de formato inexistentes. Los tests bats de SE-172 y del filtro de imágenes, reescritos para el nombre nuevo, pasan con el agente nuevo y **fallan con un `document-digest` mutado** (formato desconocido aceptado en silencio).
- **Reversión.** `git revert`; regenerar.

### S4 — Ayudantes de Court, tests y drift (−4)

Cuatro fusiones independientes en una PR, con una validación y una decisión GO/REVERT **por fusión**: una que no dé GO se saca de la PR (fusión parcial) sin bloquear las otras.

| Origen | Destino | Nivel | Qué hay que hacer notar |
|---|---|---|---|
| `fix-assigner` | `court-orchestrator` | L2 → L4 (el destino ya lo es) | `court-orchestrator` está en `protected-jobs.yaml`: la función de `fix-assigner` pasa a un agente protegido que no se invoca desde bucles autónomos. Hoy `fix-assigner` no lo es. Es intencionado y se dice. No sube ningún permiso del destino. |
| `frontend-test-runner` | `test-runner` | L4 → L4 | Tiene contrato propio (`contracts/capabilities/agent.frontend-test-runner.yaml`), corpus (`tests/evals/frontend-test-runner/`) y `tests/bats/frontend-test-runner-l4.bats`: se migran al destino, no se pierden. |
| `test-engineer` | `test-architect` | L3 → L3 | `test-engineer` es solo .NET (xUnit); `test-architect` cubre 16 language packs. Hay que comprobar que la parte de TestContainers y cobertura .NET no se pierde. 55 ficheros lo citan: es la fusión con más referencias. |
| `reconciler` | `drift-auditor` | L1 → L1 | `drift-auditor` está protegido. Lo citan `docs/rules/domain/reconciliation-decision-tree.md` y tres scripts de reconciliación (`scripts/reconciliation-pilot.sh`, `reconciliation-resolver.py`, `reconciliation-stats.sh`) con sus tests. |

- **Otras referencias.** `.claude/commands/court-review.md`, `dev-session.md`, `my-learning.md`; `.claude/agents/decision-trees/court-orchestrator-decisions.md`; `.claude/agents/code-reviewer.md`, `context-dome-manager.md`; skills `mutation-audit`, `tdd-vertical-slices`, `test-architect`, `spec-driven-development`, `agent-code-map`; `docs/rules/domain/{assignment-matrix,dev-session-protocol,frontend-testing,handoff-templates,intelligent-hooks,workflow-as-output}.md`; `scripts/dev-workflow-generate.sh`, `hierarchical-orchestrator.py`, `reaction-engine-core.py`, `test-frontend-testing.sh`, `daily-activation-plan.sh`; los mapas de `.agent-maps/`; tests `test-code-review-court.bats`, `test-dev-workflow-generate.bats`, `test-spec-183-*.bats`, `test-delegation-guard.bats`; catálogo, índices, recuentos.
- **Validación.** Corpus por origen: las tareas que hoy hace (ciclo de arreglos tras hallazgos del Court; ejecución de tests de frontend con cobertura bajo umbral; diseño de tests .NET; clasificación de contradicciones en evolución / auto-resolución / conflicto) más casos trampa de permiso (el destino no hace con el rol nuevo nada que el origen no hiciera: `fix-assigner` no escribe código de producción, `reconciler` no edita las fuentes que clasifica).
- **Reversión.** `git revert` de la PR, o de la fusión parcial por separado si se partió en commits.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-S0 | Tras cada slice, `git grep -wF "<nombre>"` restringido a `.opencode/agents/<nombre>`, `subagent_type`, `agent: <nombre>` y listas de agentes (el patrón exacto se fija en el script de S1; la prosa que usa la palabra común, p. ej. «reconciler», no cuenta) para cada agente retirado o fusionado no devuelve ninguna referencia viva (solo historia: `CHANGELOG*`, `docs/specs-archive/`, evidencias y esta spec). Un script del slice lo comprueba y falla si queda una; el caso negativo reintroduce un nombre y debe fallar. | negativo |
| AC-S1 | Recuento coherente: el número «N agentes» de `CLAUDE.md`, `README*`, `docs/readme*` y `docs/llms-full.txt` es igual al nº de ficheros de `.opencode/agents/*.md`, y `docs/rules/domain/agents-catalog.md` está al día (`agents-catalog-sync.sh --check` o equivalente). Un recuento desfasado falla. | negativo |
| AC-S2 | Tests de estructura en verde (y `tests/bats/se527-spec-coherence.bats` para la propia spec: cuatro slices, S4 último, neto 14, tier 4, sin interfaz humana): `test-se253-agent-sync.bats`, `test-se273-s1-judge-routing.bats`, `judge-routing-verify.sh`, `validate-agent-permissions.sh` (sin par nuevo en la baseline), `sam.py check` FRESH, `capability-entropy.py --check` PASS, y los tests anclados que cada slice reescribe, cada uno demostrado capaz de fallar. | positivo / negativo |
| AC-S3 | Validación B2 (D3): informe de cada slice con veredicto GO en Sonnet y en Haiku, prerregistro commiteado antes de la primera llamada, y sin regresión en las tareas del agente fusionado. Sin informe con GO la PR del slice sigue en borrador. NO CONCLUYENTE o REVERT: el agente concreto sale del slice. | negativo |
| AC-S4 | Ningún slice sube un permiso: para cada fusión, nivel y herramientas del destino son iguales o menores que antes; el informe de cada PR lo lista. | negativo |
| AC-S5 | Los seis agentes por lenguaje siguen en `.opencode/agents/` tras todos los slices y ningún slice los nombra como origen de fusión. | negativo |
| AC-S6 | `CLAUDE.md` tocado: `tests/test-se511-s2-savia-core.bats` en verde y `scripts/context-fixed-measure.sh` no sube el total; las variantes congeladas de `tests/evals/se511-d4/variants/` quedan idénticas byte a byte. | negativo |
| AC-S7 | Cada PR trae su tier calculado con `risk-tier.py` sobre su diff final (esperado 4) y la cifra de agentes antes y después. No se mide ni se anuncia ahorro de tokens fuera de lo medido por `context-fixed-measure.sh`. | positivo |
| AC-S8 | Reversión probada: para cada slice, `git revert --no-commit` del merge sobre una copia limpia deja los tests de estructura y recuento en verde. | positivo |

## Puerta de comprensión

**No hay interfaz humana nueva** ni cambia lo que una persona ve o hace: los agentes son piezas internas, la persona sigue pidiendo lo mismo y Savia lo enruta. Por eso la spec declara `human_surface: false`, no cita rutas de superficie y no lleva escenas ni prototipo S0 (SE-505). Lo que sí requiere una persona es la **revisión de cada PR** (tier 4), las respuestas a las preguntas de abajo y la aprobación de la spec.

## Fuera de alcance

- Los agentes de gestión de proyectos (`business-analyst`, `azure-devops-operator`, `dotnet-developer`): decidir su futuro es de producto, no de higiene, y los citan decenas de comandos.
- Los dominios de anclaje flojo cuyo destino depende de si siguen vivos: COBOL, GRC, redes sociales y Application Code Twin. Quedan para una segunda ronda con decisión de la operadora.
- Los 53 agentes en «revisar» que tienen anclaje de hook, settings, manifiesto o `protected-jobs.yaml`, y los jueces de los tribunales (salvo los cuatro sub-jueces de Coherence Court de S2): no se tocan sin medir ejecuciones reales de los tribunales.
- Los seis agentes por lenguaje (`go-developer`, `java-developer`, `php-developer`, `ruby-developer`, `python-developer`, `typescript-developer`) y su posible fusión en un `language-developer`: son capacidad de reserva para proyectos de cliente y «sin uso en 90 días» no es una señal válida para ellos (D5). Las reglas por lenguaje siguen en los language packs.
- Cualquier recorte de contexto: lo hizo SE-511.
- Cambiar la política de permisos de los agentes o los umbrales de los gates.
- Instrumentar la telemetría para registrar el tipo de agente (queda como propuesta aparte).

## Decisiones de la operadora (2026-11-13)

Registro de la orquestadora de las respuestas a preguntas interactivas; no es texto literal.

- **Q1. Resuelta, luego acotada:** alcance S1–S4, un slice por paquete, fusionados en orden (S5 se añadió entonces y se retiró después; ver D5).
- **Q2. Resuelta:** S2 se hace ya, con una ejecución real de `/coherence-court` como evidencia. No espera a que se repita la auditoría.
- **Q3. Superada (2026-11-13):** había reducido la validación real de S5 a `python` y `typescript` (un agente menos en total). La reducción queda superada: la operadora retira S5 entero (D5). Los seis agentes por lenguaje no se tocan y el recuento final es 76 si S1–S4 están fusionadas.
- **S5 retirada (2026-11-13):** decisión de la operadora por pregunta interactiva. Alcance: S1–S4, neto −14, 90 → 76.

## Riesgos

- **Fusionar por solape de texto lo que no solapa en comportamiento.** Mitigación: validación por tareas de cada agente fusionado (D3). Solo GO fusiona.
- **Un cero de uso que en realidad es «no consta».** Es el riesgo central de esta spec (límite 7 de la auditoría). Mitigación: solo se tocan agentes con solape demostrado, los jueces de tribunales se limitan a S2 y la reversión es barata.
- **Dejar referencias colgantes.** Mitigación: AC-S0, un `grep -w` por nombre antes de abrir cada PR y un test de que ningún fichero versionado cita un agente inexistente.
- **Mover una función a un agente protegido** (`fix-assigner` y `reconciler` pasan a `court-orchestrator` y `drift-auditor`, que figuran en `protected-jobs.yaml`). Mitigación: se dice en la PR; no se invoca desde bucles autónomos.
- **Vender más de lo que es.** −14 agentes y ≈0,4 k tokens por sesión solo en Claude Code. Cada body de PR da las cifras medidas y no habla de ahorro de contexto.
- **Recuentos en `CLAUDE.md`.** Se carga en cada turno y es el fichero más sensible a cambios; mitigación: AC-S6.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Fuente de verdad del catálogo | `.claude/agents/<x>.md`, espejo generado por `scripts/agents-opencode-convert.sh` | `.opencode/agents/<x>.md` (se edita aquí) |
| Retirados solo en OpenCode (S1) | Sin cambios | Se borran 4 ficheros de `.opencode/agents/` |
| Routing de jueces | `config/judge-routing.yaml` (común) | El mismo fichero |
| Despacho por nombre | Comandos de `.claude/commands/`, skills, `hierarchical-orchestrator.py` | Los mismos scripts |
| Allowlist de lados | `docs/agents-sync-allowlist.md` | Igual |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los agentes nuevos (`coherence-stage-judge`, `document-digest`) se despachan por su nombre desde OpenCode y el catálogo de `.opencode/agents/` coincide con los recuentos
- [ ] Tests BATS y pytest cubren cada slice, su caso negativo y su reversión (AC-S0 a AC-S8)
- [ ] No se registra ningún hook nuevo; los cambios en hooks o `settings.json` quedan fuera de esta spec

### Portability classification

- [x] **DUAL_BINDING**: los agentes viven en los dos lados y el espejo se genera desde la fuente de `.opencode/agents/`; S1 solo afecta a OpenCode.

## Aprobación

**Aprobada por la operadora** el 2026-11-13 por pregunta interactiva hacia las 21:30 («Todas aprobadas con este mensaje»; registro de la orquestadora, no texto literal). Q1–Q3 y la retirada de S5 se respondieron antes, también por pregunta interactiva el mismo día. Se formaliza al fusionar la PR. Cada slice se fusiona con revisión humana de su PR (tier 4).
