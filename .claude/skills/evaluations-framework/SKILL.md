---
layer: peripheral
name: evaluations-framework
description: Usar cuando se diseñan o ejecutan evaluaciones de calidad de agentes y prompts.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: reporting
  savia.maturity: stable
  savia.maturity: beta
  savia.priority: medium
  savia.summary: "Framework G-Eval para evaluar calidad de outputs. Tipos: PBI quality, spec quality, estimation accuracy. Output: scores por criterio + tendencias + alertas regresion."
  savia.tags: "evaluations, quality, g-eval, scoring"
---

# Evaluations Framework

## Descripción

Framework sistemático para evaluar la calidad de outputs de agentes, asegurando estándares de excelencia en la entrega de software.

## Tipos de Evaluación

### 1. PBI Decomposition Quality
Evalúa la calidad de la descomposición de historias de usuario:
- ¿Las tareas tienen un tamaño adecuado? (Story Points 2-8)
- ¿Incluye todas las actividades necesarias?
- ¿Las estimaciones son realistas?

**Rubric:**
- Excellent (90-100): Descomposición completa, tamaños consistentes, estimaciones precisas
- Good (70-89): Descomposición adecuada con detalles menores faltantes
- Fair (50-69): Tareas incompletas o mal estimadas
- Poor (<50): Descomposición insuficiente o ilógica

### 2. Spec Generation Quality
Evalúa la calidad de especificaciones técnicas generadas:
- ¿Cubre criterios de aceptación completamente?
- ¿Es verificable y comprobable?
- ¿Es implementable sin ambigüedades?

**Rubric:**
- Excellent (90-100): Especificación clara, completa, verificable
- Good (70-89): Especificación adecuada con gaps menores
- Fair (50-69): Ambigüedades significativas, algunos criterios faltantes
- Poor (<50): Especificación incompleta o confusa

### 3. Estimation Accuracy
Evalúa la precisión de estimaciones tras finalizar sprints:
- Comparación: horas predichas vs. horas reales
- Análisis de desviaciones por tipo de tarea
- Tendencias históricas

**Rubric:**
- Excellent (90-100): Desviación <10%
- Good (70-89): Desviación 10-20%
- Fair (50-69): Desviación 20-35%
- Poor (<50): Desviación >35%

### 4. Review Thoroughness
Evalúa la calidad de revisiones de código/requisitos:
- Cantidad de issues encontrados vs. missed
- Cobertura de áreas críticas
- Profundidad del análisis

**Rubric:**
- Excellent (90-100): >90% issues detectados, análisis profundo
- Good (70-89): 70-90% issues detectados
- Fair (50-69): 50-70% issues detectados
- Poor (<50): <50% issues detectados

### 5. Assignment Quality
Evalúa si las tareas se asignaron a personas idóneas:
- ¿Coincide experiencia con complejidad?
- ¿Hay oportunidades de crecimiento?
- ¿Están balanceadas las cargas?

**Rubric:**
- Excellent (90-100): Asignación óptima, desarrollo continuo
- Good (70-89): Asignación apropiada
- Fair (50-69): Algunos mismatches
- Poor (<50): Múltiples mismatches graves

## Proceso de Evaluación

1. **Define eval set**: Selecciona items a evaluar (PBIs, specs, sprints, etc.)
2. **Run agent**: Ejecuta el agente o process a evaluar
3. **Score outputs**: Aplica rubric correspondiente
4. **Analyze patterns**: Identifica tendencias y áreas de mejora
5. **Improve**: Ajusta prompts, skills, procesos

## Almacenamiento

Evaluaciones se guardan en:
```
data/evals/{eval-name}/
├── config.json (definición y rubric)
├── results/
│   └── {timestamp}.json (scores, feedback)
└── trends/
    └── {eval-name}-trends.json (análisis histórico)
```

## Automatización

- **Scheduled runs**: Ejecutarse en horarios definidos
- **Trend analysis**: Detectar patrones a lo largo del tiempo
- **Regression detection**: Alertas si scores caen >10%
- **Reports**: Generación automática de reportes

## Integración

Las evaluaciones se integran con el workflow de sprints, refinamiento y planning para mejora continua basada en datos.
