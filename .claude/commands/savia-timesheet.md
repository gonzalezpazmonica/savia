---
name: savia-timesheet
description: >
  Registrar horas y ver timesheet mensual en Savia Flow.
  Entradas almacenadas en team/{handle}/savia-flow/timesheet/.
argument-hint: "[log|view] [--project <name>]"
allowed-tools: [Read, Bash, Glob]
model_tier: mid
context_cost: low
tier: core
---

# Savia Timesheet

**Argumentos:** $ARGUMENTS

> Uso: `/savia-timesheet log` | `/savia-timesheet view` | `/savia-timesheet view 2026-03`

## Contexto requerido

1. @.opencode/skills/company-messaging/references/company-savia-config.md
2. `.opencode/skills/company-messaging/references/flow-schemas.md`

## Pasos de ejecucion

1. Mostrar banner: `--- Savia Timesheet ---`
2. Verificar company repo configurado
3. Detectar accion:
   - **log**: Preguntar proyecto, PBI ID, horas, descripcion.
     Ejecutar: `bash scripts/savia-flow.sh log-time <project> <pbi_id> <hours> <desc>`
   - **view [month]**: Leer fichero timesheet del mes indicado
     (defecto: mes actual). Ruta: `team/{handle}/savia-flow/timesheet/YYYY-MM.md`
     Mostrar tabla con totales de horas por dia y por PBI.
4. Preguntar si sincronizar: `bash scripts/company-repo.sh sync`
5. Mostrar banner de finalizacion

## Voz Savia (humano)

- Log: "Registradas {N}h en {PBI-ID}."
- View: "Aqui tienes tu timesheet de {mes}. Total: {N}h."

## Modo agente

```yaml
status: OK
action: "log|view"
handle: "@handle"
month: "YYYY-MM"
total_hours: N
```

## Restricciones

- Solo el usuario activo puede registrar horas (su propio handle)
- NUNCA modificar entradas existentes sin confirmacion
- Si el PBI no existe, avisar pero permitir log (puede ser externo)

/compact — Ejecuta para liberar contexto antes del siguiente comando
