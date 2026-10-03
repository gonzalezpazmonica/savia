---
layer: peripheral
name: automation-scheduler
description: "Usar cuando se crean, gestionan o ejecutan automatizaciones programadas: morning briefs, weekly reports, PR stale checks, dependency scans, memory consolidation, drift audits. Triggers: programa una tarea, automatiza esto, crea una automatizacion, scheduled task, ejecuta cada dia, /automations, init-defaults."
metadata:
  savia.maturity: beta
---

# automation-scheduler

Pipeline: LIST, CREATE, TEST, MONITOR, MANAGE.

## Default Tasks

6 tareas predefinidas via savia-automations.sh init-defaults:

| Tarea | Schedule | Skill | Agente |
|-------|----------|-------|--------|
| morning-brief | 0 9 * * 1-5 | sprint-management | azure-devops-operator |
| pr-stale-check | 0 10 * * * | none | azure-devops-operator |
| drift-daily | 0 7 * * * | none | drift-auditor |
| memory-consolidation | 0 2 * * * | savia-memory | memory-agent |
| weekly-report | 0 8 * * 5 | weekly-report | none |
| dependency-cve-scan | 0 8 * * 1 | dependency-scanner | none |

## Schedule

- Cron de 5 campos (min hora dia-mes mes dia-semana): `*`, listas `1,3`, rangos
  `1-5`, pasos `*/15` y `9-17/4`, nombres `jan`, `mon-fri`. Dia-semana 0 y 7 = domingo.
- Si dia-mes y dia-semana estan restringidos, basta con que case uno (semantica de cron).
- Formas humanas: `daily`, `daily HH:MM`, `weekly <dia> HH:MM`.
- Una fecha ISO (`2026-10-05T09:00`) crea una tarea `once`: se ejecuta una vez.
- Las horas son hora local (como el cron del sistema; respeta `TZ`) o la zona IANA
  de `--timezone`. `next_run` se guarda en UTC y se compara como fecha.
- `create` rechaza con exit 2 un cron invalido o que no dispara en 4 anos.
- Tras cambiar el parser, `savia-automations.sh compute` recalcula `next_run`
  de las tareas existentes.

## Scoped Approvals

Cada tarea declara always_allowed_tools. Estado real: el runner aun NO invoca la
skill ni el agente; escribe las instrucciones en el fichero de salida y registra
el run como `recorded`, nunca `completed`. `validate_scoped_approvals` existe pero
nadie la llama.

## Estados de un run

| Estado | Significado | `run` sale con |
|---|---|---|
| `running` | en curso | — |
| `recorded` | instrucciones registradas, sin ejecutar skill ni agente | 0 |
| `completed` | ejecucion real terminada (reservado: hoy ningun runner lo emite) | 0 |
| `error` | fallo, incluido un directorio de salida imposible | 1 |
| `cancelled` | cancelado | 1 |

`run`, `run-due`, `history` y `list` anaden `(not executed)` a todo `recorded`;
`run-due` resume `N/M tasks processed, R recorded without execution`.

## Politicas

- Run-once-catch-up: runs perdidos se ejecutan al reiniciar
- Skip-on-overlap: una tarea en ejecucion no se lanza otra vez
- Max concurrent: 3 runs simultaneos
- Tick interval: 30s por defecto

## Goals durables y heartbeats claimed-due (lección SE-347 / PMA)

- **Goals** (`bash scripts/savia-goals.sh`): objetivo con presupuesto
  (tokens + wall-clock) y estado durable en `~/.savia/goals/`. Regla: SOLO
  `complete` marca éxito (`goal.complete()` es el único final válido);
  `progress` acumula tokens/segundos/continuations; `abandon` para cerrar sin
  éxito. Usa goals en tareas largas (overnight, migraciones, releases).
- **Heartbeats claimed-due** (`savia-goals.sh heartbeat claim-due`): un tick
  pendiente NO se reentrega tras crash (si un runner murió tras marcar
  `last_claimed`, otro runner no lo reclama de nuevo); ticks perdidos
  **coalescen** (solo se entrega el más reciente). Añade heartbeats con
  `heartbeat add --every <secs> --prompt <text>` para tareas de larga duración.

## Data

- Tasks: .savia/automations/tasks.json
- Runs: .savia/automations/runs/{task_id}/
- Output: output/automations/{task_id}/{run_id}.md
- Goals/heartbeats: ~/.savia/goals/ (savia-goals.sh)

## CLI Reference

Exit: 0 ok · 1 tarea/run no encontrado o run fallido · 2 uso incorrecto o schedule invalido.
`SAVIA_AUTOMATIONS_DIR` y `SAVIA_AUTOMATIONS_OUTPUT` cambian datos y salida.

savia-automations.sh list [--enabled] [--due]
savia-automations.sh show <task-id>
savia-automations.sh create --name <n> --schedule <cron|ISO> --instructions <text> [--timezone <IANA>]
savia-automations.sh run <task-id>
savia-automations.sh run-due [--max N]
savia-automations.sh compute
savia-automations.sh disable|enable <task-id>
savia-automations.sh delete <task-id>
savia-automations.sh history <task-id> [--last N]
savia-automations.sh output <task-id> <run-id>
savia-automations.sh init-defaults
