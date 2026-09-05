---
layer: peripheral
name: ai-labor-impact
description: Usar cuando se analiza el impacto de la IA en el trabajo del equipo o la organización.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: enterprise-analytics
  savia.maturity: stable
  savia.memory: project
  savia.priority: low
  savia.summary: "Analisis de impacto de IA en roles laborales: auditoria de exposicion, planes de reskilling y previsiones de fuerza laboral. Input: perfil de equipo. Output: informe de exposicion por rol."
  savia.tags: "ai-impact, labor, reskilling, workforce"
---

# Skill: AI Labor Impact

> Prerequisito: @docs/rules/domain/ai-exposure-metrics.md
> Prerequisito: @docs/rules/domain/ai-competency-framework.md

Orquesta el análisis de impacto de la IA en la fuerza laboral: mapeo de
exposición por rol, clasificación de riesgo, planes de reskilling, y
monitorización del Junior Hiring Gap.

## Capacidades

- Auditoría de exposición teórica vs. observada por rol
- Clasificación de riesgo de desplazamiento (alto/medio/bajo)
- Ratio augmentation vs. automation por equipo
- Detección de Junior Hiring Gap
- Generación de planes de reskilling con plazos y recursos
- Simulación de impacto de automatización en capacidad

## Flujo 1 — Exposure Audit (`audit`)

1. Leer `equipo.md` — roles, seniority, headcount
2. Descomponer cada rol en 6-12 tareas O*NET-style
3. Evaluar TE (teórica) y OE (observada) por tarea
4. Calcular scores agregados por rol
5. Clasificar riesgo: 🔴 🟡 🟢
6. Output: `output/analytics/ai-exposure-YYYYMMDD.md`

## Flujo 2 — Reskilling Plan (`reskilling`)

1. Filtrar roles con riesgo 🔴 o 🟡
2. Mapear habilidades actuales → habilidades objetivo
3. Cruzar con `ai-competency-framework.md` (nivel actual → objetivo)
4. Estimar plazo y recursos por persona
5. Output: plan individual + plan equipo

## Flujo 3 — Junior Hiring Gap (`jhg`)

1. Leer histórico de incorporaciones (último año vs. anterior)
2. Calcular JHG index por rol y equipo
3. Alertar si JHG < 0.60 (pipeline roto)
4. Correlacionar con seniority distribution
5. Output: alerta + recomendación

## Flujo 4 — Automation Scenario (`simulate`)

1. Recibir parámetros: rol, % tareas a automatizar
2. Calcular impacto en capacidad del equipo (SP ganados/perdidos)
3. Calcular impacto en headcount necesario
4. Proyectar a 2-4 quarters
5. Output: tabla comparativa antes/después

## Errores

| Error | Acción |
|---|---|
| Equipo sin roles definidos | Solicitar `equipo.md` mínimo |
| Rol sin tareas mapeables | Usar plantilla genérica O*NET |
| Datos de contratación ausentes | Marcar JHG como "sin datos" |

## Seguridad

- Scores de exposición NO son evaluaciones de rendimiento
- Planes de reskilling son confidenciales (no compartir sin consentimiento)
- JHG index es métrica organizacional, no individual
