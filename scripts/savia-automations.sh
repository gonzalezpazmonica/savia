#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${SAVIA_AUTOMATIONS_DIR:-$ROOT_DIR/.savia/automations}"
PYTHON="${PYTHON:-python3}"

_python() {
  local _cmd="${1:-help}"
  shift || true
  cd "$ROOT_DIR" && SAVIA_CMD="$_cmd" SAVIA_ARGS="$*" "$PYTHON" - "$@" <<'PYEOF'
import json, sys, uuid, os

_cmd = os.environ.get("SAVIA_CMD", "help")
_root = os.environ.get("ROOT_DIR", os.getcwd())
_data = os.environ.get("SAVIA_AUTOMATIONS_DIR",
    os.path.join(_root, ".savia/automations"))
_out = os.environ.get("SAVIA_AUTOMATIONS_OUTPUT",
    os.path.join(_root, "output/automations"))

from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.join(_root, "scripts"))
from automations.models import ScheduledTask, TaskRun, Schedule, now_iso
from automations.store import TaskStore

store = TaskStore(str(_data))

# 'recorded' = instrucciones registradas sin ejecutar skill ni agente; se dice siempre.
NOT_EXECUTED = {"recorded": " (not executed)"}

def fail(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)

def need_task(usage):
    if len(sys.argv) < 2:
        fail(f"Usage: {usage}", 2)
    t = store.get(sys.argv[1])
    if not t:
        fail(f"not found: {sys.argv[1]}")
    return t

def record_run(task_id, result):
    """Persist the run and the task's counters (next_run is recomputed by save)."""
    store.add_run(result)
    fresh = store.get(task_id)
    if fresh is None:
        return
    fresh.run_count += 1
    fresh.last_run = result.started_at
    fresh.last_status = result.status
    store.save(fresh)

def cmd_list():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--enabled", action="store_true")
    p.add_argument("--due", action="store_true")
    a, _ = p.parse_known_args(sys.argv[1:])
    tasks = store.enabled() if a.enabled else store.all()
    if a.due:
        tasks = store.due()
    if not tasks:
        print("(no tasks)")
        return
    for t in tasks:
        state = "\u2713" if t.enabled else "\u2717"
        due = " DUE" if store.is_due(t) else ""
        print(f"[{state}] {t.id}  {t.name}{due}")
        sched = t.schedule.cron or t.schedule.fire_at or "none"
        print(f"     schedule: {t.schedule.kind}={sched}")
        print(f"     last: {t.last_status or 'never'}{NOT_EXECUTED.get(t.last_status, '')}  runs: {t.run_count}  next: {t.next_run or 'none'}")

def cmd_show():
    t = need_task("show <task-id>")
    print(json.dumps(t.to_dict(), indent=2, ensure_ascii=False))

def cmd_create():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--schedule", required=True)
    p.add_argument("--instructions", required=True)
    p.add_argument("--skill")
    p.add_argument("--agent")
    p.add_argument("--description", default="")
    p.add_argument("--timezone", default="local")
    a, _ = p.parse_known_args(sys.argv[1:])
    if store._normalize_cron(a.schedule):
        schedule = Schedule(kind="cron", cron=a.schedule, timezone=a.timezone)
    else:
        schedule = Schedule(kind="once", fire_at=a.schedule, timezone=a.timezone)
    try:
        store.validate_schedule(schedule)
    except ValueError as exc:
        fail(f"invalid schedule: {exc}", 2)
    t = ScheduledTask(
        id=str(uuid.uuid4())[:8],
        name=a.name,
        description=a.description,
        instructions=a.instructions,
        schedule=schedule,
        skill=a.skill,
        agent=a.agent,
        created_at=now_iso(),
        updated_at=now_iso(),
    )
    t.next_run = store._compute_next_run(t.schedule)
    store.save(t)
    print(f"created {t.id}: {t.name}")
    print(f"  next run: {t.next_run}")

