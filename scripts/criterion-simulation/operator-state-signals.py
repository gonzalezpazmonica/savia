#!/usr/bin/env python3
"""operator-state-signals.py — SPEC-194 Criterion Simulation Layer.

Computes operator-state signals from local data only.

Privacy: ZERO external network calls. All data is local.

Returns JSON: {fatigue_score, pressure_score, override_rate, time_band}

Usage:
    python3 scripts/criterion-simulation/operator-state-signals.py
    python3 scripts/criterion-simulation/operator-state-signals.py --operator <id>
    python3 scripts/criterion-simulation/operator-state-signals.py --json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ── Guardrail: no socket calls ever ──────────────────────────────────────────
# This is enforced by the test suite; the script itself never imports socket.

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR    = Path(__file__).resolve().parent
WORKSPACE     = Path(os.environ.get("CLAUDE_PROJECT_DIR", SCRIPT_DIR.parent.parent))
PREFS_FILE    = Path.home() / ".savia" / "preferences.yaml"

# Same log that reaffirmation-log.py writes (and the same env override).
REAFFIRMATION_LOG = Path(os.environ.get(
    "SAVIA_CS_REAFFIRMATION_LOG",
    str(WORKSPACE / "output" / "criterion-simulation" / "reaffirmations.jsonl")
))

# Env configuration
FATIGUE_BAND  = os.environ.get("SAVIA_CS_FATIGUE_HOUR_BAND", "22:00-06:00")
OVERRIDE_LOOKBACK_DAYS = 90


def _parse_hour_band(band: str) -> tuple[int, int]:
    """Parse 'HH:MM-HH:MM' into (start_hour, end_hour) in 24h format."""
    try:
        parts = band.split("-")
        start_hour = int(parts[0].split(":")[0])
        end_hour   = int(parts[1].split(":")[0])
        return start_hour, end_hour
    except (IndexError, ValueError):
        return 22, 6  # fallback


def _is_in_hour_band(hour: int, start: int, end: int) -> bool:
    """True if hour falls within [start, end] wrapping midnight."""
    if start <= end:
        return start <= hour <= end
    # wraps midnight
    return hour >= start or hour <= end


def _hour_distance(a: int, b: int) -> int:
    """Circular distance between two hours (23 and 1 are 2 hours apart)."""
    d = abs(a - b) % 24
    return min(d, 24 - d)


def _compute_fatigue_score(now_hour: int) -> tuple[int, str]:
    """0-30 based on whether current hour is in the atypical band."""
    start, end = _parse_hour_band(FATIGUE_BAND)
    if _is_in_hour_band(now_hour, start, end):
        fatigue = 30
        band    = "atypical"
    elif _hour_distance(now_hour, start) <= 2 or _hour_distance(now_hour, end) <= 2:
        fatigue = 15
        band    = "transition"
    else:
        fatigue = 0
        band    = "normal"
    return fatigue, band


def _compute_pressure_score(deadline_proximity: float | None) -> int:
    """0-20 heuristic from deadline_proximity (0.0-1.0 float from preferences.yaml)."""
    if deadline_proximity is None or not math.isfinite(deadline_proximity):
        return 0
    # Clamp to [0,1]
    p = max(0.0, min(1.0, float(deadline_proximity)))
    return int(round(p * 20))


def _compute_override_rate() -> int:
    """0-20: share of challenges the operator overrode in the last 90 days.

    Reads the reaffirmation log written by reaffirmation-log.py. Within the
    lookback window, override rate = reaffirms / (reaffirms + reframes): a
    reaffirm keeps the challenged frame, a reframe reconsiders it. 100% of
    reaffirms scores 20; only reframes (or no entries) scores 0.
    Graceful: returns 0 if the log is absent or unreadable.
    """
    log_path = REAFFIRMATION_LOG
    if not log_path.exists():
        return 0

    cutoff = datetime.now(tz=timezone.utc) - timedelta(days=OVERRIDE_LOOKBACK_DAYS)

    reaffirms = 0
    decisions = 0
    try:
        with log_path.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    kind = entry.get("type")
                    ts_str = entry.get("ts", "")
                    if kind not in ("reaffirm", "reframe") or not ts_str:
                        continue
                    ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                    if ts.tzinfo is None:
                        ts = ts.replace(tzinfo=timezone.utc)
                except (json.JSONDecodeError, ValueError, AttributeError) as exc:
                    print(f"operator-state-signals: linea ignorada en {log_path.name} ({exc})", file=sys.stderr)
                    continue
                if ts < cutoff:
                    continue
                decisions += 1
                if kind == "reaffirm":
                    reaffirms += 1
    except OSError as exc:
        print(f"operator-state-signals: log no legible ({exc}); override_rate=0", file=sys.stderr)
        return 0

    if decisions == 0:
        return 0
    return int(round(reaffirms / decisions * 20))


def _read_deadline_proximity() -> float | None:
    """Read deadline_proximity from ~/.savia/preferences.yaml. Returns None if absent.

    Accepts a trailing comment, quotes and the es_ES decimal comma ("0,8").
    Only the exact key counts (not deadline_proximity_days); nan/inf -> None.
    """
    if not PREFS_FILE.exists():
        return None
    try:
        with PREFS_FILE.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                parts = line.split(":", 1)
                if len(parts) != 2 or parts[0].strip() != "deadline_proximity":
                    continue
                value = parts[1].split("#", 1)[0].strip().strip("'\"").replace(",", ".")
                proximity = float(value)
                if not math.isfinite(proximity):
                    print(f"operator-state-signals: deadline_proximity={value!r} no es finito; presion=0",
                          file=sys.stderr)
                    return None
                return proximity
    except (OSError, ValueError) as exc:
        print(f"operator-state-signals: deadline_proximity ilegible ({exc}); presion=0", file=sys.stderr)
    return None


def compute_operator_state(operator_id: str = "default") -> dict:
    """Compute operator-state signals. All data is local. No network calls.

    Returns {fatigue_score, pressure_score, override_rate, time_band}.
    Scores:
        fatigue_score  : 0-30 (hour-of-day heuristic)
        pressure_score : 0-20 (deadline_proximity from preferences.yaml)
        override_rate  : 0-20 (local reaffirmation log history)
        time_band      : str (normal | transition | atypical)
    """
    now_hour = datetime.now().hour
    fatigue_score, time_band = _compute_fatigue_score(now_hour)

    deadline_proximity = _read_deadline_proximity()
    pressure_score = _compute_pressure_score(deadline_proximity)

    override_rate = _compute_override_rate()

    return {
        "fatigue_score":  fatigue_score,
        "pressure_score": pressure_score,
        "override_rate":  override_rate,
        "time_band":      time_band,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="SPEC-194 operator-state-signals — local only, no network"
    )
    parser.add_argument(
        "--operator", default="default",
        help="Operator identifier (used for future per-operator history; currently unused)"
    )
    args = parser.parse_args()

    state = compute_operator_state(args.operator)
    print(json.dumps(state))


if __name__ == "__main__":
    main()
