---
layer: peripheral
name: dag-scheduling
description: Usar cuando se orquestan múltiples agentes SDD con dependencias entre ellos.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: developer
  savia.maturity: beta
  savia.category: sdd-framework
  savia.context: fork
  savia.context_cost: high
  savia.priority: high
  savia.summary: "Orquesta agentes SDD en paralelo usando grafos de dependencias. Calcula camino critico, cohortes paralelas y ahorro de tiempo. Input: spec con tasks. Output: plan DAG + ejecucion."
  savia.tags: "dag, parallel, orchestration, pipeline"
---

## Subagent Scope Guard

> If you were dispatched as a subagent to execute a specific delegated task,
> **skip this skill's full orchestration workflow**. Execute only the assigned
> task, report result (DONE / DONE_WITH_CONCERNS / BLOCKED), and return.
> This guard prevents runaway skill activation in nested agent contexts.

# Skill: DAG Scheduling — Orquestación de agentes en paralelo

Ejecuta el pipeline SDD con **ejecución paralela inteligente** mediante gráficos acíclicos dirigidos (DAG). Detecta fases independientes, calcula el camino crítico y ejecuta grupos de agentes en paralelo respetando dependencias.

## Problema

El pipeline SDD actual ejecuta fases de forma **secuencial**. Muchas fases pueden ejecutarse en paralelo:
- spec-slice y security-review son independientes
- unit-tests, integration-tests, docs-update pueden correr juntos
- El tiempo total se reduce significativamente

## DAG de ejemplo

```
spec-generate
  ↓
  ├─→ spec-slice ──────────────┐
  └─→ security-review ─────────┤
                               ↓
                           dev-session
                               ↓
        ┌──────────────────────┼──────────────────────┐
        ↓                      ↓                      ↓
  unit-tests          integration-tests         docs-update
        └──────────────────────┼──────────────────────┘
                               ↓
                           code-review
                               ↓
                    comprehension-report
                               ↓
                              merge
```

## Fases (6 pasos)

### Fase 1 — Parsear DAG

Leer especificación de dependencias:
- Extraer lista de fases
- Identificar dependencias
- Construir grafo dirigido
- Validar sin ciclos

**Output**: grafo en memoria, topología validada

### Fase 2 — Camino crítico

Calcular:
1. Camino más largo desde inicio a fin
2. Holgura (slack) de cada fase
3. Fases críticas (slack = 0)
4. Fases paralelizables

**Output**: tabla de holgura, estimación

### Fase 3 — Agendar

Agrupar fases en **cohortes paralelas**:
1. Identificar grupos independientes
2. Respetar SDD_MAX_PARALLEL_AGENTS (default 5)
3. Garantizar sin conflictos de escritura

**Output**: plan de agendamiento

### Fase 4 — Ejecutar (wave-executor)

Delegar ejecucion al motor generico `scripts/wave-executor.sh`
(contrato: `docs/specs/SPEC-WAVE-DAG.spec.md`):

```bash
bash scripts/wave-executor.sh graph.json [--report report.json]
```

- Valida el grafo antes de ejecutar nada (exit 2): `tasks` array; `id`
  `[A-Za-z0-9._-]` (1-64); `command` no vacio; `depends_on` array de ids
  (ausente = `[]`); `timeout_seconds` y `max_parallel` enteros >= 1;
  sin ids duplicados, dependencias desconocidas, ciclos ni `..` en
  `expected_files` (rutas relativas al cwd del motor).
- Agrupa por nivel topologico y parte cada nivel en sub-waves de
  `max_parallel` (del grafo; si falta, `SDD_MAX_PARALLEL_AGENTS`, default 5).
- Ejecuta cada wave en paralelo con timeout por tarea (`timeout_seconds`; si
  falta, `SDD_DEFAULT_TIMEOUT_MIN`, default 30). Al vencer: TERM a todo el
  grupo de procesos de la tarea y KILL a los `WAVE_KILL_AFTER` s (default 10).
  Una tarea que sale con 124 por si misma es `failed`, no `timeout`.
- Verifica `expected_files`; un fallo o timeout termina su wave y marca las
  siguientes como `skipped`.
- Si el motor recibe SIGTERM/SIGINT/SIGHUP, termina las tareas en curso y
  sale con 143/130.
- Exit: 0 ok · 1 tarea fallida · 2 entrada invalida · 3 timeout.

El motor NO calcula camino critico ni holgura (Fases 2-3, analisis previo con
`/dag-plan`), NO aisla en worktrees ni reintenta: si una tarea necesita
worktree o reintento, su `command` debe hacerlo. La salida de cada tarea no se
conserva: redirigela a fichero en el propio `command` si la necesitas.

**Output**: execution-report JSON (status, waves, timing, speedup)

### Fase 5 — Sincronizar

Tras completar cohorte:
- Validar ficheros y tests
- Mergear outputs
- Proceder a siguiente cohorte

### Fase 6 — Reportar

Informe de ejecución con timeline, mejora porcentual, cuellos de botella

## Configuración

```yaml
SDD_MAX_PARALLEL_AGENTS: 5     # leido por wave-executor si el grafo no fija max_parallel
SDD_DEFAULT_TIMEOUT_MIN: 30    # leido por wave-executor si la tarea no fija timeout_seconds
WAVE_KILL_AFTER: 10            # segundos entre TERM y KILL al vencer un timeout
SDD_WORKER_ISOLATION: worktree # politica del orquestador; el motor no la aplica
```

## Referencia

- Skill: .opencode/skills/spec-driven-development/SKILL.md
- Regla: docs/rules/domain/parallel-execution.md
- Comandos: /dag-plan, /dag-execute
- Tests: `tests/test-dag-scheduling.bats`, `tests/test-wave-executor.bats`
