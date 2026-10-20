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
import os
import signal
import uuid
from pathlib import Path
from typing import Optional

from .models import RUN_ERROR, RUN_FAILED, RUN_RECORDED, RUN_RUNNING, ScheduledTask, TaskRun, now_iso

logger = logging.getLogger("savia.automations.runner")

OUTPUT_DIR = "output/automations"


async def run_scheduled_task(
    task: ScheduledTask,
    trigger: str,
    *,
    output_dir: str = OUTPUT_DIR,
    run_timeout: float = 900.0,
    instructions: Optional[str] = None,
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
            instructions if instructions is not None else task.instructions,
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


CHECK_TIMEOUT_SECONDS = 60.0
CHECK_TAIL_CHARS = 400
FEEDBACK_HEADER = "## Fallo del criterio de exito (reintento)"


async def _run_check(command: str, cwd: Optional[str], timeout: float) -> Optional[str]:
    """Ejecuta un success_check. Devuelve None si pasa (exit 0) o la descripcion del fallo."""
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            cwd=cwd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
    except OSError as exc:
        return f"`{command}`: no se pudo ejecutar ({exc})"
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            proc.kill()
        await proc.wait()
        return f"`{command}`: timeout tras {timeout:g}s"
    if proc.returncode == 0:
        return None
    tail = out.decode("utf-8", "replace").strip()[-CHECK_TAIL_CHARS:]
    detail = f"`{command}`: exit {proc.returncode}"
    return f"{detail}\n{tail}" if tail else detail


async def _failed_checks(task: ScheduledTask, cwd: Optional[str], timeout: float) -> list:
    failures = []
    for command in task.success_checks:
        failure = await _run_check(command, cwd, timeout)
        if failure:
            failures.append(failure)
    return failures


def _retry_input(task: ScheduledTask, failures: list) -> str:
    """Entrada del reintento: las instrucciones originales mas el fallo del check como dato nuevo."""
    feedback = "\n".join(f"- {f}" for f in failures)
    return f"{task.instructions}\n\n{FEEDBACK_HEADER}\n{feedback}\n"


async def run_with_checks(
    task: ScheduledTask,
    trigger: str,
    *,
    output_dir: str = OUTPUT_DIR,
    check_cwd: Optional[str] = None,
    check_timeout: float = CHECK_TIMEOUT_SECONDS,
    executor=None,
) -> TaskRun:
    """SE-445 S4: ejecuta la tarea y evalua sus success_checks; reintenta hasta max_retries.

    Sin success_checks equivale a run_scheduled_task. Si un check falla y quedan reintentos, el
    reintento recibe el fallo como entrada nueva. Repetir con una entrada identica a la del
    intento anterior es el patron prohibido n3 de feedback_root_cause_always: se rechaza.
    """
    executor = executor or run_scheduled_task
    cwd = check_cwd or (task.workspace or None)
    attempts = 0
    instructions = task.instructions
    previous_input: Optional[str] = None
    while True:
        if previous_input is not None and instructions == previous_input:
            run.status = RUN_FAILED
            run.error = (
                f"reintento rechazado tras {attempts} intento(s): entrada identica a la del intento "
                f"anterior (sin cambio no hay motivo para esperar otro resultado). {run.error or ''}"
            ).strip()
            return run
        attempts += 1
        run = await executor(task, trigger, output_dir=output_dir, instructions=instructions)
        run.attempts = attempts
        if run.status == RUN_ERROR or not task.success_checks:
            return run
        failures = await _failed_checks(task, cwd, check_timeout)
        if not failures:
            return run
        run.status = RUN_FAILED
        run.error = "success_check fallido: " + " | ".join(failures)
        if attempts > task.max_retries:
            return run
        previous_input = instructions
        instructions = _retry_input(task, failures)


def validate_scoped_approvals(
    task: ScheduledTask,
    requested_tool: str,
) -> bool:
    if not task.always_allowed_tools:
        return False
    return requested_tool in task.always_allowed_tools
