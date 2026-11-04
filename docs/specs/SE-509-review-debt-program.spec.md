---
status: PROPOSED
priority: P2
developer_type: agent-team
created: 2026-11-04
author: Savia
phase: B
risk: L2
related_specs: [SE-068, SE-309, SE-456, SE-167, SE-162, SE-048, SE-094, SE-220, SE-338, SE-362, SE-380, SE-397, SE-400, SE-433, SE-501]
resource: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-4-best-practices
origin: "Handoff de SaviaVASS del 2026-11-04 (encargo de spec SE-VASS-PROMPT-STRUCTURE, fuera del repo). Las cuatro decisiones de la sección «Decisiones» de SE-509e las tomó la operadora el 2026-11-04 en pregunta interactiva y sustituyen a las recomendaciones del handoff. Enmienda de la operadora del 2026-11-04: SE-509 pasa a ser el programa de deuda técnica de revisión de todo el inventario; la estructura de prompts queda como una de sus líneas. Solo spec."
timeline:
  - from: "2026-11-04"
    learned: "2026-11-04"
    value: "PROPOSED"
  - from: "2026-11-04"
    learned: "2026-11-04"
    value: "PROPOSED — enmienda: programa de deuda de revisión (SE-509a..e)"
---

# SE-509 — Programa de deuda técnica de revisión del inventario de prompts y artefactos

> Enmienda del 2026-11-04, pedida por la operadora: «gran trabajo que hay que indexar, analizar, organizar y planificar». El objeto de SE-509 deja de ser solo la estructura de los prompts y pasa a ser la **deuda de revisión** de todo el inventario de `.claude` y `.opencode`: agentes, skills, reglas, comandos, hooks, guards TS, perfiles y prompts. La reestructuración de prompts (Fases 0-2, ya escritas, con las decisiones de la operadora intactas) es la línea SE-509e del programa y usa el mismo inventario y la misma priorización.

## Partición en sub-specs

El alcance supera una spec razonable: cinco entregables con dependencias distintas y unos 1.360 artefactos. Se parte en cinco sub-specs dentro de este documento. Cada una se aprueba e implementa por separado, en su propia PR, en este orden:

| Sub-spec | Qué entrega | Depende de | Tamaño |
|---|---|---|---|
| **SE-509a** Indexar | Inventario único y regenerable, como capa sobre SE-400 F1 | — | 1 PR |
| **SE-509b** Analizar | Criterios de deuda D1-D11, puntuación riesgo × uso | a (y el linter de e para D3, con sustituto provisional) | 1 PR |
| **SE-509c** Organizar | Dueño, dominio, criticidad, destino; registro de decisiones; gate de borrado | a | 1 PR |
| **SE-509d** Planificar y cerrar el grifo | Lotes, cadencia, revisión por tier, medición, gate de PR para artefactos nuevos o tocados | a, b, c | 1 PR + lotes |
| **SE-509e** Estructura de prompts | Fases 0-2 originales (regla, linter, migración por lotes) | — (su Lote B en adelante usa la cola de d) | 4 slices |

SE-509e puede arrancar en paralelo con SE-509a: su Fase 0 y su Fase 1 no necesitan el inventario.

## Inventario de base (medido en `df4c11782`, 2026-11-04)

Un artefacto por fichero real (sin enlaces simbólicos): `.opencode/skills`, `.opencode/commands`, `.opencode/hooks` y `.opencode/docs` son enlaces a `.claude/…` o a `docs/`, así que skills, comandos, hooks y reglas existen una sola vez. Los agentes existen dos veces: `.opencode/agents` es la fuente (SE-220, `scripts/opencode-cross-audit.sh:100`) y `.claude/agents` su copia convertida (`scripts/agents-opencode-convert.sh:4-15`). Los guards TS de `.opencode/plugins` son ports de hooks bash.

| Tipo | Artefactos | Sin test (F1) | Sin mención en BATS | Sin consumidor activo (F1) | Sin cambio sustantivo desde 2026-05-04 |
|---|---|---|---|---|---|
| Agente | 90 (75 en ambos árboles + 15 solo OpenCode) | 41 | 7 | 16 | 53 |
| Skill | 139 | 77 | 46 | 0 | 41 |
| Comando | 580 | 531 | 444 | 57 | 521 |
| Hook bash | 126 | 4 | 4 | 1 | 44 |
| Guard TS | 72 ficheros (27 guards) | — (F1 no los indexa) | 33 | — | 14 |
| Regla | 340 (F1 cuenta 343) | 211 | 138 | 51 | 208 |
| Perfil | 13 | — (F1 no los indexa) | 2 | — | 9 |
| **Total** | **1.360** | **864 de 1.278** | **674** | **125 de 1.278** | **890** |

Columnas y órdenes:

- **artefactos**, **sin cambio sustantivo** y **sin mención en BATS**: `python3 <anexo-A>.py 2026-05-04 50` (script íntegro en el Anexo A; desde la raíz del repo, ≈ 3 min por la búsqueda en BATS). «Sin cambio sustantivo» excluye los 77 commits masivos (> 50 ficheros) de la historia, que son migraciones de frontmatter y regeneraciones: con ellos el recuento cae a 35, porque casi todo se tocó en bloque. El repo empieza el 2026-02-23, así que «6 meses» es casi toda la vida del proyecto.
- **sin test (F1)** y **sin consumidor activo (F1)**: `python3 scripts/ablation_inventory.py --out <dir> generate` y lectura de `records[].static_consumers.{tests,active}` (SE-400 F1). Agentes medidos sobre `.opencode/agents` (fuente). En `.claude/agents` F1 da 71 de 75 sin test porque los BATS citan la ruta de `.opencode`: el mismo agente cuenta como probado o no según el árbol. SE-509a lo resuelve con una clave por artefacto lógico, no por ruta.
- Las dos medidas de «sin test» difieren mucho (skills: 77 frente a 46; comandos: 531 frente a 444) porque miden cosas distintas: F1 cuenta referencias a la ruta y a `/comando`; la heurística cuenta cualquier aparición del nombre en un BATS. Ninguna prueba que un test **ejercite** el artefacto. SE-509b fija la definición (D2).

Otros hechos medidos:

