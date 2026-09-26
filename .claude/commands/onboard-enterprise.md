---
name: onboard-enterprise
description: "Enterprise onboarding at scale — batch import, per-role checklists, knowledge transfer"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[import|checklist|progress|knowledge-transfer] [--file data.csv] [--person nombre] [--project proyecto]"
model_tier: mid
context_cost: medium
tier: core
---

# /onboard-enterprise — Onboarding Empresarial a Escala

> Skill: @.opencode/skills/enterprise-onboarding/SKILL.md
> Config: @docs/rules/domain/onboarding-enterprise.md
> Complementa: @.opencode/commands/team-orchestrator.md

Gestiona onboarding de múltiples personas simultáneamente. Batch CSV import, checklists adaptativos, tracking de progreso, generación automática de Knowledge Transfer.

## Subcomandos

### `/onboard-enterprise import --file data.csv`

Importa lote de personas desde CSV:
- Validar CSV (name, email, role, team, projects, start_date)
- Crear perfiles temporales
- Generar checklists per-role personalizados
- Crear KT docs para cada proyecto
- Output: informe + rutas de archivos + siguiente paso

### `/onboard-enterprise checklist --person nombre`

Muestra checklist personalizado para una persona:
- Leer plantilla de rol (developer, qa, pm, tech-lead)
- Personalizar con datos de equipo/proyectos
- Mostrar estado actual (completado/pendiente)
- Output: checklist markdown con progress indicators

### `/onboard-enterprise progress --person nombre`

Trackea progreso en las 4 fases:
- % completado por fase (Fase 0/1/2/3)
- Detectar bloqueos (items en rojo)
- Calcular días desde start_date
- Alertas si está retrasado
- Output: dashboard de progreso + recomendaciones

### `/onboard-enterprise knowledge-transfer --project proyecto`

Genera Knowledge Transfer document:
- Decision log highlights (últimas 10 decisiones)
- Stack técnico del proyecto
- Primeras tareas asignadas
- Referencias de documentación clave
- Output: KT doc listo para distribuir a T-1 del onboarding

## Datos almacenados

```
output/onboarding/
├── checklists/
│   ├── nombre-developer.md
│   ├── nombre-qa.md
│   └── nombre-pm.md
├── progress/
│   ├── nombre-20260303.md     # Snapshots diarios
│   └── nombre-20260305.md
├── kt/
│   ├── proyecto-nombre.md
│   └── proyecto-otro-nombre.md
├── imports/
│   └── 20260303-batch-import.csv    # Backup del CSV importado
└── sync-YYYYMMDD.md           # Estado consolidado semanal
```

## Métricas de éxito

| Métrica | Umbral | Acción |
|---|---|---|
| Time-to-first-commit | < 2 días | Revisar impedimentos |
| Time-to-first-PR-merged | < 5 días | Asignar segundo buddy |
| Completion-rate (Fase 2) | ≥ 90% | Reducir carga si needed |
| Retention (T+90) | 100% | Feedback loop para mejora |

## Integración

| Comando | Relación |
|---|---|
| `/team-orchestrator assign` | Asignar a equipo tras onboarding completado |
| `/profile-setup` | Setup individual antes del batch import |
| `/sprint-status` | Ver primer sprint de onboarding person |
