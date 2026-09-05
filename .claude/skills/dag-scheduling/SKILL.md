---
layer: peripheral
name: dag-scheduling
description: Usar cuando se orquestan múltiples agentes SDD con dependencias entre ellos.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: developer
  savia.maturity: stable
  savia.category: sdd-framework
  savia.context: fork
  savia.context_cost: high
  savia.maturity: stable
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

---

## Problema

El pipeline SDD actual ejecuta fases de forma **secuencial**. Muchas fases pueden ejecutarse en paralelo:
- spec-slice y security-review son independientes
- unit-tests, integration-tests, docs-update pueden correr juntos
- El tiempo total se reduce significativamente

---

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

---

## Fases (6 pasos)

### Fase 1 — Parsear DAG

Leer especificación de dependencias:
- Extraer lista de fases
- Identificar dependencias
- Construir grafo dirigido
- Validar sin ciclos

**Output**: grafo en memoria, topología validada

---

### Fase 2 — Camino crítico

Calcular:
1. Camino más largo desde inicio a fin
2. Holgura (slack) de cada fase
3. Fases críticas (slack = 0)
4. Fases paralelizables

**Output**: tabla de holgura, estimación

---

### Fase 3 — Agendar

Agrupar fases en **cohortes paralelas**:
1. Identificar grupos independientes
2. Respetar SDD_MAX_PARALLEL_AGENTS (default 5)
3. Garantizar sin conflictos de escritura

**Output**: plan de agendamiento

---

### Fase 4 — Ejecutar (wave-executor)

Delegar ejecucion al motor generico `scripts/wave-executor.sh`:
- Recibe task-graph JSON con IDs, comandos, dependencias y timeouts
- Agrupa tareas en waves por nivel topologico (max SDD_MAX_PARALLEL_AGENTS)
- Ejecuta cada wave en paralelo con timeout por tarea
- Verifica expected_files tras cada wave; fallo detiene pipeline

**Output**: execution-report JSON (status, waves, timing, speedup)

---

### Fase 5 — Sincronizar

Tras completar cohorte:
- Validar ficheros y tests
- Mergear outputs
- Proceder a siguiente cohorte

---

### Fase 6 — Reportar

Informe de ejecución con timeline, mejora porcentual, cuellos de botella

---

## Configuración

```yaml
SDD_MAX_PARALLEL_AGENTS: 5
SDD_DEFAULT_TIMEOUT_MIN: 30
SDD_WORKER_ISOLATION: worktree
```

---

## Referencia

- Skill: .opencode/skills/spec-driven-development/SKILL.md
- Regla: docs/rules/domain/parallel-execution.md
- Comandos: /dag-plan, /dag-execute
