"""Persistent installation states and crash recovery (SE-399 section 5)."""
from __future__ import annotations

TRANSITIONS = {
    "discovery": {"planning", "failed"},
    "planning": {"ready", "failed"},
    "ready": {"installing", "failed"},
    "installing": {"verifying", "failed", "rolling-back"},
    "verifying": {"completed", "completed-with-warnings", "failed", "rolling-back"},
    "failed": {"rolling-back", "repair-required"},
    "rolling-back": {"rolled-back", "partially-rolled-back"},
    "partially-rolled-back": {"repair-required", "rolling-back"},
    "repair-required": {"installing", "rolling-back"},
    "completed": set(),
    "completed-with-warnings": {"repair-required"},
    "rolled-back": set(),
}
IN_FLIGHT = {"installing", "verifying", "rolling-back"}


def transition(current: str, nxt: str) -> str:
    if current not in TRANSITIONS:
        raise ValueError(f"unknown state: {current}")
    if nxt not in TRANSITIONS[current]:
        raise ValueError(f"illegal transition {current} -> {nxt}")
    return nxt


def recovery_options(state: str) -> list:
    """After a crash: never assume completion. In-flight states offer resume/rollback/inspect; states that can roll back offer rollback."""
    if state in IN_FLIGHT:
        return ["resume", "rollback", "inspect"]
    if "rolling-back" in TRANSITIONS.get(state, ()):
        return ["rollback", "inspect"]
    return ["inspect"]
