# Automation Scheduler — Domain Context

## Why this skill exists

Savia opera automatizaciones programadas (morning briefs, weekly reports, PR stale checks, CVE scans, memory consolidation). Sin una infraestructura unificada, cada automatizacion reinventa scheduling, persistencia y overlap-guard. Este skill gestiona el scheduler central de Savia (SE-304): tareas persistentes, ejecucion por cron/one-time, y digest del historial.

## Domain concepts

- **ScheduledTask** — entidad persistente con nombre, instrucciones, schedule (cron/once), skill/agente opcional, y scoped approvals (always_allowed_tools)
- **Schedule** — tipo cron ("0 9 * * 1-5", hora local o zona IANA) o one-time (fire_at ISO); `next_run` en UTC
- **TaskRun** — ejecucion individual de una tarea (status: running/recorded/completed/error/cancelled — `recorded` = registrado sin ejecutar, trigger: schedule/catchup/manual)
- **TaskStore** — persistencia JSON en .savia/automations/tasks.json + runs/{task_id}/
- **AutomationScheduler** — loop asyncrono con catch-up en restart y skip-on-overlap
- **Scoped approvals** — lista de tools permitidas por tarea; el runner rechaza tools no autorizadas
- **Default tasks** — 6 predefinidas: morning-brief, pr-stale-check, drift-daily, memory-consolidation, weekly-report, dependency-cve-scan

## Business rules it implements

- **RN-AUTOM-01**: El scheduler NUNCA ejecuta acciones destructivas sin approval gate (autonomous-safety)
- **RN-AUTOM-02**: Cada tarea declara always_allowed_tools; tools no autorizadas se rechazan en runtime (pendiente: el runner aun no invoca tools y nadie llama a `validate_scoped_approvals`)
- **RN-AUTOM-03**: Runs que exceden el timeout se cancelan automaticamente (pendiente: `run_timeout` se acepta pero no se aplica)
- **RN-AUTOM-04**: El scheduler es opcional — si no corre, Savia funciona normal
- **RN-AUTOM-05**: Las tareas disabled no se ejecutan pero se preservan en el store
- **RN-AUTOM-06**: Un schedule invalido o que nunca dispara se rechaza al crear (exit 2); nunca se guarda sin programar
