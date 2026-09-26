---
name: report-executive
description: Genera el informe ejecutivo multi-proyecto para dirección en formato Word o PowerPoint.
model_tier: mid
context_cost: medium
tier: core
---

# /report-executive

Genera el informe ejecutivo multi-proyecto para dirección en formato Word o PowerPoint.

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Reporting** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/preferences.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `preferences.language`, `preferences.detail_level`, `preferences.report_format` y `tone.formality`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Uso
```
/report-executive [--format pptx|docx] [--proyectos alpha,beta] [--semana YYYY-WW]
```
Si no se indica formato, generar ambos. Si no se indica semana, usar la semana actual.

## 3. Pasos de Ejecución

1. Para cada proyecto activo (o los indicados):
   a. Leer `projects/<proyecto>/CLAUDE.md` para contexto
   b. Obtener estado del sprint con datos de Azure DevOps
   c. Calcular semáforo de estado según umbrales de `docs/kpis-equipo.md`:
      - 🟢 Verde: velocity ≥ 90% de media, sin bloqueos críticos
      - 🟡 Amarillo: velocity 70-89%, o 1 bloqueo activo
      - 🔴 Rojo: velocity < 70%, o múltiples bloqueos, o sprint goal en riesgo
   d. Identificar riesgos y hitos próximos (milestones del proyecto)

2. Agregar datos de todos los proyectos en un único informe
3. Usar la skill `executive-reporting` para generar el fichero con formato corporativo
4. Guardar en:
   - `output/executive/YYYYMMDD-executive-report.pptx`
   - `output/executive/YYYYMMDD-executive-report.docx`
5. Preguntar si enviar por email via Microsoft Graph

## Secciones del Informe

1. **Portada:** Título, fecha, responsable, logo corporativo
2. **Resumen ejecutivo:** Estado global, semáforo por proyecto, alertas críticas
3. **Por proyecto:**
   - Estado del sprint (semáforo + sprint goal)
   - Velocity trend (gráfico últimos 5 sprints)
   - Hitos próximos (próximas 4 semanas)
   - Riesgos activos y plan de mitigación
4. **Métricas consolidadas:** Tabla comparativa de KPIs entre proyectos
5. **Próximos pasos y decisiones requeridas**
