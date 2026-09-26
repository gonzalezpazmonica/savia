---
name: sprint-plan
description: Asiste en el Sprint Planning calculando capacity disponible y proponiendo la carga de trabajo.
model_tier: mid
context_cost: medium
tier: core
---

# /sprint-plan

Asiste en el Sprint Planning calculando capacity disponible y proponiendo la carga de trabajo.

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Sprint & Daily** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `tone.alert_style` y `workflow.daily_time`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Uso
```
/sprint-plan [proyecto] [--sprint "Sprint 2026-XX"]
```

## Ejemplos

**✅ Correcto:**
```
/sprint-plan alpha --sprint "Sprint 2026-06"
→ Calcula capacity real, propone 8 PBIs, pide confirmación antes de escribir
```

**❌ Incorrecto:**
```
/sprint-plan alpha
→ Asignar PBIs sin calcular capacity ni pedir confirmación
Por qué falla: Viola regla 3 (confirmar antes de escribir en Azure DevOps)
```

## 3. Pasos de Ejecución

1. Leer `projects/<proyecto>/CLAUDE.md` y `projects/<proyecto>/equipo.md`
2. Obtener el siguiente sprint de Azure DevOps (az boards iteration team list)
3. Consultar capacidades configuradas en Azure DevOps vía API:
   `GET {org}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities`
4. Calcular capacity real por persona:
   ```
   dias_habiles = dias_sprint - dias_festivos - vacaciones
   horas_disponibles = dias_habiles * TEAM_HOURS_PER_DAY * TEAM_FOCUS_FACTOR
   ```
5. Consultar el Backlog: PBIs en estado "Approved" o "Committed" con StoryPoints asignados
6. Aplicar `docs/politica-estimacion.md` para validar estimaciones
7. Proponer asignación equilibrada respetando:
   - Capacidad individual
   - WIP_LIMIT_PER_PERSON
   - Dependencias entre items
   - Specialization (según `equipo.md`)
8. Mostrar propuesta y pedir confirmación antes de crear las capacities en Azure DevOps

## 4. Formato de Salida

```
## Sprint Planning — [Sprint Name] — [Fechas]

### Capacity del Equipo
| Persona | Días disponibles | Horas disponibles | Actividad |
|---------|-----------------|-------------------|-----------|

### PBIs Propuestos para el Sprint
| ID | Título | SP | Asignado a | Estimación |
|----|--------|----|------------|------------|
| AB#XXXX | ... | 5 | Juan García | 16h |

**Total Story Points:** X | **Total horas:** Xh / Xh disponibles
**Sprint Goal propuesto:** [descripción]

¿Confirmar y registrar en Azure DevOps? (s/n)
```
