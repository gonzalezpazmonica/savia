"""Automation Scheduler — async loop with catch-up and overlap guard.

Policies:
- run-once-catch-up: on start, executes all due tasks (trigger="catchup")
- skip-on-overlap: if a task is already running, skip
- isolation: each run is an independent asyncio.Task
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Callable, Awaitable, Optional, Set

from .models import ScheduledTask, TaskRun, now_iso
from .store import TaskStore

logger = logging.getLogger("savia.automations")

Runner = Callable[[ScheduledTask, str], Awaitable[TaskRun]]


class AutomationScheduler:
    def __init__(
        self,
        store: TaskStore,
        runner: Runner,
        *,
        tick_seconds: float = 30.0,
        max_concurrent: int = 3,
    ) -> None:
        self.store = store
        self.runner = runner
        self.tick_seconds = tick_seconds
        self.max_concurrent = max_concurrent
        self._task: Optional[asyncio.Task] = None
        self._running_ids: Set[str] = set()
        self._spawned: Set[asyncio.Task] = set()
        self._running = False

    @property
    def running(self) -> bool:
        return self._running

    async def start(self) -> None:
        if self._task is not None:
            return
        self._running = True
        logger.info("scheduler starting (tick=%ss, max_concurrent=%d)",
                     self.tick_seconds, self.max_concurrent)
        self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        self._running = False
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
        for spawned in list(self._spawned):
            spawned.cancel()
            try:
                await spawned
            except asyncio.CancelledError:
                pass
        self._spawned.clear()
        self._running_ids.clear()
        logger.info("scheduler stopped")

    async def _loop(self) -> None:
        try:
            await self._tick(trigger="catchup")
        except Exception:
            logger.exception("scheduler catch-up failed")
        while self._running:
            await asyncio.sleep(self.tick_seconds)
            if not self._running:
                break
            try:
                await self._tick(trigger="schedule")
            except Exception:
                logger.exception("scheduler tick failed")

    async def _tick(self, *, trigger: str) -> None:
        for task in self.store.due():
            if not self._running:
                break
            if task.id in self._running_ids:
                logger.debug("skipping %s — already running", task.id)
                continue
            if len(self._running_ids) >= self.max_concurrent:
                logger.debug("max_concurrent (%d) reached, deferring %s",
                             self.max_concurrent, task.id)
                break
            spawned = asyncio.create_task(
                self._execute_task(task, trigger=trigger)
            )
            self._spawned.add(spawned)
            spawned.add_done_callback(self._spawned.discard)
            spawned.add_done_callback(
                lambda _, tid=task.id: self._running_ids.discard(tid)
            )

    async def _execute_task(self, task: ScheduledTask, *, trigger: str) -> None:
        self._running_ids.add(task.id)
        run_id = str(uuid.uuid4())
        started = now_iso()

        run = TaskRun(
            id=run_id,
            task_id=task.id,
            status="running",
            started_at=started,
            trigger=trigger,
        )
        self.store.add_run(run)

        try:
            result = await self.runner(task, trigger)
            if result is not None:
                result.id = run_id
                result.finished_at = now_iso()
                self.store.update_run(result)
                run.status = result.status
            else:
                run.status = "completed"
                run.finished_at = now_iso()
                self.store.update_run(run)
        except Exception as exc:
            logger.exception("task %s run failed", task.id)
            run.status = "error"
            run.error = str(exc)
            run.finished_at = now_iso()
            self.store.update_run(run)

        fresh = self.store.get(task.id)
        if fresh is not None:
            fresh.run_count += 1
            fresh.last_run = started
            fresh.last_status = run.status
            self.store.save(fresh)

    async def run_now(self, task_id: str) -> Optional[str]:
        task = self.store.get(task_id)
        if task is None:
            return None
        if task.id in self._running_ids:
            return None
        run_id = str(uuid.uuid4())
        self._running_ids.add(task.id)
        try:
            result = await self.runner(task, "manual")
        finally:
            self._running_ids.discard(task.id)
        fresh = self.store.get(task_id)
        if fresh is not None:
            fresh.run_count += 1
            fresh.last_run = now_iso()
            fresh.last_status = result.status if result else "completed"
            self.store.save(fresh)
        return run_id
