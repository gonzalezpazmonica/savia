---
name: savia-team
description: >
  Gestionar equipos en Savia Flow: ver miembros, roles, velocidad.
argument-hint: "[show|init] [--team <name>]"
allowed-tools: [Read, Bash, Glob]
model_tier: fast
context_cost: low
tier: core
---

# Savia Team

**Argumentos:** $ARGUMENTS

> Uso: `/savia-team show` | `/savia-team init dev-team`

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md

## Pasos de ejecucion

1. Mostrar banner: `--- Savia Team ---`
2. Verificar company repo configurado
3. Detectar accion:
   - **show [team]**: Leer `teams/{team}/team.md`. Mostrar tabla de miembros
     con handle, nombre, rol, capacidad. Leer velocity.md y mostrar historial.
   - **init <team> [members]**: Ejecutar:
     `bash scripts/savia-flow.sh init-team <team> <members_csv>`
     Format CSV: `handle:name:role,handle:name:role`
4. Si show sin team especificado, listar equipos disponibles en `teams/`
5. Mostrar banner de finalizacion

## Voz Savia (humano)

- Show: "Equipo {name}: {N} miembros, velocidad media {V} SP."
- Init: "Equipo {name} creado con {N} miembros."

## Modo agente

```yaml
status: OK
action: "show|init"
team: "name"
members: N
avg_velocity: N
```

## Restricciones

- Solo lectura en show, no modifica archivos
- Init requiere confirmacion antes de crear

/compact — Ejecuta para liberar contexto antes del siguiente comando