def cmd_run():
    t = need_task("run <task-id>")
    import asyncio
    from automations.runner import run_scheduled_task
    result = asyncio.run(run_scheduled_task(
        t, "manual", output_dir=_out))
    record_run(t.id, result)
    print(f"run {result.id}: {result.status}{NOT_EXECUTED.get(result.status, '')}")
    if result.output:
        print(f"  output: {result.output}")
    if result.error:
        print(f"  error: {result.error}")
    if result.status not in ("completed", "recorded"):
        sys.exit(1)

def cmd_run_due():
    """Run all due enabled tasks (the 'loops saltan solos' driver).

    Optionally limit with --max N. Task instructions may select a local LLM
    (--decide llm) — CRIT-001: the runner never falls back to cloud. If the
    local LLM is absent, the task fails open with a recorded error instead of
    contacting a provider.
    """
    max_tasks = sys.maxsize
    if len(sys.argv) >= 3 and sys.argv[1] == "--max":
        try:
            max_tasks = int(sys.argv[2])
        except ValueError:
            fail(f"run-due: --max needs an integer, got '{sys.argv[2]}'", 2)
    due = store.due()
    if not due:
        print("run-due: no due tasks")
        return
    import asyncio
    executed = 0
    recorded = 0
    from automations.runner import run_scheduled_task
    for t in due[:max_tasks]:
        result = asyncio.run(run_scheduled_task(
            t, "schedule", output_dir=_out))
        record_run(t.id, result)  # counters + recomputed next_run
        executed += 1
        if result.status == "recorded":
            recorded += 1
        print(f"run-due {t.id} ({t.name}): {result.status}{NOT_EXECUTED.get(result.status, '')}")
        if result.error:
            print(f"  error: {result.error}")
    print(f"run-due: {executed}/{len(due)} tasks processed, {recorded} recorded without execution")

def cmd_compute():
    """Materialize next_run for every task (normalize + recompute)."""
    updated = 0
    for t in store.all():
        new_next = store._compute_next_run(t.schedule)
        if new_next != t.next_run:
            t.next_run = new_next
            store.save(t)
            updated += 1
        print(f"{t.id} {t.name}: next_run={t.next_run or 'none'}")
    print(f"compute: {updated} tasks updated")

def cmd_disable():
    t = need_task("disable <task-id>")
    t.enabled = False
    store.save(t)
    print(f"disabled {t.id}: {t.name}")

def cmd_enable():
    t = need_task("enable <task-id>")
    t.enabled = True
    store.save(t)
    print(f"enabled {t.id}: {t.name}")

def cmd_delete():
    if len(sys.argv) < 2:
        fail("Usage: delete <task-id>", 2)
    if not store.delete(sys.argv[1]):
        fail(f"not found: {sys.argv[1]}")
    print(f"deleted {sys.argv[1]}")

def cmd_history():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("task_id")
    p.add_argument("--last", type=int, default=10)
    a, _ = p.parse_known_args(sys.argv[1:])
    if not store.get(a.task_id):
        fail(f"not found: {a.task_id}")
    runs = store.list_runs(a.task_id, limit=a.last)
    if not runs:
        print("(no runs)")
        return
    icons = {"completed": "\u2713", "recorded": "\u25A1", "running": "\u25CB", "error": "\u2717", "cancelled": "\u2298"}
    for r in runs:
        icon = icons.get(r.status, "?")
        print(f"[{icon}] {r.id}  {r.status}  {r.trigger}  {r.started_at}{NOT_EXECUTED.get(r.status, '')}")
        if r.error:
            print(f"     error: {r.error}")

def cmd_output():
    if len(sys.argv) < 3:
        fail("Usage: output <task-id> <run-id>", 2)
    run = store.get_run(sys.argv[1], sys.argv[2])
    if not run:
        fail(f"not found: {sys.argv[1]}/{sys.argv[2]}")
    output_path = Path(_out) / run.task_id / f"{run.id}.md"
    if output_path.exists():
        print(output_path.read_text(encoding="utf-8"))
    else:
        fail("(output file not found)")

