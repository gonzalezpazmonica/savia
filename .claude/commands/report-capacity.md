---
name: report-capacity
description: Muestra el estado de capacidades del equipo — disponibilidad, asignación y alertas de sobre-carga.
model_tier: mid
context_cost: medium
tier: core
---

# /report-capacity

Muestra el estado de capacidades del equipo: disponibilidad, asignación y alertas de sobre-carga.

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
/report-capacity [proyecto] [--sprint "Sprint 2026-XX"]
```

## 3. Pasos de Ejecución

1. Usar la skill `capacity-planning` para:
   a. Consultar capacidades vía API:
      `GET {org}/{project}/{team}/_apis/work/teamsettings/iterations/{id}/capacities`
   b. Consultar días off del equipo:
      `GET {org}/{project}/{team}/_apis/work/teamsettings/iterations/{id}/teamdaysoff`
   c. Calcular horas disponibles reales por persona
2. Obtener carga actual: sum(RemainingWork) por persona desde WIQL
3. Calcular utilización: `carga_asignada / horas_disponibles * 100`
4. Generar alertas:
   - 🔴 Sobre-cargado: utilización > 100%
   - 🟡 Al límite: utilización entre 85-100%
   - 🟢 Disponible: utilización < 85%
   - ⚪ Sin datos: sin capacidad configurada en Azure DevOps

## Formato de Salida

```
## Capacity Report — [Proyecto] — [Sprint] — [Fecha]

| Persona | Disponible (h) | Asignado (h) | Restante (h) | Utilización | Estado |
|---------|---------------|--------------|--------------|-------------|--------|
| Juan García | 60h | 52h | 8h | 87% | 🟡 |
| Ana López | 60h | 40h | 20h | 67% | 🟢 |
| Pedro Ruiz | 48h | 55h | -7h | 115% | 🔴 |

**Total equipo:** 168h disponibles / 147h asignadas — Utilización: 88% 🟡

### ⚠️ Alertas
- Pedro Ruiz: SOBRE-CARGADO (+7h). Considerar redistribuir los tasks AB#1234, AB#1235.
- Capacidad no configurada para: [nombre] — Configurar en Azure DevOps.

### Días Off del Sprint
| Persona | Fechas |
|---------|--------|
| Juan García | 2026-03-05 (día festivo) |
```