- **Duplicados entre frontends**: 75 agentes en ambos árboles, los 75 con cuerpo idéntico (difieren solo en el frontmatter, que convierte `agents-opencode-convert.sh`); 15 solo en OpenCode y 0 solo en Claude Code. `bash scripts/opencode-cross-audit.sh` → `OK 920, DRIFT 0, OPENCODE_ONLY 15, RESULT: PASS`. Guards TS: 27 en `.opencode/plugins/guards/`, 18 con hook bash homónimo; ningún BATS ni test TS compara un guard con su hook con la misma entrada (solo `.opencode/plugins/__tests__/block-force-push.test.ts` prueba un guard aislado). Esa divergencia ya ha dejado pasar huecos solo en TS en el pasado.
- **Revisión humana registrada**: 0 artefactos. `grep -rlE '^\s*(last_reviewed|savia\.last_reviewed):' .claude/agents .opencode/agents .claude/skills .claude/commands docs/rules .claude/hooks | wc -l` → 0. SE-380 definió el campo `last_reviewed` (`docs/specs/SE-380-capability-lifecycle-usage-budget.spec.md:28`) pero está DEFERRED y no se aplicó. Hoy la deuda de revisión humana es, por definición, el inventario entero.
- **Referencias rotas**: `bash scripts/doc-health-audit.sh --json` → `broken_links 42`, `stale_refs 426`, `orphan_refs 227`, `score 20`, `pass: false` (solo `docs/` y skills).
- **Manifiestos desfasados**: `skills-manifest.json` tiene 154 entradas, generado el 2026-10-03, y 2 skills en disco no figuran en él.
- **Madurez de skills**: `bash scripts/skill-maturity-audit.sh --tsv-only` → 19 Calibrated, 114 Incomplete, 6 Stub, 0 Deprecated (139).
- **Reglas**: `bash scripts/rule-orphan-detector.sh --json` → 310 reglas, 0 huérfanas; `bash scripts/rule-manifest-integrity.sh --json` → PASS, 319 entradas. Hooks: `bash scripts/hooks-integrity-check.sh` → PASS, 126 registrados.
- **Uso real (telemetría)**: `data/skill-invocations.jsonl` (SPEC-SE-030) y `output/router-decisions.jsonl` no existen en este árbol y están en `.gitignore`. No hay señal de invocaciones versionada; el uso solo se puede medir en local.

## Lo que ya existe y se reutiliza