def cmd_init_defaults():
    tasks = [
        ("morning-brief", "0 9 * * 1-5", "Generate a morning brief: sprint status, blocked items, PRs pending review, team capacity, and daily priorities.", "sprint-management", "azure-devops-operator"),
        ("pr-stale-check", "0 10 * * *", "Check all open PRs. Flag any >48h without activity. Post summary to output/always-on/pr-stale.md.", None, "azure-devops-operator"),
        ("drift-daily", "0 7 * * *", "Run drift audit: detect divergence between docs, config, and code. Report findings.", None, "drift-auditor"),
        ("memory-consolidation", "0 2 * * *", "Consolidate session memories. Detect contradictions, apply TTL, compress old entries.", "savia-memory", "memory-agent"),
        ("weekly-report", "0 8 * * 5", "Generate weekly project status report with sprint metrics, PR activity, team velocity, and key decisions.", "weekly-report", None),
        ("dependency-cve-scan", "0 8 * * 1", "Scan all projects for dependency vulnerabilities. Generate SBOM report.", "dependency-scanner", None),
    ]
    created = 0
    for name, cron, instructions, skill, agent in tasks:
        existing = any(t.name == name for t in store.all())
        if existing:
            print(f"skip {name} (already exists)")
            continue
        t = ScheduledTask(
            id=str(uuid.uuid4())[:8],
            name=name,
            description=f"Auto-generated default: {name}",
            instructions=instructions,
            schedule=Schedule(kind="cron", cron=cron),
            skill=skill,
            agent=agent,
            always_allowed_tools=["read"] if name == "drift-daily" else ["read", "write"],
            created_at=now_iso(),
            updated_at=now_iso(),
        )
        t.next_run = store._compute_next_run(t.schedule)
        store.save(t)
        print(f"created {t.id}: {t.name} (next: {t.next_run})")
        created += 1
    print(f"\n{created} default tasks created")

cmds = {
    "list": cmd_list, "ls": cmd_list,
    "show": cmd_show, "inspect": cmd_show,
    "create": cmd_create, "add": cmd_create,
    "run": cmd_run, "execute": cmd_run,
    "run-due": cmd_run_due, "due-run": cmd_run_due,
    "compute": cmd_compute, "recompute": cmd_compute,
    "disable": cmd_disable, "off": cmd_disable,
    "enable": cmd_enable, "on": cmd_enable,
    "delete": cmd_delete, "rm": cmd_delete,
    "history": cmd_history, "log": cmd_history,
    "output": cmd_output, "out": cmd_output,
    "init-defaults": cmd_init_defaults, "init": cmd_init_defaults,
}
if _cmd in cmds:
    cmds[_cmd]()
else:
    if _cmd not in ("help", "-h", "--help"):
        print(f"unknown command: {_cmd}", file=sys.stderr)
    print("savia-automations.sh -- Automation Scheduler CLI (SE-304)")
    print()
    print("Usage: savia-automations.sh <command> [args]")
    print()
    print("Commands:")
    print("  list [--enabled] [--due]      List scheduled tasks")
    print("  show <task-id>                 Show full task details (JSON)")
    print("  create --name <n> --schedule <cron|ISO datetime> --instructions <text>")
    print("         [--timezone <IANA>] [--skill <s>] [--agent <a>]")
    print("  run <task-id>                  Execute a task immediately")
    print("  run-due [--max N]             Run all due enabled tasks")
    print("  compute                       Recompute next_run for all tasks")
    print("  disable <task-id>              Disable a task")
    print("  enable <task-id>               Enable a disabled task")
    print("  delete <task-id>               Delete a task permanently")
    print("  history <task-id> [--last N]   Show run history")
    print("  output <task-id> <run-id>      Show run output")
    print("  init-defaults                  Create 6 default automation tasks")
    print()
    print("Data: .savia/automations/tasks.json")
    print("Runs: .savia/automations/runs/")
    print("Output: output/automations/")
    print()
    print("Cron times are local wall-clock (like system cron) unless")
    print("--timezone <IANA name> is given; next_run is stored in UTC.")
    if _cmd not in ("help", "-h", "--help"):
        sys.exit(2)
PYEOF
}

_python "$@"
