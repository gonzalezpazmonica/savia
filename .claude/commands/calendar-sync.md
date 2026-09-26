---
name: calendar-sync
description: "Sincronizar calendario Outlook/Teams via Microsoft Graph API"
argument-hint: "[--project nombre] [--days 7]"
allowed-tools: [Read, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /calendar-sync — Sincronizar Calendario

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`

## Prerequisitos

1. `GRAPH_CLIENT_ID` y `GRAPH_TENANT_ID` configurados en pm-config.local.md
2. Token OAuth obtenido (device code flow o browser)
3. Permisos: `Calendars.ReadWrite`, `MailboxSettings.Read`

## Flujo

1. Autenticar con Microsoft Graph (device code flow si primera vez)
2. Leer eventos del calendario (default: proximos 7 dias)
3. Sincronizar con estado local: `data/calendar-cache.json`
4. Detectar conflictos: reuniones superpuestas, sin agenda, en horario no laboral
5. Mostrar resumen: reuniones, huecos, % capacidad productiva

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 /calendar-sync — Sincronizacion Outlook
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
