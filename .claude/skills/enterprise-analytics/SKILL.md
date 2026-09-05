---
layer: peripheral
name: enterprise-analytics
description: "Usar cuando se necesitan métricas SPACE, aggregación de portfolio o forecasting empresarial."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: reporting
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: beta
  savia.memory: project
  savia.priority: medium
  savia.summary: "Metricas empresariales: SPACE, agregacion de portfolio, salud de equipo, matriz de riesgo y forecasting. Para organizaciones con multiples proyectos. Output: dashboard ejecutivo."
  savia.tags: "analytics, space-metrics, portfolio, forecasting"
---

# Skill: Enterprise Analytics

> Prerequisito: @docs/rules/domain/enterprise-metrics.md

Orquesta cálculo de métricas SPACE, agregación portfolio, análisis de salud por equipo, detección de riesgos cross-proyecto, y forecasting.

## Flujo 1 — Portfolio (`portfolio`)

1. Leer data de todos los proyectos (velocity, deployments, lead time)
2. Calcular SPACE_avg por proyecto
3. Agregar portfolio score
4. Generar tabla: proyecto, velocity, health, trend, risk
5. Output: dashboard portfolio + top risks

## Flujo 2 — Team Health (`team-health`)

1. Leer data del equipo: velocidad, WIP, burnout, comunicación
2. Calcular cada dimensión SPACE (0-100)
3. Generar gráfico radar (5 ejes = 5 dimensiones)
4. Identificar fortalezas/debilidades
5. Output: scores + recomendaciones

## Flujo 3 — Risk Matrix (`risk-matrix`)

1. Mapear dependencies entre proyectos
2. Identificar críticas (red status, bloqueadas > 48h)
3. Calcular risk exposure por proyecto
4. Output: matriz 2D (likelihood × impact) + alertas

## Flujo 4 — Forecast (`forecast`)

1. Leer últimos 5 sprints de velocity
2. Calcular optimistic/likely/pessimistic ranges
3. Proyectar 2 quarters adelante
4. Output: gráfico + table con predictions + confidence intervals

## Errores

| Error | Acción |
|---|---|
| Equipo sin datos | Crear proyecto stub; mostrar datos insuficientes |
| Velocity inconsistente | Usar últimas 3 sprints válidos |
| Dependencies circulares | Alertar como CRÍTICO |

## Seguridad

- Métricas pueden ser compartidas (no hay PII)
- Forecasts son internos (no prometer a clientes sin validación)
