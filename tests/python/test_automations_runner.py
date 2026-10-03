"""Tests for Task Runner (SE-304)."""

import asyncio
import tempfile
import pytest
from pathlib import Path

from automations.models import ScheduledTask, TaskRun, Schedule
from automations.runner import run_scheduled_task, validate_scoped_approvals


@pytest.fixture
def task():
    return ScheduledTask(
        id="t1",
        name="test-task",
        description="Test task",
        instructions="Write a test report",
        schedule=Schedule(kind="cron", cron="0 9 * * *"),
        always_allowed_tools=["read", "write"],
    )


@pytest.fixture
def output_dir():
    with tempfile.TemporaryDirectory() as td:
        yield td


class TestRunScheduledTask:
    @pytest.mark.asyncio
    async def test_run_without_execution_is_recorded(self, task, output_dir):
        # El runner aún no invoca skill ni agente: nunca 'completed' sin ejecución real.
        run = await run_scheduled_task(task, "manual", output_dir=output_dir)
        assert run.status == "recorded"
        assert run.status != "completed"
        assert run.trigger == "manual"
        assert run.output is not None
        assert Path(run.output).exists()

    @pytest.mark.asyncio
    async def test_output_file_content(self, task, output_dir):
        run = await run_scheduled_task(task, "schedule", output_dir=output_dir)
        content = Path(run.output).read_text(encoding="utf-8")
        assert task.name in content
        assert task.instructions in content
        assert run.id in content
        assert "Recorded, not executed" in content
        assert "Completed" not in content

    @pytest.mark.asyncio
    async def test_run_with_skill(self, task, output_dir):
        task.skill = "my-skill"
        task.agent = "my-agent"
        run = await run_scheduled_task(task, "manual", output_dir=output_dir)
        content = Path(run.output).read_text(encoding="utf-8")
        assert "my-skill" in content
        assert "my-agent" in content

    @pytest.mark.asyncio
    async def test_run_without_skill_or_agent(self, task, output_dir):
        task.skill = None
        task.agent = None
        run = await run_scheduled_task(task, "manual", output_dir=output_dir)
        assert run.status == "recorded"

    @pytest.mark.asyncio
    async def test_unwritable_output_is_error(self, task, output_dir):
        blocker = Path(output_dir) / "file"
        blocker.write_text("x", encoding="utf-8")
        run = await run_scheduled_task(task, "manual", output_dir=str(blocker))
        assert run.status == "error"
        assert run.error


class TestScopedApprovals:
    def test_allowed_tool_passes(self):
        task = ScheduledTask(
            id="t1", name="test", description="", instructions="",
            schedule=Schedule(kind="cron", cron="* * * * *"),
            always_allowed_tools=["read", "write", "glob"],
        )
        assert validate_scoped_approvals(task, "read") is True
        assert validate_scoped_approvals(task, "write") is True
        assert validate_scoped_approvals(task, "glob") is True

    def test_disallowed_tool_fails(self):
        task = ScheduledTask(
            id="t1", name="test", description="", instructions="",
            schedule=Schedule(kind="cron", cron="* * * * *"),
            always_allowed_tools=["read"],
        )
        assert validate_scoped_approvals(task, "bash") is False
        assert validate_scoped_approvals(task, "write") is False

    def test_empty_allowed_tools(self):
        task = ScheduledTask(
            id="t1", name="test", description="", instructions="",
            schedule=Schedule(kind="cron", cron="* * * * *"),
            always_allowed_tools=[],
        )
        assert validate_scoped_approvals(task, "read") is False
