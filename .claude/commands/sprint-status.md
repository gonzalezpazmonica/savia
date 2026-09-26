---
name: sprint-status
description: Estado del sprint actual — progreso, burndown, alertas.
model_tier: mid
context_cost: medium
complexity_tier: mode1
tier: core
---

# /sprint-status

**Argumentos:** $ARGUMENTS

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 /sprint-status — Estado del sprint actual
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> Si no se indica proyecto, usar el definido en AZURE_DEVOPS_DEFAULT_PROJECT.

## 2. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Sprint & Daily** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `tone.alert_style` y `workflow.daily_time`
4. Si no hay perfil → continuar con comportamiento por defecto

## 3. Verificar prerequisitos

```
Verificando requisitos...
```

Mostrar ✅/❌:
- PAT de Azure DevOps
- Proyecto configurado (CLAUDE.md del proyecto)
- Sprint activo

Si falta el PAT → modo interactivo (pedir y guardar).
Si falta el proyecto → preguntar cuál y cargar su CLAUDE.md.

## 4. Ejecución con progreso

```
📋 Paso 1/3 — Obteniendo sprint actual y work items...
📋 Paso 2/3 — Calculando métricas y distribución...
📋 Paso 3/3 — Evaluando alertas...
```

### Pasos internos

1. Cargar variables de entorno desde `.claude/.env`
2. Leer CLAUDE.md del proyecto indicado
3. Usar la skill `sprint-management` para obtener el sprint actual
4. Obtener work items con: Id, Title, State, AssignedTo, WorkItemType, CompletedWork, RemainingWork, StoryPoints
5. Calcular:
   - Total Story Points planificados vs completados
   - RemainingWork total del equipo
   - Distribución de items por estado (New, Active, Resolved, Closed)
   - Distribución por persona
6. Alertas si:
   - Alguna persona supera WIP_LIMIT_PER_PERSON (default: 2 Active)
   - RemainingWork excede capacity restante del sprint
   - Hay bugs sin asignar

## 5. Mostrar resultado

```
## Sprint Status — [Nombre Sprint] — [Fecha]

**Sprint Goal:** [objetivo del sprint]
**Días restantes:** X | **Capacidad restante:** Xh

### Progreso General
| Métrica | Valor | Estado |
|---------|-------|--------|
| Story Points | X/Y completados | 🟢/🟡/🔴 |
| Remaining Work | Xh | 🟢/🟡/🔴 |
| Items Done | X/Y | 🟢/🟡/🔴 |

### Items por Estado
...

### Carga por Persona
...

### ⚠️ Alertas
...
```

## 6. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /sprint-status — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Sprint {nombre} | {X}% completado | {N} alertas
```
