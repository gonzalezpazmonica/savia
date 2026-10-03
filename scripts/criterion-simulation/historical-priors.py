#!/usr/bin/env python3
"""historical-priors.py — SPEC-194 Criterion Simulation Layer.

Searches for similar tasks that were reverted or failed in the KG
(knowledge-graph SQLite DB) within a configurable lookback window.

Graceful degradation: returns count 0 if KG is absent or inaccessible,
with `source` telling which case applies. NEVER raises; NEVER makes
network calls. A task without tags matches nothing (source no_tags).

Output: JSON {count: int, priors: [{id, summary, date}], source: str}

Usage:
    python3 scripts/criterion-simulation/historical-priors.py
    python3 scripts/criterion-simulation/historical-priors.py --lookback 60
    python3 scripts/criterion-simulation/historical-priors.py --task-json '{"tags": ["security"]}'
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR  = Path(__file__).resolve().parent
WORKSPACE   = Path(os.environ.get("CLAUDE_PROJECT_DIR", SCRIPT_DIR.parent.parent))
DEFAULT_DB  = Path(os.environ.get(
    "SAVIA_KG_DB",
    str(WORKSPACE / ".savia-kg" / "graph.db")
))


def _env_int(name: str, default: int) -> int:
    """Read an int env var; on invalid value warn on stderr and use default."""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError:
        print(f"historical-priors: {name}={raw!r} no es entero; uso {default}", file=sys.stderr)
        return default


LOOKBACK_DAYS = _env_int("SAVIA_CS_LOOKBACK_DAYS", 90)

def _table_exists(cursor: sqlite3.Cursor, table: str) -> bool:
    cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)
    )
    return cursor.fetchone() is not None


def _column_exists(cursor: sqlite3.Cursor, table: str, column: str) -> bool:
    cursor.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cursor.fetchall())


def _extract_tags(task_context: dict) -> list[str]:
    """Extract searchable tags from task_context for similarity matching."""
    tags: list[str] = []
    for key in ("tags", "categories", "modules"):
        val = task_context.get(key)
        if isinstance(val, list):
            tags.extend(str(t) for t in val)
        elif isinstance(val, str):
            tags.append(val)
    # Also include signal flags as implicit tags
    for flag in ("touches_production", "touches_security", "touches_human_safety"):
        if task_context.get(flag):
            tags.append(flag.replace("touches_", ""))
    return [t.lower() for t in tags if t]


def _like_escape(tag: str) -> str:
    """Escape LIKE wildcards so '_' or '%' in a tag match literally."""
    return tag.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _result(source: str, priors: list | None = None) -> dict:
    """Build the output; `source` says why count is what it is.

    absent     KG file does not exist
    no_table   KG without frame_reaffirmations
    no_tags    task without tags/flags, or table without a tags column:
               there is nothing to compare, so no prior counts as "similar"
    ok         query ran (count may be 0)
    unreadable KG corrupt or unreadable (also warned on stderr)
    """
    priors = priors or []
    return {"count": len(priors), "priors": priors, "source": source}


def get_recent_failed_frames(task_context: dict, lookback_days: int = LOOKBACK_DAYS,
                             db_path: Path | None = None) -> dict:
    """Return {count: int, priors: [{id, summary, date}], source: str} from local KG.

    Searches frame_reaffirmations table for reverted/failed tasks with
    tags matching task_context within lookback_days. Similarity needs tags:
    without them the result is empty (source no_tags), never "any row".

    Graceful: returns count 0 if KG absent, table missing or unreadable.
    """
    db_path = Path(db_path) if db_path is not None else DEFAULT_DB

    if not db_path.exists():
        return _result("absent")

    cutoff = (datetime.now(tz=timezone.utc) - timedelta(days=lookback_days)).isoformat()
    tags   = _extract_tags(task_context)

    try:
        with closing(sqlite3.connect(str(db_path))) as conn:
            cursor = conn.cursor()

            # Graceful: table may not exist yet
            if not _table_exists(cursor, "frame_reaffirmations"):
                return _result("no_table")

            if not tags or not _column_exists(cursor, "frame_reaffirmations", "tags"):
                return _result("no_tags")

            # Match any record whose tags overlap with task_context tags
            query = f"""
                SELECT task_id, reason, ts, verdict_before
                FROM frame_reaffirmations
                WHERE ts >= ?
                  AND verdict_before IN ('FRAME_DOUBT', 'FRAME_REJECT')
                  AND (
                    {" OR ".join(["tags LIKE ? ESCAPE '\\'" for _ in tags])}
                  )
                ORDER BY ts DESC
                LIMIT 10
            """
            like_params = [f"%{_like_escape(t)}%" for t in tags]
            rows = cursor.execute(query, [cutoff] + like_params).fetchall()

        priors = [
            {
                "id":      row[0],
                "summary": row[1] if row[1] else "(no reason recorded)",
                "date":    row[2] if row[2] else "",
            }
            for row in rows
        ]
        return _result("ok", priors)

    except (sqlite3.Error, OSError) as exc:
        # Degradacion declarada: KG ilegible equivale a "sin precedentes",
        # pero queda marcada en source para que el trigger la propague.
        print(f"historical-priors: KG no legible ({exc}); sin precedentes", file=sys.stderr)
        return _result("unreadable")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="SPEC-194 historical-priors — find similar failed frames in KG"
    )
    parser.add_argument(
        "--lookback", type=int, default=LOOKBACK_DAYS,
        help=f"Lookback window in days (default: {LOOKBACK_DAYS})"
    )
    parser.add_argument(
        "--task-json", default=None,
        help="Task context as JSON string (otherwise reads from stdin)"
    )
    parser.add_argument(
        "--db", default=str(DEFAULT_DB),
        help=f"Path to SQLite database (default: {DEFAULT_DB})"
    )
    args = parser.parse_args()

    if args.task_json:
        raw = args.task_json
    elif not sys.stdin.isatty():
        raw = sys.stdin.read().strip()
    else:
        raw = "{}"

    try:
        task_context = json.loads(raw) if raw else {}
    except json.JSONDecodeError as exc:
        print(f"historical-priors: contexto JSON invalido ({exc}); uso contexto vacio", file=sys.stderr)
        task_context = {}

    if not isinstance(task_context, dict):
        print("historical-priors: el contexto no es un objeto JSON; uso contexto vacio", file=sys.stderr)
        task_context = {}

    result = get_recent_failed_frames(task_context, lookback_days=args.lookback,
                                      db_path=Path(args.db))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