| Herramienta | Cita | Qué cubre | Hueco que deja |
|---|---|---|---|
| SE-400 F1 `scripts/ablation_inventory.py` | `:1-11`, `:32` (`REMOVAL_ACTIONS`), `:10` («UNKNOWN nunca lleva acción de retirada») | Un registro por recurso (2.683) con `kind`, `class`, `static_consumers.{active,tests}`, enlace al SAM; frescura por hash; ya cubre agentes, skills, comandos, hooks y reglas | Sin guards TS ni perfiles; clave por ruta (el mismo agente cuenta dos veces); sin fecha/PR de última modificación, revisión humana, tamaño, deuda ni destino |
| SE-397 SAM `scripts/sam.py`, `.scm/sam.json` | `scripts/sam.py:2` | Grafo de 2.932 nodos; 1.451 COMPONENT con procedencia | Solo cubre comandos (295 de 580), skills (139), agentes de OpenCode (90) y scripts; 0 hooks, 0 reglas, 0 perfiles, 0 guards |
| SE-167 `scripts/skill-maturity-audit.sh` | `:4-8` | Madurez de skills (Calibrated/Incomplete/Stub/Deprecated) | Solo skills |
| SE-162 `scripts/knowledge-graph.sh` / `.py` | `knowledge-graph.py:22` | Grafo de entidades (project, person, skill, decision, spec, concept, tool, rule) en SQLite fuera del repo | No modela agentes, comandos ni hooks; base local, no reproducible en CI. Útil para impacto, no como inventario |
| `model-upgrade-auditor` (agente) y skill `model-upgrade-audit` | `.claude/agents/model-upgrade-auditor.md:30-35`, `:54` | Detecta deuda de prompt (énfasis repetido, negativas, few-shot compensatorio, prompt hinchado) con juicio LLM | No determinista; informe en `output/model-audit/`; no persiste estado ni prioriza. Se usa en el análisis de cada lote, no en el inventario |
| `/docs-quality-audit` | `.claude/commands/docs-quality-audit.md:17` | Feedback de agentes sobre documentación (`public-docs-feedback/`) | No mide artefactos ni deuda de revisión; fuera de este programa |
| `drift-auditor` (agente) | `.claude/agents/drift-auditor.md:4`, `:42-45` | Drift docs/config/código, ficheros > 150 líneas, PII | Juicio LLM puntual; no produce inventario persistente |
| skill `workspace-integrity` | `.claude/skills/workspace-integrity/SKILL.md:48-52` | Orquesta `claude-md-drift-check`, `rule-manifest-integrity`, `agents-catalog-sync`, `rule-orphan-detector`, `agent-size-audit` | Agrega veredictos, no un registro por artefacto |
| skill `codebase-map` | `.claude/skills/codebase-map/SKILL.md:29` | Mapa comandos → agentes → reglas → skills por LLM | Lo cubre mejor y de forma determinista `static_consumers` de F1 |
| skill `rules-traceability` | `.claude/skills/rules-traceability/SKILL.md:13` | Reglas **de negocio** (RN-XXX-NN) → PBIs | No trata reglas del workspace; no aplica |
| Manifiestos | `scripts/rule-manifest-generate.sh:5`, `:71`; `skills-manifest.json`; `scripts/build-skill-manifest.sh:4` | Rule manifest `{tier, consumers}` (SE-338) en sync; manifiesto de skills con `maturity` | El de skills está desfasado (arriba); tier solo para reglas |
| `scripts/opencode-cross-audit.sh` | `:4`, `:100` | Duplicados y drift `.claude`/`.opencode` en agentes, comandos y skills | No cubre hooks ↔ guards TS |
| `scripts/hooks-integrity-check.sh` | `:5-7` | Hooks fantasma y huérfanos frente a `settings.json` | No dice qué guard TS porta cada hook |
| `scripts/rule-orphan-detector.sh` (SE-048), `scripts/skills-usage-audit.sh` | `rule-orphan-detector.sh:9`; `skills-usage-audit.sh:3` | Referencias estáticas de reglas y skills | Solapan con F1 `static_consumers`; F1 es la fuente común |
| `scripts/doc-health-audit.sh` (SE-094) | `:6-7` | Enlaces rotos y referencias a specs inexistentes | Solo `docs/` y skills; da un total, no un registro por artefacto |
| `scripts/agent-size-audit.sh` | `:4-11` | Tamaño de agentes frente al tope de 4 KB (Rule #22) | Solo agentes |
| `scripts/usage-report.py`, `scripts/skill-usage-tracker.py` | `usage-report.py:5-6` | Uso real local (metadata) | Sin datos en el repo; solo skills y router |
| `scripts/capability-entropy.py` (SE-380) | `:4`, `:10` | Métrica con baseline congelado y trinquete (solo puede bajar) | Es el patrón de medición que copia SE-509d, no un inventario |
| SE-380 (DEFERRED) | `SE-380…spec.md:22-28` | Campos de ciclo de vida: `status`, `owner`, `last_reviewed`, `retirement_criterion`, `replaced_by` | No implementado. SE-509c reutiliza sus nombres de campo en vez de inventar otros |

Conclusión: no falta un escáner nuevo, falta **una capa** que una lo que ya hay por artefacto lógico, añada lo que nadie mide (revisión humana, fecha/PR, tamaño, paridad hook/guard) y guarde las decisiones humanas. SE-509a es esa capa.

## SE-509a — Indexar

- `scripts/review-debt-inventory.py` (Python stdlib, sin red, solo lectura, determinista) genera `output/review-debt/inventory.json` y un `.md` resumen. Importa los registros de SE-400 F1 (`ablation_inventory`) en vez de reescanear, y añade guards TS (`.opencode/plugins/**/*.ts`) y perfiles (`.claude/profiles/**/*.md`) como `kind` nuevos.
- **Clave por artefacto lógico**: `agent:<nombre>`, `skill:<nombre>`, `command:<ruta relativa>`, `hook:<nombre>`, `guard:<nombre>`, `rule:<ruta>`, `profile:<ruta>`. Un agente presente en ambos árboles es un solo registro con dos rutas.
- **Campos por registro**: `key`, `kind`, `paths[]`, `frontend` (`claude-code`, `opencode` o `ambos`, resuelto por enlace simbólico o par convertido), `tier` (`model_tier` del frontmatter en agentes/skills/comandos; `tier` del rule manifest en reglas; vacío si no hay), `lines`, `bytes`, `last_change` (`{date, commit, pr}` del último commit no masivo; `pr` sale del `(#NNNN)` del asunto, o `null`), `last_human_review` (de SE-509c; `UNKNOWN` si no hay registro o si el `sha256` registrado no es el actual), `tests[]` (BATS y corpus de `tests/evals/<nombre>/` que lo referencian, con la definición de D2), `consumers` (`static_consumers` de F1), `usage_runtime` (solo en ejecución local, ver abajo), `pair` (para agentes: cuerpo idéntico sí/no; para hooks y guards: el homónimo y si existe test de paridad), `debt` (de SE-509b), `annotation` (de SE-509c).
- **Lo derivado no se versiona.** El inventario se regenera en local y en CI y vive en `output/` (ignorado). Motivo: SE-501 (APPROVED) sacó de las PR la firma, el SAM y el manifiesto de reglas porque cada derivado versionado desalineaba a todas las PR abiertas; un inventario de 1.360 registros que cambia con cada PR repetiría ese problema. Lo que no se puede derivar —decisiones y revisiones humanas— se versiona en SE-509c, en fragmentos.
- **Uso real**: los registros llevan `consumers` (estático, reproducible). Si existen `data/skill-invocations.jsonl` o `output/router-decisions.jsonl`, la ejecución local añade `usage_runtime` con recuentos agregados (sin contenido de conversación, como `usage-report.py`). CI nunca los tiene, así que la puntuación oficial (SE-509b) usa solo uso estático; el runtime es una vista local.
- `--check` sale ≠ 0 si un artefacto en disco no tiene registro (fallo del generador, no del autor) o si hay registros sin fichero.

## SE-509b — Analizar

### Criterios de deuda (por registro, cada uno 0/1 salvo indicación)

| Id | Criterio | Medida | Peso |
|---|---|---|---|
| D1 | Sin revisión humana vigente | `last_human_review` es `UNKNOWN` o su `sha256` no es el del fichero actual | 3 |
| D2 | Sin test | Ningún BATS o eval lo **ejecuta o carga** (ruta del artefacto en una orden `run`/`bash`/`source`/`python3`, o corpus en `tests/evals/<nombre>/`). Una simple mención no cuenta | 3 |
| D3 | Test acoplado a literales | Algún test del artefacto hace `grep`/`assert` de una frase del cuerpo del prompt (patrón del hallazgo de SE-509e sobre `tests/evals/test-architect-agent.bats:43-69`) | 1 |
| D4 | Anti-patrones de prompt | Fallos de `scripts/prompt-structure-lint.sh` (SE-509e). Hasta que exista: las cinco expresiones de la tabla de recuento de SE-509e (mayúsculas enfáticas, emojis de alarma, BCP 14 fuera de `<constraints>`) | 1 por clase de fallo, tope 3 |
| D5 | Referencias rotas | Rutas o `@` a ficheros, specs o scripts que no existen (lógica de `doc-health-audit.sh` extendida a todo el inventario, no copiada) | 2 |
| D6 | Obsoleto o dormido | Marca `dormant_since`, `usage: reference-only`, `deprecated: true`, o condición que ya no se cumple (caso SE-068: modelo que ningún agente declara) | 2 |
| D7 | Sin uso | `consumers.active == 0` y no es punto de entrada (comando invocable por persona, hook registrado, agente en el catálogo) | 2 |
| D8 | Duplicado | Dos registros con cuerpo normalizado idéntico o con similitud ≥ 0,9 (jaccard de 5-gramas de palabras) que no son par convertido | 2 |
| D9 | Divergencia entre frontends | Par de agentes con cuerpo distinto; hook con guard TS homónimo sin test de paridad con la misma entrada; agente solo en un árbol sin causa registrada | 3 |
| D10 | Tamaño | Agente > 4.096 bytes (Rule #22, `agent-size-audit.sh`), regla > 150 líneas, skill > 400 líneas | 1 |
| D11 | Contradicción con reglas canónicas | Contradice `critical-facts.md`, `autonomous-safety.md`, `radical-honesty.md` o las reglas 1-8: lo marca un revisor (persona o revisora independiente) en el registro de SE-509c; no se detecta solo con regex | 3 |

`riesgo = (Σ pesos de criterios activos) × criticidad`, con criticidad 3, 2 o 1 (SE-509c).

`uso = 1 + log2(1 + consumers.active + consumers.tests)`, y × 2 si es punto de entrada en un camino caliente (hook registrado en `PreToolUse`/`SessionStart`, agente de catálogo con `model_tier: heavy`, regla cargada por `@import` en `CLAUDE.md`).

`prioridad = riesgo × uso`. Pesos y fórmula se congelan en `tests/baselines/review-debt.json` (versionado, como `capability-entropy`); cambiarlos exige enmienda de esta spec con la causa. Empates: más reciente `last_change` primero (más probable que se vuelva a tocar).

## SE-509c — Organizar

- **Registro humano versionado**: `docs/review-debt/ledger.d/<YYYYMMDD>-<rama>.jsonl`, fragmentos por PR como `CHANGELOG.d` (sin conflictos entre PR paralelas). Cada línea: `{key, sha256, event, by, date, pr, note}` con `event` ∈ `review`, `annotate`, `destination`, `decision`. `by` es un rol (`operadora`, `revisora-independiente`, `orquestadora`), nunca un nombre.
- **Anotación por artefacto** (`event: annotate`), reutilizando los nombres de SE-380: `owner` (dominio dueño: `pm`, `sdd`, `seguridad`, `memoria`, `labs`, `vaults`, `space`, `core`…), `domain`, `criticality` (3 = seguridad, autoridad, secretos, git o merge: hooks bloqueantes, guards TS, agentes con `Bash`+`Write`/`Edit`, reglas de `critical-facts`/`autonomous-safety`; 2 = invocado por otros artefactos o por CI; 1 = resto), `retirement_criterion`, `replaced_by`. La criticidad inicial la propone el generador con esas señales; una persona puede subirla, nunca bajarla sin `note`.
- **Destino** (`event: destination`): `mantener`, `migrar` (reescritura en sitio, p. ej. SE-509e), `fusionar` (con `replaced_by`), `archivar` (mover a `docs/archive/` o equivalente, con stub de redirección si tiene consumidores) o `borrar`.
- **Borrado**: solo con `event: decision`, `by: operadora`, `destination: borrar` y la referencia a su decisión (pregunta interactiva o PR). Además, en coherencia con SE-400 (`ablation_inventory.py:10`), un artefacto con `consumers.active > 0` o con clase `UNKNOWN` no puede tener destino `borrar` hasta que se archive primero y pase un ciclo sin consumidores.
- Las revisoras independientes pueden registrar `review` y `annotate`; no `decision`.

## SE-509d — Planificar y cerrar el grifo

### Lotes

- Cola = registros ordenados por `prioridad` (SE-509b). Un lote = hasta **10 artefactos** del mismo `kind` y `owner`, o hasta 400 líneas de diff, lo que llegue antes. Un agente cuenta una vez aunque toque dos árboles.
- **WIP**: el programa ocupa como máximo **1** de las 3 PR activas que fija la operadora (decisión del 2026-11-03); 2 solo si ella lo pide. SE-509e comparte ese cupo.
- **Cadencia**: un lote por semana como objetivo; el lote siguiente se abre cuando el anterior está fusionado o cerrado. Los grants de merge van por lotes de PR con `scripts/merge-sprint.sh` (SE-433), no uno por PR.
- **Qué hace un lote**: para cada artefacto, (1) revisión con la lista de comprobación (D1-D11), (2) arreglos que no cambian comportamiento o que lo cambian con test que falla antes y pasa después (SE-456), (3) registro en `ledger.d` (`review` con el `sha256` final, `annotate`, `destination`), (4) medición antes/después en el body de la PR.
- **Quién revisa, por criticidad** (alineado con SE-362): criticidad 3 → revisora independiente (proveedor distinto si lo hay) **y** revisión explícita de la operadora del PR concreto (tier 3/4); criticidad 2 → revisora independiente + grant de merge por lotes; criticidad 1 → revisora independiente + grant por lotes. Ningún agente registra `review` de un artefacto que él mismo modificó en el lote.

### Medición

- `python3 scripts/review-debt-inventory.py --summary` da: deuda inicial (congelada en `tests/baselines/review-debt.json` al fusionar SE-509b), deuda restante (Σ `prioridad`), artefactos con D1 = 0, tasa de cierre (Σ `prioridad` cerrada por semana, media de 4 semanas) y semanas restantes al ritmo actual.
- Cada lote registra en `docs/propuestas/LOG.d/` las cifras antes/después. El baseline es un trinquete: solo puede bajar, como `capability-entropy.py --check` (`:10`).

### Gate contra la reacumulación (G20 en `pr-plan` y en CI)

Sobre los artefactos añadidos o modificados en la PR (`git diff origin/main..HEAD --name-only --diff-filter=AMDR`, rutas del inventario; misma técnica que `g14_skill_catalog` en `scripts/pr-plan-gates.sh:623-640`, que ya resuelve el enlace `.opencode/skills`):

1. **Nuevo sin anotación**: un artefacto añadido sin línea `annotate` en algún `ledger.d` de la PR → FALLO.
2. **Tocado sin bajar o mantener deuda**: si la `prioridad` del artefacto sube respecto a `origin/main` → FALLO (trinquete por artefacto).
3. **Prompt tocado** (> 60 líneas de cuerpo, cuando SE-509e S2 exista): debe pasar `prompt-structure-lint.sh` → si no, FALLO.
4. **Borrado sin decisión**: un artefacto inventariado eliminado (`D`) o renombrado fuera del árbol sin `decision` de la operadora con `destination: borrar` o `archivar` → FALLO.
5. **Fail-closed**: si falta el generador, `python3`, `origin/main` o un `ledger.d` no parsea, el gate sale con error, nunca PASS.

Arranque gradual sin rebajar el criterio: durante las 2 primeras semanas tras fusionar SE-509d el gate corre en informe en `pr-plan` y bloquea en CI solo las reglas 4 y 5; después bloquea todas. La fecha de paso queda en la spec al aprobarla.

## SE-509e — Línea de estructura de prompts

Contenido original de SE-509 (Fases 0-2), sin cambios en las decisiones de la operadora. Integración con el programa:

- Usa el inventario de SE-509a para listar candidatos y el criterio D4 de SE-509b como medida de su avance.
- Su linter (`scripts/prompt-structure-lint.sh`) es la fuente de D4 y la regla 3 del gate G20.
- Lote A (los 10 heavy ya elegidos) se mantiene. Desde el Lote B, el orden sale de la cola de SE-509d filtrada por agentes `heavy`; los artefactos que ya están en un lote de SE-509d con destino `migrar` se migran en ese mismo lote, sin PR aparte.
- Cada agente migrado registra `review` en `ledger.d` con el `sha256` resultante.

### Problema (verificado en origin/main c4f317e03, 2026-11-04)

Las instrucciones de agentes, reglas y skills mezclan convenciones de estructura y abusan del énfasis tipográfico (mayúsculas, «CRÍTICO», emojis de alarma). La guía oficial de Anthropic lo desaconseja para los modelos actuales: «Soften any aggressive language… you can use more normal prompting such as 'Use this tool when…'», porque sobreactivan. La regla que debía ordenar la estructura (SE-068) está dormida y no rige a ningún agente.

Hechos internos, con cita:

1. **SE-068 está dormida y su condición ya no se cumple.** `docs/rules/domain/agent-prompt-xml-structure.md:4-5` marca `usage: reference-only` y `dormant_since: "2026-06-24"`. `:15` limita su uso a agentes con `claude-opus-4-7` y esfuerzo `xhigh`/`max`. Los agentes declaran `model_tier: heavy|mid|fast` (`docs/rules/domain/model-alias-schema.md:7`, `:91`); ningún fichero de `.claude/agents/` contiene `claude-opus-4-7` (`grep -l 'claude-opus-4-7' .claude/agents/*.md` → 0). Define 6 etiquetas (`:23-32`) y prohíbe etiquetas fuera del conjunto (`:99`).
2. **La migración de SE-068 es cosmética.** El linter (`scripts/opus47-compliance-check.sh:99-111`) solo comprueba que 5 agentes fijos (`:43`: architect, dev-orchestrator, court-orchestrator, truth-tribunal-orchestrator, code-reviewer) contengan las cadenas `<instructions>`, `<context_usage>`, `<constraints>`, `<output_format>` y el marcador `SE-068`. Hoy da `VERDICT: PASS`. Pero el contenido de esas etiquetas es un relleno de una línea: `.claude/agents/architect.md:105` dice `<instructions>Apply operational guidance above.</instructions>`. La estructura existe en el fichero, no en el prompt.
3. **Anti-patrón tipo**: `.opencode/agents/terraform-developer.md:5-6` («CRÍTICO: NUNCA ejecutar terraform apply»), `:31` («## RESTRICCIÓN CRÍTICA»), `:34-36` (🔴 NUNCA…), `:38-40` (✅ SÓLO…), `:99-103` (cinco «NUNCA» más).
4. **El texto promete más de lo que garantiza el hook.** `.claude/hooks/block-infra-destructive.sh:37-40` bloquea `terraform apply` solo en PRE/PRO; el prompt dice «NUNCA apply» sin condición. Las mayúsculas no añaden garantía y ocultan el hueco: nadie sabe qué parte de la restricción la hace cumplir el código.
5. **Corpus de evaluación ya existente** (patrón SE-309): `tests/evals/commit-guardian/` y `tests/evals/security-guardian/` tienen `golden.json` (5), `edge.json` (3), `bypass.json` (3) y `adversarial.json` (2): 13 casos cada uno. `terraform-developer` no tiene corpus.
6. **DeepSeek** es el proveedor de ejemplo del frontend OpenCode (`docs/rules/domain/model-alias-schema.md:113-121`); el modelo concreto de cada instalación se resuelve en local. No hay evidencia publicada sobre cómo responde DeepSeek a etiquetas XML o a tono sin mayúsculas.

Fuentes externas citadas por el handoff de SaviaVASS (verificadas allí el 2026-11-04, no reverificadas en esta PR): guía de Anthropic citada en `resource` (XML para separar instrucciones, contexto, ejemplos y entradas; suavizar el lenguaje agresivo; explicar el motivo); RFC 2119 y RFC 8174 (las palabras BCP 14 son normativas solo en mayúsculas); ausencia de estudios empíricos sobre RFC 2119 en LLM; recomendación de OpenAI para GPT-5 de usar sintaxis tipo XML. El handoff cita además un informe `output/research/xml-tags-rfc2119-20261104.md` y la skill `.claude/skills/macos-application-packaging/` (ejemplo de etiquetas de dominio como `<tool_selection>`, `<release_trust>`); **ninguno de los dos existe en este repositorio**: proceden del entorno de SaviaVASS.

#### Recuento (recalculado, ficheros `.md` regulares)

| Ámbito | Ficheros | Con etiquetas canónicas a inicio de línea | BCP 14 (apariciones / ficheros) | Mayúsculas enfáticas (apariciones / ficheros) | Ficheros con emoji de alarma |
|---|---|---|---|---|---|
| `.claude/agents` | 87 | 5 | 1 / 1 | 145 / 45 | 7 |
| `.opencode/agents` | 95 | 6 | 1 / 1 | 147 / 40 | 7 |
| `.claude/skills` | 465 | 0 | 2 / 1 | 329 / 135 | 71 |
| `docs/rules/domain` | 325 | 1 (la propia SE-068) | 30 / 21 | 343 / 111 | 1 |
| `.claude/commands` | 580 | 0 | 0 / 0 | 396 / 176 | 174 |

Órdenes (por ámbito `$d`): ficheros `find $d -name '*.md' -type f`; etiquetas `grep -lE '^<(role|instructions|context_usage|examples|constraints|output_format)>'`; BCP 14 `grep -ohE '\b(MUST|SHOULD|SHALL|REQUIRED|MAY)\b'`; mayúsculas `grep -ohE '\b(NUNCA|SIEMPRE|OBLIGATORIO|PROHIBIDO|CRITICAL|IMPORTANT|CRÍTICO|INMUTABLE)\b'`; alarma `grep -lE '🔴|⚠️|🚨|❌|⛔'`. Las cifras difieren de las del handoff (por ejemplo, 2 apariciones BCP 14 en skills frente a 55) porque el handoff se midió en otro árbol y con otros patrones; las de esta tabla son reproducibles aquí. `CRITICAL` incluye niveles de severidad legítimos de escáneres: el recuento es una cota superior del énfasis.

#### Agentes `heavy` reales

`grep -lE '^model_tier:\s*heavy' .claude/agents/*.md` da **23** (no 10 como suponía el handoff): architect, business-analyst, cobol-developer, code-reviewer, compliance-judge, confidentiality-auditor, context-dome-manager, court-orchestrator, drift-auditor, excel-digest, factuality-judge, hallucination-judge, infrastructure-agent, legal-compliance, meeting-confidentiality-judge, meeting-risk-analyst, model-upgrade-auditor, pdf-digest, pentester, reflection-validator, sdd-spec-writer, security-guardian, truth-tribunal-orchestrator. Reparto actual: 23 heavy, 47 mid, 5 fast. De los pilotos, solo `security-guardian` es heavy (y tiene 43 líneas, por debajo del umbral de 60); `terraform-developer` y `commit-guardian` son `mid`.

#### Tests BATS acoplados a cadenas literales (base del riesgo de rotura)

`grep -rnE '(NUNCA|SIEMPRE|OBLIGATORIO|PROHIBIDO|CRITICAL|IMPORTANT|CRÍTICO|INMUTABLE|RESTRICCIÓN)' --include=*.bats tests | grep -E 'grep|assert|\[\[|=~|output'` da **34 líneas en 21 ficheros**. La mayoría (29) comprueba niveles de severidad `CRITICAL` de escáneres (por ejemplo `tests/test-se239-history-scan.bats:257`) u otros identificadores (`CRITICAL_FACTS_START` en `tests/test-critical-facts-cap.bats:26`), no texto de prompt, y no se ve afectada. Las que sí comprueban la palabra de énfasis en un prompt son **5 líneas en 4 ficheros**:

- `tests/test-neurodivergent-profiles.bats:72` — `grep -q "NUNCA" "$RULE"` sobre `docs/rules/domain/neurodivergent-integration.md`.
- `tests/test-spec-088-pair-integrity.bats:37` — `(NUNCA|NEVER).*tool_use.*tool_result` sobre `docs/rules/domain/context-health.md`.
- `tests/test-skill-template.bats:72` y `:158` — `NUNCA|NEVER` sobre `templates/skills/_template/SKILL.md`.
- `tests/test-se-032-specs-format.bats:97` — `OBLIGATORIO` sobre una spec (fuera de alcance: las specs no son prompts).

Acoplamiento más amplio: 58 ficheros BATS citan rutas de `.claude/agents/` u `.opencode/agents/`; `tests/evals/test-architect-agent.bats:43-69` busca frases literales del cuerpo del agente («Safety verification», «positive cases»…). Entre los heavy, `architect` aparece en 60 ficheros BATS, `code-reviewer` en 17 y `security-guardian` en 10 (`grep -rlE '<agente>' --include=*.bats tests | wc -l`). La migración debe preservar esas frases o reescribir el test para que compruebe la restricción, nunca borrar la aserción.

### Decisiones (tomadas por la operadora el 2026-11-04)

1. **Fase 0 informativa, no bloqueante.** La medición A/B en DeepSeek y Claude se ejecuta y se registra con datos, pero la Fase 1 arranca sin esperar a un GO. Un resultado peor en algún modelo abre una revisión de la decisión; no cierra la spec. La protección es el umbral de parada por lote de la Fase 2.
2. **Conjunto cerrado de etiquetas.** Todo se reescribe al conjunto canónico: las 6 de SE-068 (`<role>`, `<instructions>`, `<context_usage>`, `<examples>`, `<constraints>`, `<output_format>`) más `<rationale>`. Única excepción heredada de SE-068: `<example>` dentro de `<examples>`. No se permiten etiquetas de dominio (estilo `<tool_selection>`, `<release_trust>`) ni anidar unas canónicas dentro de otras. El linter las rechaza.
3. **Vocabulario normativo en inglés literal BCP 14**: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY. Se declara una sola vez en la regla, con referencia a RFC 2119 y RFC 8174, y solo puede aparecer dentro de `<constraints>`, aunque el resto del prompt esté en español. Fuera de `<constraints>` se escribe en tono normal y en minúsculas.
4. **Numeración SE-509 en `docs/specs/`**, no `docs/propuestas/SE-VASS-…`.

### Qué decide esta spec

#### Fase 0 — Medición (informativa)

- Pilotos: `terraform-developer` (anti-patrón tipo), `security-guardian` y `commit-guardian` (ya tienen corpus).
- Variante A: texto actual. Variante B: etiquetas canónicas, `<rationale>`, BCP 14 solo en `<constraints>`, sin mayúsculas enfáticas ni emojis.
- Corpus: el existente de SE-309 para los dos guardianes, ampliado hasta ≥ 10 casos por piloto con al menos 3 casos trampa («aplica directamente», «salta el hook», «es solo DEV»); corpus nuevo para `terraform-developer` en `tests/evals/terraform-developer/` con el mismo esquema.
- Ejecución contra un modelo DeepSeek vía OpenCode y un modelo Claude, mismo corpus, misma temperatura, ≥ 3 repeticiones por caso.
- Métricas por variante y modelo: cumplimiento de restricciones (% de casos trampa rechazados), sobreactivación (% de casos `golden` rechazados o con comprobaciones innecesarias) y tokens de entrada.
- Resultado en `tests/evals/se509-ab/` con el modelo, la fecha, el commit del prompt y los datos crudos.

#### Fase 1 — Regla y linter

- SE-068 se reescribe (mismo fichero): sin condición de modelo ni `dormant_since`; aplica a todo agente, regla o skill de más de 60 líneas de cuerpo. Añade `<rationale>`, el conjunto cerrado, la declaración BCP 14 con RFC 2119/8174 y estas normas: cada MUST NOT de seguridad nombra el hook o script que lo hace cumplir (ruta existente); si no hay hook, se dice «sin hook» y se abre deuda, en vez de fingir garantía; sin emojis de alarma ni bloques «RESTRICCIÓN CRÍTICA»; la razón va en `<rationale>`, no en mayúsculas.
- El linter se separa de `opus47-compliance-check.sh` en un script neutral respecto al modelo, `scripts/prompt-structure-lint.sh`, que recibe rutas y comprueba: etiquetas dentro del conjunto, sin anidamiento, BCP 14 solo dentro de `<constraints>`, MUST NOT de seguridad con hook existente, cero emojis de alarma, mayúsculas enfáticas fuera de nombres propios, y contenido no vacío (rechaza el relleno de una línea del hallazgo 2). `--xml-tags` de `opus47-compliance-check.sh` delega en él.
- Para clasificar «de seguridad», el MUST NOT lleva la marca `[security]` al inicio; el linter no adivina por palabras.

#### Fase 2 — Migración incremental

- Antes de tocar ningún agente: reescribir las 4 aserciones de prompt listadas arriba (salvo SE-032) para que comprueben la restricción con el vocabulario nuevo o con su hook, y ejecutar las suites BATS de cada agente del lote.
- Lote A (10): los heavy con más énfasis y uso: infrastructure-agent, pentester, confidentiality-auditor, pdf-digest, legal-compliance, excel-digest, code-reviewer, cobol-developer, architect, meeting-risk-analyst. Lote B: los 13 heavy restantes. Los pilotos `mid` se migran en la Fase 0 como variante B. El resto, cuando se toque por otro motivo.
- Cada agente se migra en `.claude/agents/` y en `.opencode/agents/` en el mismo commit.
- **Umbral de parada por lote**: tras cada lote se repite la medición de la Fase 0 sobre los agentes con corpus. Si en cualquiera de los dos modelos el cumplimiento de B baja más de 5 puntos porcentuales respecto a A, o la sobreactivación sube más de 10 puntos, se para la migración y se revierte ese lote (revert del commit del lote) antes de seguir.
- `.claude/commands/` queda fuera.

### Criterios de aceptación de SE-509e

| AC | Criterio | Tipo |
|---|---|---|
| CA-1 | Corpus de ≥ 10 casos por piloto (≥ 3 trampa) en `tests/evals/<agente>/`, validado por el esquema de SE-309. | positivo |
| CA-2 | Resultados A/B de los 3 pilotos en DeepSeek y Claude en `tests/evals/se509-ab/`, con las tres métricas y los datos crudos. | positivo |
| CA-3 | El resultado se registra con datos en la spec. Si B es peor en algún modelo, se abre una revisión de la decisión 1 (registrada en el LOG); la spec no se cierra por ello. | positivo |
| CA-4 | `agent-prompt-xml-structure.md` sin condición de modelo, sin `dormant_since` ni `usage: reference-only`, con `<rationale>` y la declaración BCP 14 con RFC 2119/8174. | positivo |
| CA-5 | El linter rechaza (exit ≠ 0) un fixture con `<tool_selection>`. | negativo |
| CA-6 | El linter rechaza un fixture con `<constraints>` anidada dentro de `<instructions>`. | negativo |
| CA-7 | El linter rechaza un fixture con `MUST` dentro de `<instructions>` y acepta el mismo texto con `MUST` dentro de `<constraints>`. | negativo / positivo |
| CA-8 | El linter rechaza `MUST NOT [security]` sin hook nombrado, y uno que nombra un hook inexistente; acepta uno que nombra `.claude/hooks/block-force-push.sh`. | negativo / positivo |
| CA-9 | El linter rechaza un fixture con 🔴 o con «RESTRICCIÓN CRÍTICA», y uno con `<instructions>Apply operational guidance above.</instructions>` como único contenido. | negativo |
| CA-10 | Sin argumentos, con una ruta inexistente o con un fichero ilegible, el linter sale con error, nunca PASS. | negativo |
| CA-11 | Las 4 aserciones de prompt listadas se reescriben antes de la migración y cada una falla con el texto anterior al cambio (SE-456). | negativo |
| CA-12 | Los 10 agentes del lote A, en ambos frontends, pasan el linter y sus BATS siguen en verde sin aserciones eliminadas. | positivo |
| CA-13 | Cero emojis de alarma en los agentes migrados de `.claude/agents` y `.opencode/agents`. | positivo |
| CA-14 | El umbral de parada se aplica: un lote que lo cruza queda revertido y el LOG registra las cifras. | negativo |
| CA-15 | El MUST NOT de `terraform apply` en `terraform-developer` (variante B) nombra `block-infra-destructive.sh` y su límite real (solo PRE/PRO) o se marca «sin hook» para DEV con deuda abierta. | negativo |

### Fuera de alcance de SE-509e

- Migración masiva de skills, reglas y comandos (≈ 1.500 ficheros `.md` en los cinco ámbitos de la tabla).
- Cambiar el idioma del resto de los prompts: solo las palabras normativas van en inglés.
- Crear hooks nuevos para cubrir huecos detectados: se nombran como deuda.
- Specs, informes y documentación para personas.

### Riesgos de SE-509e

- **Fase 0 no bloqueante (decisión 1).** Contra: si B empeora en DeepSeek, se descubre con la migración en curso. Mitigación: umbral de parada y reversión por lote (CA-14), y lotes de 10 como máximo.
- **Conjunto cerrado sin etiquetas de dominio (decisión 2).** Contra: perder semántica que las etiquetas de dominio daban (qué bloque trata de qué); prompts con muchas secciones pueden quedar con `<instructions>` muy largos. Mitigación: subtítulos Markdown dentro de la etiqueta canónica.
- **BCP 14 en inglés literal (decisión 3).** Contra: mezcla de idiomas dentro de un prompt en español; las personas que lean el prompt pueden no conocer la convención, y el modelo puede responder en inglés más a menudo. Mitigación: declaración única en la regla, uso solo en `<constraints>`, medir el idioma de salida en la Fase 0.
- **Tests acoplados a literales.** 4 aserciones identificadas; 58 ficheros BATS citan agentes y algunos buscan frases del cuerpo. Se reescriben antes de migrar, nunca se eliminan.
- **Sin evidencia sobre DeepSeek.** La Fase 0 da la primera medida, con muestra pequeña: ruido. Mitigación: ≥ 3 repeticiones y datos crudos publicados.
- **Falsa garantía al nombrar hooks.** Nombrar un hook no prueba que cubra el caso (hallazgo 4). CA-15 obliga a decir el límite real.
- Compliance: no aplica (sin datos personales ni cliente regulado).

### Plan por slices de SE-509e

1. **S1** — Fase 0: corpus y ejecución A/B (CA-1, CA-2, CA-3).
2. **S2** — Fase 1: regla y linter con fixtures (CA-4 a CA-10).
3. **S3** — Reescritura de aserciones BATS (CA-11).
4. **S4** — Lote A con medición y umbral (CA-12, CA-13, CA-14, CA-15). Lote B en una spec o batch posterior con el mismo protocolo.

## Criterios de aceptación del programa (SE-509a..d)

Los de SE-509e (CA-1 a CA-15) siguen en su sección, con la misma numeración.

| AC | Sub-spec | Criterio | Tipo |
|---|---|---|---|
| CA-a1 | a | `review-debt-inventory.py` genera un registro por artefacto lógico: los totales por `kind` coinciden con el Anexo A en el mismo commit (± los artefactos añadidos o borrados desde `df4c11782`, listados). | positivo |
| CA-a2 | a | Un agente presente en `.claude/agents` y `.opencode/agents` produce un único registro con `frontend: ambos` y dos rutas; uno solo de OpenCode, `frontend: opencode`. | positivo |
| CA-a3 | a | Fixture con un hook y un guard TS homónimo sin test de paridad: `pair.parity_test` es `false`. Con test de paridad: `true`. | negativo / positivo |
| CA-a4 | a | `--check` sale ≠ 0 con un fichero de agente añadido al árbol de fixture que no aparece en la salida, y con un registro cuyo fichero no existe. | negativo |
| CA-a5 | a | Dos ejecuciones sobre el mismo árbol dan bytes idénticos; sin `data/` ni red, el resultado no cambia (determinismo, `usage_runtime` ausente). | positivo |
| CA-a6 | a | Sin `python3`, sin `.git` o con F1 roto, el generador sale con error y no escribe salida parcial. | negativo |
| CA-b1 | b | Para cada criterio D1-D10 (D11 lo registra una persona) hay un fixture que lo activa y otro que no; la puntuación de cada fixture coincide con la fórmula congelada. | negativo / positivo |
| CA-b2 | b | Un artefacto que solo **menciona** el nombre en un BATS (sin ejecutarlo ni cargarlo) tiene D2 = 1. | negativo |
| CA-b3 | b | Cambiar un peso en `tests/baselines/review-debt.json` sin enmienda hace fallar su test de congelación. | negativo |
| CA-b4 | b | Las cifras de deuda inicial (Σ prioridad, n.º con D1, D2, D9) quedan registradas en esta spec y en el LOG al fusionar b. | positivo |
| CA-c1 | c | Un `ledger.d` con `by` distinto de los tres roles, o con un nombre de persona, no valida. | negativo |
| CA-c2 | c | `destination: borrar` sin `event: decision` de `operadora` no valida; con `consumers.active > 0` o clase `UNKNOWN` tampoco, aunque haya decisión. | negativo |
| CA-c3 | c | Una revisión registrada con un `sha256` que ya no es el del fichero hace que `last_human_review` vuelva a `UNKNOWN` (D1 = 1). | negativo |
| CA-c4 | c | Una revisora independiente que intenta registrar `decision` es rechazada por el validador. | negativo |
| CA-d1 | d | G20: PR de fixture que añade `.opencode/agents/nuevo.md` sin `annotate` → FALLO; con `annotate` → PASS. | negativo / positivo |
| CA-d2 | d | G20: PR que borra un artefacto inventariado sin `decision` registrada → FALLO; con `decision` de la operadora y destino `borrar` → PASS. | negativo / positivo |
| CA-d3 | d | G20: PR que sube la `prioridad` de un artefacto tocado (p. ej. añade un emoji de alarma) → FALLO. | negativo |
| CA-d4 | d | G20 sin `origin/main`, sin generador o con `ledger.d` malformado → error, nunca PASS. | negativo |
| CA-d5 | d | Un lote con más de 10 artefactos o más de 400 líneas de diff es rechazado por el planificador. | negativo |
| CA-d6 | d | El resumen muestra deuda inicial, restante, tasa de cierre y semanas restantes; tras un lote, la deuda restante baja y el baseline se actualiza solo a la baja (subirlo falla). | positivo / negativo |
| CA-d7 | d | Un agente que modificó un artefacto en el lote no puede registrar su `review` (validador). | negativo |

## Fuera de alcance

- Revisar el contenido de los 1.360 artefactos en esta spec: aquí se fija cómo se indexa, mide, organiza y planifica. La revisión ocurre en los lotes.
- Scripts de `scripts/` (1.309 registros en F1): no son prompts ni artefactos de `.claude`/`.opencode`. Pueden entrar en una enmienda posterior usando el mismo inventario.
- Telemetría nueva o envío de uso fuera de la máquina: el uso real se lee solo de las fuentes locales que ya existen.
- Implantar SE-380 entero (ciclo de vida con presupuesto de complejidad): se reutilizan sus nombres de campo, no su alcance.
- Borrar nada: el programa propone destinos; el borrado es decisión de la operadora, uno a uno o por lote explícito.
- De SE-509e: migración masiva de skills, reglas y comandos (≈ 1.500 ficheros `.md`) fuera de los lotes, cambiar el idioma del resto de los prompts, hooks nuevos (se nombran como deuda), specs e informes para personas.

## Riesgos del programa

- **El inventario mide lo fácil, no lo importante.** D2 (sin test) y D7 (sin uso) son estáticos; un artefacto puede estar probado de verdad por un test que no lo nombra, o usarse sin referencias. Mitigación: `UNKNOWN` antes que falso negativo, nunca borrar por D7 (SE-509c), y D2 exige ejecución, no mención.
- **D1 vale 1 para todo al principio.** 0 revisiones registradas: la deuda inicial es máxima y la tasa de cierre al principio será lenta. Es el dato real, no se maquilla con revisiones retroactivas sin `sha256`.
- **Volumen frente a capacidad.** 1.360 artefactos a 10 por lote y un lote por semana son unos 136 lotes (más de dos años). La cola por `prioridad` y la regla «el resto, cuando se toque por otro motivo» (G20 regla 2) son las que hacen el programa viable; el objetivo medible es cerrar los artefactos de criticidad 3 y los 100 primeros de la cola, no el inventario entero.
- **Fricción en las PR.** G20 añade trabajo a cada PR que toca un artefacto. Mitigación: la anotación es una línea en un fragmento; el arranque en informe durante 2 semanas; sin derivados versionados (SE-501).
- **Doble fuente con SE-400.** Si F1 cambia de esquema, SE-509a se rompe. Mitigación: SE-509a importa F1 como librería y tiene un test de contrato sobre los campos que usa.
- **Revisoras sin proveedor independiente.** Si no hay proveedor distinto, la «revisora independiente» es otro agente del mismo modelo. Se dice en cada PR; la criticidad 3 exige siempre a la operadora.
- Compliance: no aplica (sin datos personales; `by` es un rol).

## Plan por slices del programa

1. **a-S1** — `review-debt-inventory.py` sobre F1, clave lógica, nuevos `kind`, `--check` (CA-a1 a CA-a6).
2. **b-S1** — criterios D1-D11, fórmula, baseline congelado y cifras de deuda inicial (CA-b1 a CA-b4).
3. **c-S1** — esquema y validador de `ledger.d`, criticidad propuesta por señales (CA-c1 a CA-c4).
4. **d-S1** — G20 en `pr-plan-gates.sh` y CI, planificador de lotes, resumen de avance (CA-d1 a CA-d7).
5. **d-S2…** — lotes de revisión por la cola, uno por semana, con WIP 1.
6. **e-S1…S4** — línea de estructura de prompts (abajo), en paralelo desde el principio.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/review-debt-inventory.py` (a, b) | Python desde la sesión y CI | El mismo; indexa `.opencode/agents` como fuente (SE-220) y `.opencode/plugins` |
| `docs/review-debt/ledger.d/` (c) | Ficheros versionados | Los mismos |
| Gate G20 (d) | `scripts/pr-plan-gates.sh` y CI | El mismo (bash, independiente del frontend) |
| Agentes migrados (e) | `.claude/agents/<a>.md` | `.opencode/agents/<a>.md` (mismo commit) |
| `scripts/prompt-structure-lint.sh` (e) | Bash desde la sesión y CI | El mismo |
| Regla SE-068 (e) | `docs/rules/domain/agent-prompt-xml-structure.md` | La misma (vía `.opencode/docs`) |
| Ejecución A/B (e) | Modelo Claude | Modelo DeepSeek del frontend OpenCode |

### Verification protocol

- [ ] El inventario trata ambos árboles y los guards TS (CA-a2, CA-a3)
- [ ] Funciona en runtime OpenCode: la Fase 0 de SE-509e se ejecuta en ambos frontends
- [ ] Tests BATS del generador, del validador de `ledger.d`, de G20 y del linter, con fixtures positivos y negativos; corren igual en cualquier motor
- [ ] No añade hooks

### Portability classification

- [x] **DUAL_BINDING**: el inventario, el registro y el gate son Python/bash puros e indexan los dos frontends; los prompts se migran en los dos árboles de agentes en el mismo commit y la medición de SE-509e cubre ambos frontends.

## Aprobación

Spec PROPOSED. Cada sub-spec (SE-509a..e) se aprueba por separado: la operadora o la orquestadora con autoridad delegada, en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.

## Anexo A — medición del inventario de base

Ejecutar desde la raíz del repo: `python3 se509-baseline.py 2026-05-04 50`. No se versiona como script porque es medición de la spec, no herramienta; SE-509a la sustituye.

```python
# SE-509 Anexo A. Uso: python3 se509-baseline.py [corte=2026-05-04] [masivo=50]
import glob, os, re, subprocess, sys
cut = sys.argv[1] if len(sys.argv) > 1 else "2026-05-04"
bulk = int(sys.argv[2]) if len(sys.argv) > 2 else 50
real = lambda gs: sorted({p for g in gs for p in glob.glob(g, recursive=True)
                          if os.path.isfile(p) and not os.path.islink(p)})
kinds = {"agente": real([".opencode/agents/*.md"]),
         "skill": real([".claude/skills/*/SKILL.md"]),
         "comando": real([".claude/commands/*.md", ".claude/commands/*/*.md"]),
         "hook": real([".claude/hooks/*.sh"]),
         "guard-ts": real([".opencode/plugins/**/*.ts"]),
         "regla": real(["docs/rules/domain/*.md", "docs/rules/languages/**/*.md", ".claude/rules/**/*.md"]),
         "perfil": real([".claude/profiles/**/*.md"])}
log = subprocess.run(["git", "log", "--format=@%cs", "--name-only", "HEAD"],
                     capture_output=True, text=True, check=True).stdout
last, day, files = {}, None, []
def flush():
    if day and len(files) <= bulk:
        for f in files: last.setdefault(f, day)
for line in log.splitlines() + ["@end"]:
    if line.startswith("@"): flush(); day, files = line[1:], []
    elif line: files.append(line)
bats = "\n".join(open(p, errors="ignore").read() for p in glob.glob("tests/**/*.bats", recursive=True))
name = lambda p: os.path.basename(os.path.dirname(p)) if p.endswith("/SKILL.md") else os.path.splitext(os.path.basename(p))[0]
print("| tipo | artefactos | sin mención en BATS | sin cambio sustantivo desde", cut, "|\n|---|---|---|---|")
tot = [0, 0, 0]
for k, fs in kinds.items():
    nt = sum(1 for p in fs if p not in bats and not re.search(r"(?<![\w-])" + re.escape(name(p)) + r"(?![\w-])", bats))
    old = sum(1 for p in fs if last.get(p, "0000") < cut)
    tot = [tot[0] + len(fs), tot[1] + nt, tot[2] + old]
    print(f"| {k} | {len(fs)} | {nt} | {old} |")
print(f"| **total** | **{tot[0]}** | **{tot[1]}** | **{tot[2]}** |")
cl = {os.path.basename(p) for p in real([".claude/agents/*.md"])}
op = {os.path.basename(p) for p in kinds["agente"]}
body = lambda p: open(p).read().split("\n---\n", 1)[-1].strip()
same = sum(1 for n in cl & op if body(f".claude/agents/{n}") == body(f".opencode/agents/{n}"))
hooks = {name(p) for p in kinds["hook"]}
guards = {name(p) for p in glob.glob(".opencode/plugins/guards/*.ts") if not p.endswith(".test.ts")}
print(f"\nagentes en ambos frontends: {len(cl & op)} (cuerpo idéntico {same}); solo OpenCode: {len(op - cl)}; solo Claude Code: {len(cl - op)}")
print(f"guards TS: {len(guards)}; con hook bash homónimo: {len(guards & hooks)}")
```
