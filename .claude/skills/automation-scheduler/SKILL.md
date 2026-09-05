---
layer: peripheral
name: automation-scheduler
description: "Usar cuando se crean, gestionan o ejecutan automatizaciones programadas: morning briefs, weekly reports, PR stale checks, dependency scans, memory consolidation, drift audits. Triggers: programa una tarea, automatiza esto, crea una automatizacion, scheduled task, ejecuta cada dia, /automations, init-defaults."
metadata:
  savia.maturity: stable
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

## Scoped Approvals

Cada tarea declara always_allowed_tools. El runner rechaza cualquier tool no incluida.

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

savia-automations.sh list [--enabled] [--due]
savia-automations.sh show <task-id>
savia-automations.sh create --name <n> --schedule <cron> --instructions <text>
savia-automations.sh run <task-id>
savia-automations.sh disable|enable <task-id>
savia-automations.sh delete <task-id>
savia-automations.sh history <task-id> [--last N]
savia-automations.sh output <task-id> <run-id>
savia-automations.sh init-defaults
