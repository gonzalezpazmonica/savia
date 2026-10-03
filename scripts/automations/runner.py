"""Task Runner — executes scheduled tasks via agent/skill invocation.

Each run:
1. Validates always_allowed_tools (scoped approvals)
2. Writes output to output/automations/{task_id}/{run_id}.md
3. Returns TaskRun with status

Estado real: el runner aún NO invoca la skill ni el agente. Solo registra las
instrucciones, así que el run queda en RUN_RECORDED, nunca RUN_COMPLETED.
Un fallo de E/S (directorio de salida imposible) deja RUN_ERROR.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from pathlib import Path
from typing import Optional

from .models import RUN_ERROR, RUN_RECORDED, RUN_RUNNING, ScheduledTask, TaskRun, now_iso

logger = logging.getLogger("savia.automations.runner")

OUTPUT_DIR = "output/automations"


async def run_scheduled_task(
    task: ScheduledTask,
    trigger: str,
    *,
    output_dir: str = OUTPUT_DIR,
    run_timeout: float = 900.0,
) -> TaskRun:
    run_id = str(uuid.uuid4())
    started = now_iso()

    run = TaskRun(
        id=run_id,
        task_id=task.id,
        status=RUN_RUNNING,
        started_at=started,
        trigger=trigger,
    )

    try:
        task_output_dir = Path(output_dir) / task.id
        task_output_dir.mkdir(parents=True, exist_ok=True)
        output_file = task_output_dir / f"{run_id}.md"
        lines = [
            f"# Run: {task.name}",
            f"",
            f"- **Task**: {task.id}",
            f"- **Run**: {run_id}",
            f"- **Trigger**: {trigger}",
            f"- **Started**: {started}",
            f"- **Skill**: {task.skill or 'none'}",
            f"- **Agent**: {task.agent or 'none'}",
            f"",
            f"## Instructions",
            f"",
            task.instructions,
            f"",
            f"## Status",
            f"",
            f"*Pending execution...*",
        ]
        output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

        scoped = task.always_allowed_tools
        if scoped:
            logger.info("task %s scoped approvals: %s", task.id, scoped)

        run.status = RUN_RECORDED
        run.output = str(output_file)
        run.finished_at = now_iso()

        lines[-1] = "*Recorded, not executed: the runner does not invoke the skill or agent yet.*"
        output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    except asyncio.TimeoutError:
        run.status = RUN_ERROR
        run.error = f"timeout after {run_timeout}s"
        run.finished_at = now_iso()
        logger.error("task %s timed out", task.id)

    except Exception as exc:
        run.status = RUN_ERROR
        run.error = str(exc)
        run.finished_at = now_iso()
        logger.exception("task %s execution failed", task.id)

    return run


def validate_scoped_approvals(
    task: ScheduledTask,
    requested_tool: str,
) -> bool:
    if not task.always_allowed_tools:
        return False
    return requested_tool in task.always_allowed_tools
