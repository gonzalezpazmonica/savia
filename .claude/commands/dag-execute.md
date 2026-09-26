---
name: dag-execute
description: Ejecutar pipeline SDD con agentes en paralelo según DAG
context_cost: high
developer_type: all
agent: developer
model_tier: heavy
tier: core
---

# /dag-execute {task-id|spec-path}

> Ejecuta el pipeline SDD de una tarea con orquestación paralela basada en DAG. Lanza múltiples agentes simultáneamente, sincroniza resultados y reporta progreso en tiempo real.

---

## Parámetros

- {task-id} — ID de la tarea (ej: AB#1234) o ruta a spec
- --dry-run (opcional) — Mostrar plan sin ejecutar agentes

---

## Ejecución (5 pasos)

### Paso 1 — Validar e importar spec

Leer y validar la especificación:
- Verificar spec existe
- Extraer criterios de aceptación
- Preparar casos de test

### Paso 2 — Construir DAG y agendar cohortes

Usar skill dag-scheduling:
- Fase 1: parsear DAG
- Fase 2: calcular camino crítico
- Fase 3: agendar cohortes

Mostrar plan: cohortes y paralelo

### Paso 3 — Ejecutar cohortes via wave-executor

Delegar ejecucion al motor generico `scripts/wave-executor.sh`:
1. Construir task-graph JSON desde el DAG (IDs, comandos, deps, timeouts)
2. Ejecutar: `bash scripts/wave-executor.sh graph.json --report report.json`
3. wave-executor agrupa en waves, ejecuta en paralelo, verifica expected_files
4. Si falla: exit 1 (task failed) o exit 3 (timeout)
5. Leer report.json para progreso y metricas

---

### Paso 4 — Sincronizar y validar

Tras completar agentes:
- Recopilar ficheros de worktrees
- Validar: conflictos, ficheros esperados, tests
- Mergear outputs al repo
- Ejecutar code-review sobre diff completo

### Paso 5 — Generar informe final

Usar Fase 6 de dag-scheduling: reportar timeline, mejora, cuellos

---

## Output

```
═══════════════════════════════════════════════════════════
  DAG Execution Report — AB#1234
═══════════════════════════════════════════════════════════

Cronología
  Cohorte 1: spec-generate (5 min) ✅
  Cohorte 2: spec-slice [8] + security-review [6] = 8 min ✅
  Cohorte 3: dev-session (14 min) ✅
  Cohorte 4: unit-tests + integration-tests + docs = 6 min ✅
  Cohorte 5: code-review (5 min) ✅
  Cohorte 6: comprehension-report (2 min) ✅

Total Secuencial: 55 min
Total Paralelo: 38 min
Mejora: 31% más rápido (17 min ahorrados)

Ficheros generados
  ApiController.cs | ReservationService.cs | ReservationRepository.cs

Estado
  ✅ Tests pass (42/42)
  ✅ Code review: APPROVED
  ✅ Ready to merge
```

---

## Notas

- Máximo 5 agentes paralelos (SDD_MAX_PARALLEL_AGENTS)
- Si agente falla: reintenta una vez
- Usa worktrees; rollback automático si todo falla
