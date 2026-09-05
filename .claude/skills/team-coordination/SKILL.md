---
layer: peripheral
name: team-coordination
description: "Usar cuando se coordinan múltiples equipos, se asignan miembros o se detectan bloqueantes cross-team."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: pm-operations
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.memory: project
  savia.priority: medium
  savia.summary: "Orquestacion multi-equipo: crear equipos, asignar miembros, detectar bloqueantes cross-team y dependencias. Output: mapa de dependencias + alertas de bloqueo."
  savia.tags: "team, coordination, multi-team, blockers"
---

# Skill: Team Coordination

> Prerequisito: @docs/rules/domain/team-structure.md
> Complementa: @.opencode/skills/capacity-planning/SKILL.md

Orquesta la creación, gestión y coordinación de equipos dentro de departamentos.
Detecta dependencias cross-equipo, bloqueos y problemas de capacidad.

## Flujo 1 — Crear equipo (`create`)

1. Verificar que el departamento existe en `teams/departments.md`
   - Si no existe, preguntar si crear el departamento primero
2. Crear estructura de directorios: `teams/{dept}/{team}/`
3. Generar `team.md` con schema de @team-structure.md:
   - name, department, lead (vacío si no se indica), members: []
   - capacity_total: 0, velocity_avg: 0, sprint_cadence: 2w
4. Generar `deps.md` vacío: `dependencies: []`
5. Actualizar `teams/departments.md` con el nuevo equipo
6. Output: confirmación + ruta + siguiente paso ("asigna miembros con /team-orchestrator assign")

## Flujo 2 — Asignar miembro (`assign`)

1. Verificar que el equipo existe en `teams/{dept}/{team}/team.md`
2. Verificar que el usuario tiene perfil (`.claude/profiles/{user}/` o `active-user.md`)
3. Añadir entrada a `members:` en team.md:
   - handle, role (contributor|pm|tech-lead|qa|architect), capacity (FTE), projects
4. Recalcular `capacity_total` (suma de FTE de todos los miembros)
5. Si el usuario ya está en otro equipo, advertir (multi-equipo permitido si capacity < 1.0)
6. Output: miembro asignado + capacidad total actualizada

## Flujo 3 — Dependencias cross-equipo (`deps`)

1. Leer todos los `teams/*/*/deps.md` recursivamente
2. Construir grafo de dependencias:
   - Nodos = equipos
   - Aristas = dependencias (blocking, informational, shared-resource)
3. Detectar:
   - **Bloqueos activos** (deps con status: red o amber)
   - **Dependencias circulares** (A→B→C→A)
   - **Equipos aislados** (sin ninguna dependencia declarada — posible gap)
4. Si `--critical`: filtrar solo blocking con status red/amber
5. Output: tabla de dependencias + alertas + gráfico ASCII

```
Ejemplo output:
┌─────────┐  blocking  ┌─────────┐
│ Backend │──────────→│ Frontend │
└─────────┘            └─────────┘
     │ shared-resource      │ informational
     ▼                      ▼
┌──────────┐          ┌──────────┐
│ Platform │          │  Mobile  │
└──────────┘          └──────────┘

⚠️ 2 bloqueos activos:
  Backend → Frontend (red): API contracts pendientes
  Platform → Backend (amber): migración K8s en progreso
```

## Flujo 4 — Sincronizar estado (`sync`)

1. Para cada equipo, leer team.md y deps.md
2. Verificar coherencia:
   - ¿Todos los miembros listados tienen perfil?
   - ¿Las deps referencian equipos que existen?
   - ¿La capacity_total coincide con suma de FTE?
3. Recalcular velocity_avg si hay datos de sprint disponibles
4. Actualizar status de deps basándose en última actividad
5. Guardar `output/team-sync-YYYYMMDD.md` con resumen

## Flujo 5 — Dashboard de estado (`status`)

1. Leer todos los equipos (o filtrar por dept si `--dept`)
2. Para cada equipo calcular:
   - Capacidad: total FTE, % utilizado (si hay sprint activo)
   - Salud: dependency_health (% deps en green)
   - Velocidad: velocity_avg + tendencia (↑↗→↘↓)
   - Bloqueos: count de deps blocking con status != green
3. Agregar por departamento si `--all`
4. Output: tabla resumen + alertas

```
Ejemplo output:
══════════════════════════════════════════════
  Multi-Team Status — Engineering Department
══════════════════════════════════════════════

  Team         │ FTE │ Velocity │ Health │ Blocks
  ─────────────┼─────┼──────────┼────────┼───────
  Backend Core │ 4.5 │   42 ↗   │  80%   │   1
  Frontend Web │ 3.0 │   35 →   │ 100%   │   0
  Platform     │ 2.0 │   18 ↘   │  50%   │   2
  Mobile       │ 3.5 │   28 ↑   │ 100%   │   0
  ─────────────┼─────┼──────────┼────────┼───────
  TOTAL        │13.0 │  123     │  83%   │   3

  ⚠️ Platform: 2 bloqueos activos, velocity descendente
```

## Errores

| Error | Acción |
|---|---|
| Departamento no existe | Preguntar si crear. Si sí, crear departments.md |
| Equipo ya existe | Mostrar datos actuales, preguntar si actualizar |
| Miembro sin perfil | Ejecutar `/profile-setup` primero |
| Dependencia circular detectada | Alertar como CRÍTICO, sugerir reunión de resolución |
| deps.md referencia equipo inexistente | Advertir + sugerir actualizar |

## Seguridad

- NUNCA exponer datos personales de miembros en output público
- SIEMPRE usar @handles, no nombres reales en reports exportables
- Datos de equipo en `teams/` — git-tracked (sin datos sensibles)
- Rates/salarios NUNCA en team.md — esos van en `.flow-data/rates.json` (git-ignored)
