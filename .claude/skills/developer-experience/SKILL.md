---
layer: peripheral
name: developer-experience
description: Usar cuando se mide o mejora la experiencia de desarrollo del equipo.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Framework DX Core 4 (Speed, Effectiveness, Quality, Impact) y metricas SPACE para medir experiencia del desarrollador. Output: scorecard DX + recomendaciones priorizadas."
  savia.tags: "dx, developer-experience, space, core4"
---

# Developer Experience (DX)

Marco de referencia para medir y mejorar la experiencia del desarrollador usando metodologías de vanguardia.

## §1 DX Core 4 Framework

Cuatro pilares fundamentales de la experiencia del desarrollador (referencia: DX 2024):

### Speed (Velocidad)
- **Métrica**: Número de diffs/cambios por ingeniero en un período
- **Objetivo**: Maximizar velocidad de entrega sin sacrificar calidad
- **Medición**: Commits por semana, tiempo de ciclo PR, duración deploy

### Effectiveness (Efectividad)
- **Métrica**: Proporción de objetivos alcanzados vs planificados
- **Objetivo**: Claridad en requerimientos y alineación de entrega
- **Medición**: User stories completadas, acceptance criteria met, scope creep

### Quality (Calidad)
- **Métrica**: Tasa de defectos, MTTR (Mean Time To Repair)
- **Objetivo**: Código confiable y procesos robustos de testing
- **Medición**: Bugs en producción, fallos detectados en QA, cobertura de tests

### Impact (Impacto)
- **Métrica**: Valor de negocio entregado al usuario final
- **Objetivo**: Asegurar que el trabajo importa
- **Medición**: Features activadas, adopción usuario, ROI, customer satisfaction

## §2 SPACE Framework

Cinco dimensiones complementarias para una visión holística:

- **Satisfaction**: Satisfacción y bienestar del equipo
- **Performance**: Rendimiento y velocidad de entrega
- **Activity**: Nivel de actividad y engagement
- **Communication**: Claridad y efectividad de comunicación
- **Efficiency**: Eficiencia de procesos y herramientas

Medir al menos 3 dimensiones usando métrica combinada cuantitativa + cualitativa.

## §3 Cognitive Load

Tres tipos de carga cognitiva (Sweller):

### Intrinsic Cognitive Load
- Complejidad inherente del problema
- Reducir: Descomponer tareas, abstraer detalles innecesarios

### Extraneous Cognitive Load
- Distracción causada por herramientas, procesos o comunicación
- Reducir: Simplificar workflow, automatizar tareas rutinarias, mejorar UX

### Germane Cognitive Load
- Esfuerzo productivo en resolver el problema
- Maximizar: Documentación clara, ejemplos, reutilización de código

**Conexión Team Topologies**: Alineación de equipos reduce cognitive load interdependencias.

## §4 Feedback Loops

La velocidad del feedback es central en DX. Ciclos rápidos = mejor experiencia.

### Métricas Clave
- **PR Review Time**: Tiempo promedio desde PR abierto hasta revisión
- **CI/CD Duration**: Tiempo total de pipeline (build, test, deploy)
- **Error Detection Time**: Cuánto tarda en detectarse un fallo en producción
- **Deploy Frequency**: Frecuencia de deployments a producción

Objetivo: Ciclos de feedback sub-minuto donde sea posible.

## §5 Survey Design

Encuestas validadas de DX (recomendación trimestral):

### Características
- Escala Likert de 5 puntos (1=Totalmente en desacuerdo, 5=Totalmente de acuerdo)
- Preguntas validadas en investigación académica
- Anonimato crítico para respuestas honestas
- 12-15 preguntas cuantitativas + 3 abiertas
- Tiempo estimado: 8-12 minutos

### Frecuencia Recomendada
- Trimestral como línea base
- Post-implementación de cambios mayor (análisis antes/después)
- Mínimo 50% participación para validez

## §6 Actionable Metrics

Cada métrica debe vincularse a acción. No medir por medir.

### Estructura de Métrica Accionable
1. **Métrica**: Qué se mide
2. **Threshold**: Valor objetivo
3. **Trigger**: Cuándo tomar acción (umbral rojo)
4. **Acción**: Qué hacer cuando se dispara
5. **Medición de Éxito**: Cómo validar que la acción funcionó

Ejemplo: Si PR review time > 24h → asignar reviewer automáticamente → meta: <4h

## §7 Integración en pm-workspace

DX metrics se alimentan de múltiples fuentes:

### Agent Trace Integration
- Fallos de comando → Friction points
- Tasa de éxito → Tool satisfaction proxy
- Latencia de ejecución → Performance baseline

### Flow Metrics Integration
- Tiempo en diferentes estados (drafting, review, execution)
- Bottlenecks identificables → Recomendaciones
- Trend analysis → Sprint-to-sprint improvement

### Spec Status Integration
- Tiempo de ciclo spec-generate → spec-verify
- Complejidad de specs (dependencies, files affected)
- Rework ratio → Quality signal

### Commands
- `/dx-survey`: Recolectar feedback cualitativo
- `/dx-dashboard`: Visualizar métricas automatizadas
- `/dx-recommendations`: Análisis de friction points
