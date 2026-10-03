"""Task Store — JSON persistence for scheduled tasks and runs.

.savia/automations/
  tasks.json            — array of ScheduledTask
  config.yaml           — global config (tick_seconds, max_concurrent)
  runs/{task_id}/
    {run_id}.json       — individual run records
"""

from __future__ import annotations

import json
import os
import uuid
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, List

from . import cron
from .models import ScheduledTask, TaskRun, Schedule, now_iso


class TaskStore:
    def __init__(self, data_dir: str = ".savia/automations") -> None:
        self.data_dir = Path(data_dir)
        self.tasks_file = self.data_dir / "tasks.json"
        self.runs_dir = self.data_dir / "runs"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.runs_dir.mkdir(parents=True, exist_ok=True)
        if not self.tasks_file.exists():
            self.tasks_file.write_text("[]", encoding="utf-8")

    def _load_tasks(self) -> list[dict]:
        try:
            raw = self.tasks_file.read_text(encoding="utf-8")
            data = json.loads(raw)
            return data if isinstance(data, list) else []
        except (json.JSONDecodeError, FileNotFoundError):
            return []

    def _save_tasks(self, tasks: list[dict]) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        tmp = self.tasks_file.with_name(f".tasks.json.{os.getpid()}.tmp")
        tmp.write_text(
            json.dumps(tasks, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        tmp.replace(self.tasks_file)

    def all(self) -> List[ScheduledTask]:
        return [ScheduledTask.from_dict(d) for d in self._load_tasks()]

    def enabled(self) -> List[ScheduledTask]:
        return [t for t in self.all() if t.enabled]

    def due(self, now: Optional[str] = None) -> List[ScheduledTask]:
        return [t for t in self.enabled() if self.is_due(t, now)]

    @staticmethod
    def is_due(task: ScheduledTask, now: Optional[str] = None) -> bool:
        """Compare as datetimes: ISO strings with different offsets don't sort."""
        next_run = parse_datetime(task.next_run or "", "UTC")
        ref = parse_datetime(now, "UTC") if now else datetime.now(timezone.utc)
        return bool(next_run and ref and next_run <= ref)

    def get(self, task_id: str) -> Optional[ScheduledTask]:
        for t in self.all():
            if t.id == task_id:
                return t
        return None

    def save(self, task: ScheduledTask) -> None:
        tasks = self._load_tasks()
        task.updated_at = now_iso()
        if not task.created_at:
            task.created_at = task.updated_at
        if task.schedule.kind == "once" and task.last_run:
            task.next_run = None  # a one-shot task fires once
        else:
            task.next_run = self._compute_next_run(task.schedule)
        d = task.to_dict()
        for i, existing in enumerate(tasks):
            if existing.get("id") == task.id:
                tasks[i] = d
                break
        else:
            tasks.append(d)
        self._save_tasks(tasks)

    def delete(self, task_id: str) -> bool:
        tasks = self._load_tasks()
        new_tasks = [t for t in tasks if t.get("id") != task_id]
        if len(new_tasks) == len(tasks):
            return False
        self._save_tasks(new_tasks)
        return True

    def add_run(self, run: TaskRun) -> None:
        run_dir = self.runs_dir / run.task_id
        run_dir.mkdir(parents=True, exist_ok=True)
        run_file = run_dir / f"{run.id}.json"
        run_file.write_text(
            json.dumps(run.to_dict(), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    def update_run(self, run: TaskRun) -> None:
        self.add_run(run)

    def get_run(self, task_id: str, run_id: str) -> Optional[TaskRun]:
        run_file = self.runs_dir / task_id / f"{run_id}.json"
        if not run_file.exists():
            return None
        try:
            return TaskRun.from_dict(
                json.loads(run_file.read_text(encoding="utf-8"))
            )
        except (json.JSONDecodeError, KeyError):
            return None

    def list_runs(self, task_id: str, limit: int = 100) -> List[TaskRun]:
        run_dir = self.runs_dir / task_id
        if not run_dir.is_dir():
            return []
        runs = []
        for f in sorted(run_dir.iterdir(), reverse=True):
            if not f.name.endswith(".json"):
                continue
            try:
                runs.append(
                    TaskRun.from_dict(
                        json.loads(f.read_text(encoding="utf-8"))
                    )
                )
            except (json.JSONDecodeError, KeyError):
                continue
        return runs[:limit]

    _HUMAN_DAYS = {
        "sun": 0, "sunday": 0, "mon": 1, "monday": 1, "tue": 2, "tuesday": 2,
        "wed": 3, "wednesday": 3, "thu": 4, "thursday": 4, "fri": 5, "friday": 5,
        "sat": 6, "saturday": 6,
    }

    def _normalize_cron(self, cron: str) -> Optional[str]:
        """Normalize human cron notation to 5-field cron.

        Supported human forms (case-insensitive):
          daily HH:MM            → MM HH * * *
          daily                 → 0 8 * * *   (default 08:00)
          weekly DOW HH:MM      → MM HH * * DOW
          weekly HH:MM          → 0 HH * * *
        Any 5-field cron passes through; cron.parse validates it.
        Returns None if unparseable.
        """
        if not cron:
            return None
        raw = cron.strip().lower()
        parts = raw.split()
        # Already standard 5-field? Pass through.
        if len(parts) == 5:
            return " ".join(parts)
        def hhmm(tok: str) -> tuple[int, int]:
            hh, mm = tok.split(":")
            return int(hh), int(mm)

        # Unrecognised words or extra tokens → None, never a silent default.
        try:
            if parts[0] == "daily" and len(parts) <= 2:
                if len(parts) == 2:
                    hh, mm = hhmm(parts[1])
                    return f"{mm} {hh} * * *"
                return "0 8 * * *"  # daily default 08:00
            if parts[0] == "weekly" and len(parts) <= 3:
                if len(parts) >= 2 and parts[1] in self._HUMAN_DAYS:
                    dow = self._HUMAN_DAYS[parts[1]]
                    if len(parts) == 3:
                        hh, mm = hhmm(parts[2])
                        return f"{mm} {hh} * * {dow}"
                    return f"0 8 * * {dow}"
                if len(parts) == 2:
                    hh, mm = hhmm(parts[1])
                    return f"{mm} {hh} * * *"
                if len(parts) == 1:
                    return "0 8 * * *"
        except (ValueError, IndexError):
            return None
        return None

    def validate_schedule(self, schedule: Schedule) -> None:
        """Raise ValueError when the schedule can never produce a run."""
        if schedule.kind == "once":
            if parse_datetime(schedule.fire_at or "", schedule.timezone) is None:
                raise ValueError(f"invalid fire_at: '{schedule.fire_at}'")
            return
        normalized = self._normalize_cron(schedule.cron or "")
        if not normalized:
            raise ValueError(f"invalid cron: '{schedule.cron}'")
        spec = cron.parse(normalized)
        now = datetime.now(timezone.utc)
        if cron.next_fire(spec, now, schedule.timezone) is None:
            raise ValueError(f"cron never fires: '{schedule.cron}'")

    def _compute_next_run(
        self, schedule: Schedule, now: Optional[datetime] = None
    ) -> Optional[str]:
        """Next fire time after ``now`` as a UTC ISO string, or None.

        Cron fields are wall-clock times in ``schedule.timezone`` (``local``
        by default, like system cron). ``now`` is injectable for tests.
        """
        if schedule.kind == "once":
            fire = parse_datetime(schedule.fire_at or "", schedule.timezone)
            return fire.isoformat() if fire else None
        normalized = self._normalize_cron(schedule.cron) if schedule.cron else None
        if not normalized:
            return None
        ref = now or datetime.now(timezone.utc)
        try:
            when = cron.next_fire(cron.parse(normalized), ref, schedule.timezone)
        except ValueError:
            return None
        return when.isoformat() if when else None


def parse_datetime(value: str, tz: str = "local") -> Optional[datetime]:
    """Parse an ISO datetime to aware UTC; naive values are read in ``tz``."""
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.strip())
    except ValueError:
        return None
    if dt.tzinfo is None:
        if tz in ("", "local"):
            dt = dt.astimezone()
        else:
            from zoneinfo import ZoneInfo
            dt = dt.replace(tzinfo=ZoneInfo(tz))
    return dt.astimezone(timezone.utc)
