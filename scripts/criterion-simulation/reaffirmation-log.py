#!/usr/bin/env python3
"""reaffirmation-log.py — SPEC-194 Criterion Simulation Layer.

Records conscious human reaffirmations or reframes of a challenged task.

Subcommands:
    reaffirm --task ID --reason STR     Confirm the frame with a reason (>= 20 chars)
    reframe  --task ID --new-statement STR  Redefine the problem statement

Exit codes:
    0 — success
    1 — usage/IO error
    2 — validation failure (reason too short, missing required argument)

Output log: output/criterion-simulation/reaffirmations.jsonl

Usage:
    python3 scripts/criterion-simulation/reaffirmation-log.py reaffirm \
        --task TASK-123 --reason "I reviewed dependencies; the approach is sound."
    python3 scripts/criterion-simulation/reaffirmation-log.py reframe \
        --task TASK-123 --new-statement "Scope down to core auth only, defer bulk import."
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE  = Path(os.environ.get("CLAUDE_PROJECT_DIR", SCRIPT_DIR.parent.parent))
LOG_PATH   = Path(os.environ.get(
    "SAVIA_CS_REAFFIRMATION_LOG",
    str(WORKSPACE / "output" / "criterion-simulation" / "reaffirmations.jsonl")
))

MIN_REASON_LEN = 20


def _append_entry(entry: dict) -> None:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def _require_task(task_id: str) -> None:
    if not task_id.strip():
        print("Error: --task cannot be empty.", file=sys.stderr)
        sys.exit(2)


def cmd_reaffirm(task_id: str, reason: str, operator: str = "default") -> None:
    """Register a conscious reaffirmation of the task frame."""
    _require_task(task_id)
    # Whitespace padding is not deliberate thought: measure the trimmed reason
    # with internal runs of blanks collapsed.
    meaningful = " ".join(reason.split())
    if len(meaningful) < MIN_REASON_LEN:
        print(
            f"Error: --reason must be >= {MIN_REASON_LEN} characters "
            f"(got {len(meaningful)} without padding). Reaffirmation requires deliberate thought.",
            file=sys.stderr,
        )
        sys.exit(2)

    entry = {
        "type":     "reaffirm",
        "task_id":  task_id.strip(),
        "ts":       datetime.now(tz=timezone.utc).isoformat(),
        "operator": operator,
        "reason":   reason,
    }
    _append_entry(entry)
    print(json.dumps({"status": "ok", "type": "reaffirm", "task_id": task_id}))


def cmd_reframe(task_id: str, new_statement: str, operator: str = "default") -> None:
    """Register a redefinition of the problem statement."""
    _require_task(task_id)
    if not new_statement.strip():
        print(
            "Error: --new-statement cannot be empty.",
            file=sys.stderr,
        )
        sys.exit(2)

    entry = {
        "type":          "reframe",
        "task_id":       task_id.strip(),
        "ts":            datetime.now(tz=timezone.utc).isoformat(),
        "operator":      operator,
        "new_statement": new_statement,
    }
    _append_entry(entry)
    print(json.dumps({"status": "ok", "type": "reframe", "task_id": task_id}))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="SPEC-194 reaffirmation-log — record conscious frame confirmations"
    )
    parser.add_argument(
        "--operator", default=os.environ.get("SAVIA_OPERATOR", "default"),
        help="Operator identifier"
    )
    subparsers = parser.add_subparsers(dest="command")

    # reaffirm subcommand
    p_reaffirm = subparsers.add_parser("reaffirm", help="Confirm frame with deliberate reason")
    p_reaffirm.add_argument("--task", required=True, help="Task identifier")
    p_reaffirm.add_argument(
        "--reason", required=True,
        help=f"Why this frame is correct (>= {MIN_REASON_LEN} chars required)"
    )

    # reframe subcommand
    p_reframe = subparsers.add_parser("reframe", help="Redefine the problem statement")
    p_reframe.add_argument("--task", required=True, help="Task identifier")
    p_reframe.add_argument("--new-statement", required=True, dest="new_statement",
                           help="The new/revised problem statement")

    args = parser.parse_args()

    if args.command == "reaffirm":
        cmd_reaffirm(args.task, args.reason, args.operator)
    elif args.command == "reframe":
        cmd_reframe(args.task, args.new_statement, args.operator)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
