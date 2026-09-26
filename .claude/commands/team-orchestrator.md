---
name: team-orchestrator
description: "Multi-team coordination — create teams, assign members, track cross-team dependencies and blockers"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[create|assign|deps|sync|status] {dept} {team} [--critical] [--dept engineering] [--all]"
model_tier: mid
context_cost: medium
tier: core
---

# /team-orchestrator — Coordinación multi-equipo

> Skill: @.opencode/skills/team-coordination/SKILL.md
> Config: @docs/rules/domain/team-structure.md
> Complementa: @.opencode/commands/portfolio-overview.md

Gestiona la estructura organizativa de equipos y departamentos. Detecta
dependencias cross-equipo, bloqueos y problemas de capacidad. Diseñado para
consultoras con 50-500 personas y 10-50 proyectos concurrentes.

Basado en Team Topologies (Skelton & Pais, 2019): stream-aligned, platform,
enabling y complicated-subsystem.

## Subcomandos

### `/team-orchestrator create {dept} {team}`

Crea un nuevo equipo dentro de un departamento:
- Si el departamento no existe, ofrece crearlo
- Genera `teams/{dept}/{team}/team.md` y `deps.md`
- Actualiza `teams/departments.md`
- Output: confirmación + ruta + instrucciones para asignar miembros

### `/team-orchestrator assign {user} {team} [--role contributor] [--capacity 1.0]`

Asigna un miembro a un equipo:
- Verifica que el equipo y el usuario existan
- Añade entrada en `team.md` con handle, role, capacity, projects
- Recalcula capacity_total del equipo
- Advierte si el usuario ya está en otro equipo con capacity > 0.5
- Roles válidos: `contributor`, `pm`, `tech-lead`, `qa`, `architect`

### `/team-orchestrator deps [--critical]`

Visualiza dependencias entre equipos:
- Lee todos los `teams/*/*/deps.md`
- Construye grafo de dependencias (blocking, informational, shared-resource)
- Detecta: bloqueos activos, dependencias circulares, equipos aislados
- `--critical`: solo blocking con status red/amber
- Output: tabla + gráfico ASCII + alertas

### `/team-orchestrator sync`

Verifica coherencia de datos de equipo:
- Todos los miembros tienen perfil válido
- Las deps referencian equipos existentes
- capacity_total = suma FTE real
- velocity_avg actualizada con datos de sprint
- Output: informe de coherencia + correcciones sugeridas

### `/team-orchestrator status [--dept {dept}] [--all]`

Dashboard de salud multi-equipo:
- Por equipo: FTE, velocity, dependency_health, bloqueos activos
- Por departamento: agregación de métricas
- `--all`: todos los departamentos
- Output: tabla resumen + alertas de equipos en riesgo

## Datos almacenados

```
teams/
├── departments.md              # Índice: [{name, lead, teams_count}]
├── engineering/
│   ├── dept.md                 # Misión, responsable, KPIs
│   ├── backend/
│   │   ├── team.md             # Miembros, capacidad, velocity
│   │   └── deps.md             # Dependencias cross-equipo
│   └── frontend/
│       ├── team.md
│       └── deps.md
└── operations/
    ├── dept.md
    └── devops/
        ├── team.md
        └── deps.md
```

## Métricas clave

| Métrica | Umbral sano | Acción si fuera |
|---|---|---|
| Dependency Health | ≥80% deps en green | Resolver bloqueos prioritarios |
| Cross-team WIP | ≤3 items bloqueantes | Reducir WIP o priorizar resolución |
| Sync Overhead | ≤10% capacidad | Simplificar ceremonias cross-team |
| Equipos sin deps declaradas | 0 | Revisar si realmente son independientes |

## Integración

| Comando | Relación |
|---|---|
| `/portfolio-overview` | Incluye datos de equipo en vista portfolio |
| `/capacity-planner` | Usa capacity_total de teams para planificación |
| `/ceo-report` | Agrega métricas de salud inter-equipo |
| `/rbac-manager` | Roles RBAC se asignan por equipo (Era 37) |
| `/enterprise-dashboard` | Dashboard multi-equipo consolidado (Era 41) |
