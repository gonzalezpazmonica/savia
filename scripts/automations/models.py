"""Automation data models — SE-304.

A scheduled task is a persistent entity with a schedule, instructions, and
optional skill/agent binding. Each run is recorded independently.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, List
from datetime import datetime, timezone


@dataclass
class Schedule:
    kind: str
    cron: Optional[str] = None
    fire_at: Optional[str] = None
    timezone: str = "local"

    def to_dict(self) -> dict:
        d = {"kind": self.kind, "timezone": self.timezone}
        if self.cron:
            d["cron"] = self.cron
        if self.fire_at:
            d["fire_at"] = self.fire_at
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "Schedule":
        return cls(
            kind=d.get("kind", "once"),
            cron=d.get("cron"),
            fire_at=d.get("fire_at"),
            timezone=d.get("timezone", "local"),
        )


@dataclass
class ScheduledTask:
    id: str
    name: str
    description: str
    instructions: str
    schedule: Schedule
    skill: Optional[str] = None
    agent: Optional[str] = None
    workspace: str = ""
    enabled: bool = True
    always_allowed_tools: List[str] = field(default_factory=list)
    run_count: int = 0
    last_run: Optional[str] = None
    last_status: Optional[str] = None
    next_run: Optional[str] = None
    created_at: str = ""
    updated_at: str = ""

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "instructions": self.instructions,
            "schedule": self.schedule.to_dict(),
            "skill": self.skill,
            "agent": self.agent,
            "workspace": self.workspace,
            "enabled": self.enabled,
            "always_allowed_tools": self.always_allowed_tools,
            "run_count": self.run_count,
            "last_run": self.last_run,
            "last_status": self.last_status,
            "next_run": self.next_run,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "ScheduledTask":
        return cls(
            id=d["id"],
            name=d["name"],
            description=d.get("description", ""),
            instructions=d.get("instructions", ""),
            schedule=Schedule.from_dict(d.get("schedule", {"kind": "once"})),
            skill=d.get("skill"),
            agent=d.get("agent"),
            workspace=d.get("workspace", ""),
            enabled=d.get("enabled", True),
            always_allowed_tools=d.get("always_allowed_tools", []),
            run_count=d.get("run_count", 0),
            last_run=d.get("last_run"),
            last_status=d.get("last_status"),
            next_run=d.get("next_run"),
            created_at=d.get("created_at", ""),
            updated_at=d.get("updated_at", ""),
        )


# Estados de un TaskRun. 'completed' exige ejecución real de la skill o el agente;
# 'recorded' = instrucciones registradas en el fichero de salida sin ejecutar nada.
RUN_RUNNING = "running"
RUN_RECORDED = "recorded"
RUN_COMPLETED = "completed"
RUN_ERROR = "error"
RUN_CANCELLED = "cancelled"
RUN_STATUSES = (RUN_RUNNING, RUN_RECORDED, RUN_COMPLETED, RUN_ERROR, RUN_CANCELLED)


@dataclass
class TaskRun:
    id: str
    task_id: str
    status: str
    started_at: str
    finished_at: Optional[str] = None
    trigger: str = "schedule"
    error: Optional[str] = None
    output: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "task_id": self.task_id,
            "status": self.status,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "trigger": self.trigger,
            "error": self.error,
            "output": self.output,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "TaskRun":
        return cls(
            id=d["id"],
            task_id=d["task_id"],
            status=d.get("status", "running"),
            started_at=d.get("started_at", ""),
            finished_at=d.get("finished_at"),
            trigger=d.get("trigger", "schedule"),
            error=d.get("error"),
            output=d.get("output"),
        )


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
