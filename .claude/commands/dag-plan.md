---
name: dag-plan
description: Visualizar DAG de ejecución, camino crítico y ahorro de tiempo
context_cost: medium
developer_type: all
agent: business-analyst
model_tier: mid
tier: core
---

# /dag-plan {task-id}

> Analiza las dependencias del pipeline SDD para una tarea y muestra el DAG de ejecución con camino crítico y estimación de tiempo.

---

## Parámetros

- {task-id} — ID de la tarea (ej: AB#1234) o ruta a spec

---

## Ejecución (4 pasos)

### Paso 1 — Cargar spec

Obtener la especificación de la tarea:
- Buscar en projects/{proyecto}/specs/ el fichero
- Si no existe → error con sugerencia de crear spec

### Paso 2 — Extraer DAG

Parsear las dependencias del pipeline SDD:
- spec-generate → [spec-slice, security-review] (paralelo)
- spec-slice → dev-session
- security-review → dev-session
- dev-session → [unit-tests, integration-tests, docs-update] (paralelo)
- unit-tests → code-review
- integration-tests → code-review
- docs-update → code-review
- code-review → comprehension-report
- comprehension-report → merge

### Paso 3 — Calcular métricas

1. Camino crítico: secuencia más larga
2. Holgura de cada fase
3. Cohortes paralelas: grupos simultáneos
4. Estimación secuencial vs paralelo

Tiempos por fase:
- spec-generate: 5 min
- spec-slice: 8 min
- security-review: 6 min
- dev-session: 15 min
- unit-tests: 4 min
- integration-tests: 6 min
- docs-update: 3 min
- code-review: 5 min
- comprehension-report: 2 min
- merge: 1 min

### Paso 4 — Reportar

Mostrar tabla y DAG con estimaciones

---

## Output

```
═══════════════════════════════════════════════════════════
  DAG Plan — AB#1234 — Crear API de reservas
═══════════════════════════════════════════════════════════

Camino Crítico
  spec-generate → dev-session → [unit|integ|docs] → code-review → report
  Duración: 37 min

Cohortes Paralelas
  Cohorte 1: spec-generate (5 min)
  Cohorte 2: spec-slice [8] + security-review [6] = 8 min paralelo
  Cohorte 3: dev-session (15 min)
  Cohorte 4: unit-tests [4] + integration-tests [6] + docs [3] = 6 min paralelo
  Cohorte 5: code-review (5 min)
  Cohorte 6: comprehension-report (2 min)
  Cohorte 7: merge (1 min)

Estimación
  Secuencial: 55 min
  Paralelo: 37 min
  Mejora: 33% más rápido (18 min ahorrados)

Cuello de botella
  dev-session (15 min) — no paralelizable
  Contribuye 41% del tiempo total
```

---

## Notas

- Las estimaciones son defaults; se actualizan con ejecuciones reales
