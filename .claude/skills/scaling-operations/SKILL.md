---
layer: peripheral
name: scaling-operations
description: Usar cuando se analiza el tier de escala de un servicio o se necesitan optimizaciones de capacidad.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.memory: project
  savia.priority: medium
  savia.summary: "Analiza tier de escalado, benchmarks y recomienda optimizaciones. Para organizaciones en crecimiento. Knowledge search integrado. Output: plan de escalado priorizado."
  savia.tags: "scaling, tier-analysis, benchmark, optimization"
---

# Skill: Scaling Operations

> Prerequisito: @docs/rules/domain/scaling-patterns.md

Orquesta análisis de escala, benchmarking contra tier targets, recomendaciones de optimización, búsqueda transversal de conocimiento.

## Flujo 1 — Analyze (`analyze`)

1. Detectar tier actual: contar proyectos, personas, teams
2. Calcular métricas de escala:
   - Context per-project (KB)
   - Parallel agents habituales
   - Meeting time % capacidad
   - Async vs sync communication ratio
3. Mapear a tier (Small/Medium/Large)
4. Output: current tier + métricas + gaps

## Flujo 2 — Benchmark (`benchmark`)

1. Cargar targets de tier actual
2. Comparar métricas actuales vs targets
3. Identificar discrepancias
4. Generar scorecard: 0-100 por aspecto
5. Output: benchmark table + recomendaciones

## Flujo 3 — Recommend (`recommend`)

1. Ejecutar analyze + benchmark internamente
2. Priorizar optimizaciones (high-impact first)
3. Estimar esfuerzo (story points)
4. Output: action plan ordenado por ROI

**Ejemplos**:
- "Reducir context per-project usando fragments" (2 SP)
- "Implementar team worktrees" (5 SP)
- "Async-first transformation" (13 SP)

## Flujo 4 — Knowledge Search (`knowledge-search`)

1. Full-text search across:
   - decision-log.md
   - ADRs (architecture/)
   - Specs (.spec.md)
   - Rules (domain/)
   - Agent memory
2. Buscar por palabra clave
3. Output: resultados + relevancia score

## Errores

| Error | Acción |
|---|---|
| No hay metrics | Crear stub con ceros |
| Tier indeterminado | Sugerir Small por defecto |
| Knowledge search vacío | Mostrar "sin resultados" |

## Seguridad

- Búsqueda de conocimiento es interna (no exportar)
- Recommendations pueden ser compartidas (son públicas)
