---
layer: peripheral
name: smart-calendar
description: Usar cuando se gestiona la agenda inteligente con sincronización Outlook/Teams.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: pm-operations
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Gestion inteligente de agenda: sincronizacion Outlook/Teams, planificacion automatica de focus blocks, rebalanceo por prioridades, alertas de conflictos y deadlines. Gestion inteligente de agenda PM: sincronizacion bidireccional con Outlook/Teams, planificacion automatica de trabajo, rebalanceo por prioridades, focus blocks, alertas de conflictos y deadlines. Nada se queda atras."
  savia.tags: "calendar, outlook, teams, focus, scheduling, deadlines, ceremonies"
  savia.user-invocable: True
---

# Skill: Smart Calendar — Gestion Inteligente de Agenda PM

> "Un PM sin calendario sincronizado con su backlog es un PM que apaga fuegos."
> Inspirado en: Reclaim.ai (AI time-blocking), Cal Newport (Deep Work),
> Eisenhower Matrix, PMI Time Management, McKinsey PM playbook.

## Problema que resuelve

El PM gestiona: ceremonias Scrum, 1:1s, steercos, follow-ups con stakeholders,
deadlines de informes, tareas de backlog, y trabajo profundo de analisis.
Sin automatizacion, las tareas sin fecha fija (informes, analisis, specs)
se posponen indefinidamente hasta que son urgentes.

## Arquitectura: 4 capas

### Capa 1 — Sync Engine (Microsoft Graph API)

Sincronizacion bidireccional con Outlook/Teams:
- **Leer**: eventos del calendario, free/busy, categorias, recurrencias
- **Escribir**: crear bloques de focus, mover reuniones, crear eventos
- **Webhook**: notificaciones push cuando cambia el calendario
- **Auth**: OAuth 2.0 con MSAL (delegated permissions, user consent)

Permisos Graph API requeridos:
- `Calendars.ReadWrite` — leer/escribir eventos
- `MailboxSettings.Read` — horario laboral del usuario
- `OnlineMeetings.Read` — detalles de reuniones Teams

Config en `pm-config.local.md`:
```
GRAPH_TENANT_ID    = "..."
GRAPH_CLIENT_ID    = "..."
GRAPH_CALENDAR_SYNC = true
CALENDAR_WORK_START = "09:00"
CALENDAR_WORK_END   = "18:00"
CALENDAR_TIMEZONE   = "Europe/Madrid"
```

### Capa 2 — Work Planner (priorizacion automatica)

Fuentes de trabajo del PM (no solo calendario):
- **Ceremonias**: cadencia Scrum del proyecto (ceremonies.md, sprint dates)
- **1:1s y follow-ups**: recurrencias programadas
- **Deadlines**: informes ejecutivos, steercos, releases, auditorias
- **Backlog PM**: tareas propias (analisis, specs, onboarding, roadmaps)
- **Incidencias**: items bloqueados, escalaciones, hotfixes
- **Digestiones**: reuniones grabadas, documentos pendientes de digerir

Cada item tiene: prioridad (Eisenhower), esfuerzo estimado, deadline, dependencias.

Clasificacion automatica (Eisenhower adaptado para PM):
- **DO** (urgente + importante): bloqueantes, steerco hoy, deadline hoy
- **SCHEDULE** (importante, no urgente): specs, analisis, 1:1s, informes
- **DELEGATE** (urgente, no importante): seguimientos rutinarios, updates
- **ELIMINATE** (ni urgente ni importante): reuniones sin agenda, duplicados

### Capa 3 — Focus Scheduler (bloques de trabajo profundo)

Algoritmo de planificacion diaria:
1. Leer calendario de hoy + semana
2. Identificar huecos libres (no meetings, no lunch)
3. Priorizar items SCHEDULE por deadline proximity + importancia
4. Crear bloques de focus en huecos:
   - Minimo 45 min (menos no permite Deep Work)
   - Maximo 3h (fatiga cognitiva)
   - Etiqueta: "[Savia] Focus: {tarea}"
   - Color: azul oscuro (distinguir de reuniones)
5. Respetar preferencias: no focus antes de daily, no focus despues de las 17h
6. Si cambia el calendario (nueva reunion): rebalancear automaticamente

### Capa 4 — Guardian de Deadlines

Alerta proactiva de lo que se puede quedar atras:
- **Informe semanal**: pendiente de generacion, deadline viernes
- **Steerco**: preparacion necesaria 2 dias antes
- **Sprint review**: datos que recopilar 1 dia antes
- **1:1 follow-up**: acciones comprometidas sin completar
- **Digestion pendiente**: reuniones grabadas sin procesar >48h
- **Backlog PM**: items sin mover >5 dias

Cadencia de alertas:
- **Diaria** (09:00, post-daily): resumen del dia con alertas
- **Semanal** (lunes 08:30): vista de la semana con gaps y riesgos
- **Evento-driven**: si se cancela/mueve reunion, rebalancear

## Comandos

- `/calendar-sync` — sincronizar calendario Outlook/Teams
- `/calendar-plan` — planificar semana con focus blocks automaticos
- `/calendar-today` — vista del dia con alertas y recomendaciones
- `/calendar-rebalance` — rebalancear tras cambio de prioridades
- `/calendar-deadlines` — deadlines proximos con estado de preparacion
- `/calendar-focus` — crear bloque de focus para tarea especifica
- `/sync-calendars` — sincronizar disponibilidad entre 2 tenants Microsoft 365

## Integraciones

- **sprint-management**: fechas de ceremonias → eventos de calendario
- **meeting-digest**: reuniones grabadas → alerta si no digerida en 48h
- **daily-routine**: `/calendar-today` como primer paso del dia
- **overnight-sprint**: no programar tareas autonomas en horas de focus
- **wellbeing-guardian**: alertar si >6h de reuniones/dia (burnout risk)

## Reglas de negocio

1. NUNCA mover una reunion con stakeholder externo sin confirmacion
2. NUNCA programar focus en horario de daily/standup
3. SIEMPRE respetar horario laboral configurado
4. SIEMPRE dejar 15 min entre reuniones (travel time / reset cognitivo)
5. Focus blocks son "tentative" no "busy" (permiten override manual)
6. Si >70% del dia es reuniones: alertar como dia sin capacidad productiva
7. Ceremonias Scrum tienen prioridad sobre focus blocks

## Sistema de Criticidad (Era 120)

El Focus Scheduler usa `criticality_score` (5 dimensiones, WSJF+RICE+Eisenhower)
para decidir que tarea asignar a cada bloque. Spec completo:
`spec-task-criticality.md` | Referencia de frameworks: `spec-criticality-frameworks.md`

Comandos de criticidad:
- `/criticality-dashboard` — panel cross-project P0-P3
- `/criticality-assess {item}` — desglose de 5 dimensiones
- `/criticality-rebalance` — redistribuir carga por criticidad

Integracion: `/calendar-plan` ordena por criticality_score. Items P0 crean
bloques de emergencia (override focus time). Auto-escalado temporal aplica
a `/calendar-deadlines`. Confidence decay limpia backlog automaticamente.
