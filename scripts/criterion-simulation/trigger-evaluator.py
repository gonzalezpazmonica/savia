#!/usr/bin/env python3
"""trigger-evaluator.py — SPEC-194 Criterion Simulation Layer.

Decides whether to activate the criterion-simulation layer based on
task context and operator-state signals.

Input:  JSON task_context dict via --task-json flag or stdin
Output: JSON {activate: bool, score: int 0-100, reasons: [], operator_state: {},
              priors: {}, signals_degraded: []}

Threshold: SAVIA_CS_TRIGGER_THRESHOLD env (default 50).

Usage:
    echo '{"touches_security": true}' | python3 scripts/criterion-simulation/trigger-evaluator.py
    python3 scripts/criterion-simulation/trigger-evaluator.py --task-json '{"touches_production": true}'
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# ── Threshold ─────────────────────────────────────────────────────────────────
DEFAULT_THRESHOLD = 50


def _env_int(name: str, default: int) -> int:
    """Read an int env var; on invalid value warn on stderr and use default."""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError:
        print(f"trigger-evaluator: {name}={raw!r} no es entero; uso {default}", file=sys.stderr)
        return default


TRIGGER_THRESHOLD = _env_int("SAVIA_CS_TRIGGER_THRESHOLD", DEFAULT_THRESHOLD)


# ── Sibling modules ───────────────────────────────────────────────────────────
# The sibling scripts have hyphenated file names, so a plain `import` can never
# find them: they are loaded by path. A failure is reported on stderr instead of
# silently zeroing the signals (that silent fallback hid both modules for months).
# The hook drops stderr, so each failure is also listed in `signals_degraded`.
_DEGRADED: list[str] = []

def _load_sibling(filename: str):
    spec = importlib.util.spec_from_file_location(
        filename.replace("-", "_").removesuffix(".py"), SCRIPT_DIR / filename
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"no se puede cargar {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    compute_operator_state = _load_sibling("operator-state-signals.py").compute_operator_state
except (ImportError, OSError, SyntaxError, AttributeError) as exc:
    print(f"trigger-evaluator: operator-state-signals no disponible ({exc}); senales a 0", file=sys.stderr)
    _DEGRADED.append("operator_state")

    def compute_operator_state(operator_id: str = "default") -> dict:  # type: ignore[misc]
        return {"fatigue_score": 0, "pressure_score": 0, "override_rate": 0, "time_band": "normal"}

try:
    get_recent_failed_frames = _load_sibling("historical-priors.py").get_recent_failed_frames
except (ImportError, OSError, SyntaxError, AttributeError) as exc:
    print(f"trigger-evaluator: historical-priors no disponible ({exc}); sin precedentes", file=sys.stderr)
    _DEGRADED.append("historical_priors")

    def get_recent_failed_frames(task_context: dict, lookback_days: int = 90) -> dict:  # type: ignore[misc]
        return {"count": 0, "priors": [], "source": "unavailable"}


def should_activate(task_context: dict) -> dict:
    """Returns {activate, score 0-100, reasons, operator_state, priors, signals_degraded}.

    Activates if score >= TRIGGER_THRESHOLD (default 50).

    High-impact signals:
        touches_production    +25
        touches_security      +30
        touches_human_safety  +50
        estimated_hours > 16  +15

    Operator state (scaled):
        fatigue_score  * 0.3  (0-30 -> 0-9)
        pressure_score * 0.2  (0-20 -> 0-4)
        override_rate  * 0.2  (0-20 -> 0-4)

    Historical priors (only for tasks with tags/flags; see historical-priors):
        >= 2 similar reverts  +20

    signals_degraded lists the signal sources that failed (module not
    loadable, KG unreadable) and therefore counted as 0.
    """
    score   = 0
    reasons = []

    # ── High-impact signals ───────────────────────────────────────────────────
    if task_context.get("touches_production"):
        score += 25
        reasons.append("production")

    if task_context.get("touches_security"):
        score += 30
        reasons.append("security")

    if task_context.get("touches_human_safety"):
        score += 50
        reasons.append("safety")

    try:
        if float(task_context.get("estimated_hours", 0)) > 16:
            score += 15
            reasons.append("large")
    except (TypeError, ValueError):
        pass

    # ── Operator state signals ────────────────────────────────────────────────
    operator_id = task_context.get("operator", "default")
    state       = compute_operator_state(operator_id)

    score += state.get("fatigue_score", 0)  * 0.3
    score += state.get("pressure_score", 0) * 0.2
    score += state.get("override_rate", 0)  * 0.2

    if state.get("time_band") == "atypical":
        reasons.append("atypical_hour")
    elif state.get("time_band") == "transition":
        reasons.append("transition_hour")

    # ── Historical priors ─────────────────────────────────────────────────────
    lookback = _env_int("SAVIA_CS_LOOKBACK_DAYS", 90)
    priors   = get_recent_failed_frames(task_context, lookback_days=lookback)

    if priors.get("count", 0) >= 2:
        score += 20
        reasons.append(f"{priors['count']} similar reverts")

    degraded = list(_DEGRADED)
    if priors.get("source") == "unreadable" and "historical_priors" not in degraded:
        degraded.append("historical_priors")

    final_score = min(100, int(score))

    return {
        "activate":       final_score >= TRIGGER_THRESHOLD,
        "score":          final_score,
        "reasons":        reasons,
        "operator_state": state,
        "priors":         priors,
        "signals_degraded": degraded,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="SPEC-194 trigger-evaluator — decide if criterion-simulation activates"
    )
    parser.add_argument(
        "--task-json", default=None,
        help="Task context as JSON string (otherwise reads from stdin)"
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
        print(json.dumps({"error": f"invalid JSON: {exc}", "activate": False, "score": 0, "reasons": [], "operator_state": {}, "priors": {}}))
        sys.exit(1)

    if not isinstance(task_context, dict):
        print(json.dumps({"error": "task context must be a JSON object", "activate": False, "score": 0, "reasons": [], "operator_state": {}, "priors": {}}))
        sys.exit(1)

    result = should_activate(task_context)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
