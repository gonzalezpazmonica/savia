---
name: report-hours
description: Genera el informe de imputación de horas del sprint actual o especificado.
model_tier: mid
context_cost: medium
tier: core
---

# /report-hours

Genera el informe de imputación de horas del sprint actual o especificado.

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
/report-hours [proyecto] [--sprint "Sprint 2026-XX"] [--format xlsx|docx]
```
Formato por defecto: `xlsx`.

## 3. Pasos de Ejecución

1. Cargar variables de entorno y leer `projects/<proyecto>/CLAUDE.md`
2. Usar la skill `time-tracking-report`:
   a. Ejecutar WIQL para obtener work items del sprint con campos:
      `CompletedWork`, `RemainingWork`, `OriginalEstimate`, `Activity`, `AssignedTo`
   b. Agrupar por persona → por tipo de actividad (Development, Testing, Documentation, Meeting)
   c. Calcular desviaciones vs estimación original
   d. Cruzar con capacity configurada en Azure DevOps
3. Generar fichero en el formato solicitado usando `scripts/report-generator.js`
4. Guardar en `output/reports/YYYYMMDD-hours-<proyecto>-<sprint>.<ext>`
5. Preguntar si subir a SharePoint (requiere Graph API configurada)

## Campos WIQL Usados
- `System.Id`, `System.Title`, `System.WorkItemType`
- `System.AssignedTo`, `System.State`
- `Microsoft.VSTS.Scheduling.CompletedWork`
- `Microsoft.VSTS.Scheduling.RemainingWork`
- `Microsoft.VSTS.Scheduling.OriginalEstimate`
- `Microsoft.VSTS.Common.Activity`
- `System.IterationPath`

## Formato del Informe Excel (pestañas)

**Pestaña 1 — Resumen**
| Persona | Estimado (h) | Imputado (h) | Desviación | % Utilización |
|---------|-------------|--------------|------------|---------------|

**Pestaña 2 — Detalle por Persona**
| ID | Título | Tipo | Actividad | Estimado | Imputado | Restante | Desviación |

**Pestaña 3 — Por Actividad**
| Actividad | Horas totales | % del total |

**Pestaña 4 — Comparativa Sprints**
Gráfico de barras con las últimas `VELOCITY_AVERAGE_SPRINTS` iteraciones.
