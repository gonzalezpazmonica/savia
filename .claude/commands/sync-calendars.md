---
name: sync-calendars
description: "Sincronizar disponibilidad entre calendarios de dos tenants Microsoft 365"
argument-hint: "[setup|status|conflicts|clean] [--days 14] [--busy]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /sync-calendars — Sincronizacion Multi-Tenant

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`
Spec: `@.opencode/skills/smart-calendar/spec-multi-tenant-sync.md`

## Subcomandos

- **sin argumento**: sincronizar ahora (default)
- **setup**: wizard de configuracion de credenciales (primera vez)
- **status**: estado de ultima sync + conflictos pendientes
- **conflicts**: listar solo conflictos activos entre calendarios
- **clean**: eliminar todos los bloques [Sync] (requiere confirmacion)

## Flujo (sync default)

1. Leer credenciales cifradas de `~/.pm-workspace/calendar-secrets/{slug}/`
2. Pedir passphrase (1 vez por sesion, en memoria)
3. Autenticar con ambos tenants via Graph API (Device Code Flow)
4. Leer eventos de ambos calendarios (ventana: --days, default 14)
5. Filtrar: excluir bloques [Sync] previos (solo eventos reales)
6. Para cada evento real en A sin bloque en B → crear `[Sync] Ocupado`
7. Bloques existentes con horario cambiado → actualizar
8. Eventos cancelados → borrar bloque [Sync] correspondiente
9. Repetir en direccion B → A
10. Detectar conflictos: Hard (ambos confirmados) / Soft (uno tentative)
11. Guardar sync-state.json con timestamp

## Seguridad

- Credenciales: AES-256-CBC, PBKDF2 100K iter, passphrase en memoria
- Solo sincroniza free/busy — NUNCA titulo, asistentes ni contenido
- Bloques creados como Private + sin reminder
- Detalle: `@.opencode/skills/smart-calendar/spec-multi-tenant-security.md`

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 /sync-calendars — Multi-Tenant Sync
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
