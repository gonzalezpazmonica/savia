#!/usr/bin/env python3
"""track.py — SPEC-193 Capa C, Componente 8.

Cross-turn semantic domain tracker. Registers domain classification per turn
in output/cross-turn/{session_id}.jsonl and emits a convergence alert when
>= convergence_minimum of the last N turns touch SENSITIVE_DOMAINS.

CLI:
    python3 track.py --session SESSION_ID --turn TURN_ID --text TEXT
    python3 track.py --session SESSION_ID --report
    python3 track.py --session SESSION_ID --check   # exit 1 if convergence
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Locate workspace root and taxonomy ─────────────────────────────────────

SCRIPT_DIR  = Path(__file__).resolve().parent
WORKSPACE   = Path(os.environ.get("CLAUDE_PROJECT_DIR", SCRIPT_DIR.parent.parent))
TAXONOMY_FILE = SCRIPT_DIR / "sensitive-taxonomy.json"
LOG_DIR     = WORKSPACE / "output" / "cross-turn"
SESSION_ID_RE = re.compile(r"[A-Za-z0-9_-]{1,128}")


def _load_taxonomy() -> dict:
    if TAXONOMY_FILE.exists():
        return json.loads(TAXONOMY_FILE.read_text())
    # Minimal fallback if file missing
    return {
        "domains": {
            "chem-synthesis": {"keywords": ["synthesis", "precursor", "reagent"]},
            "bio-pathogen":   {"keywords": ["pathogen", "culture", "amplification"]},
            "nuclear-fissile": {"keywords": ["nuclear", "fissile", "enrichment"]},
            "radiological":   {"keywords": ["radiological", "isotope", "dispersal"]},
            "weapons":        {"keywords": ["explosive", "detonator", "weapon"]},
        },
        "convergence_minimum": 3,
        "convergence_window":  10,
    }


TAXONOMY = _load_taxonomy()
SENSITIVE_DOMAINS: set[str] = set(TAXONOMY.get("domains", {}).keys())
CONVERGENCE_MINIMUM: int = TAXONOMY.get("convergence_minimum", 3)
CONVERGENCE_WINDOW:  int = TAXONOMY.get("convergence_window",  10)


# ── Domain classifier ────────────────────────────────────────────────────────

def classify_domain(text: str) -> str:
    """Return the most prominent sensitive domain found in text, or 'benign'."""
    t = text.lower()
    hits: dict[str, int] = {}

    for domain, info in TAXONOMY.get("domains", {}).items():
        count = sum(1 for kw in info.get("keywords", []) if kw in t)
        if count:
            hits[domain] = count

    if not hits:
        return "benign"
    return max(hits, key=lambda d: hits[d])


# ── Log helpers ──────────────────────────────────────────────────────────────

def _log_path(session_id: str) -> Path:
    if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
        raise ValueError("invalid session id: %r" % (session_id,))
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    return LOG_DIR / f"{session_id}.jsonl"


def append_turn(session_id: str, turn_id: str, domain: str, text_snippet: str = "") -> None:
    entry = {
        "ts":       datetime.now(timezone.utc).isoformat(),
        "session":  session_id,
        "turn":     turn_id,
        "domain":   domain,
        "snippet":  text_snippet[:80],
    }
    path = _log_path(session_id)
    with path.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def load_recent_turns(session_id: str, n: int = CONVERGENCE_WINDOW) -> list[dict]:
    path = _log_path(session_id)
    if not path.exists():
        return []
    lines = [l for l in path.read_text().splitlines() if l.strip()]
    entries = []
    for line in lines[-n:]:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return entries


# ── Convergence detector ─────────────────────────────────────────────────────

def check_convergence(session_id: str) -> dict:
    """Return convergence analysis for the session's last N turns."""
    recent = load_recent_turns(session_id, CONVERGENCE_WINDOW)
    domains_in_window = [t["domain"] for t in recent]
    sensitive_hits    = [d for d in domains_in_window if d in SENSITIVE_DOMAINS and d != "benign"]
    unique_sensitive  = set(sensitive_hits)
    count             = len(sensitive_hits)

    alert = count >= CONVERGENCE_MINIMUM

    result = {
        "session_id":          session_id,
        "window_size":         len(recent),
        "sensitive_hit_count": count,
        "unique_domains":      sorted(unique_sensitive),
        "convergence_alert":   alert,
        "threshold":           CONVERGENCE_MINIMUM,
        "all_domains":         domains_in_window,
    }

    if alert:
        result["alert_type"] = "convergence_on_sensitive_domain"

    return result


# ── Telemetry writer ─────────────────────────────────────────────────────────

def _write_telemetry(session_id: str, convergence: dict) -> None:
    log_path = os.environ.get(
        "SAVIA_HARDENING_LOG",
        str(WORKSPACE / "output" / "context-hardening-telemetry.jsonl")
    )
    entry = {
        "ts":      datetime.now(timezone.utc).isoformat(),
        "layer":   "C",
        "hook":    "cross-turn-correlation",
        "decision": "CONVERGENCE_ALERT" if convergence["convergence_alert"] else "NO_CONVERGENCE",
        "evidence": json.dumps(convergence),
        "session": session_id,
    }
    Path(log_path).parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a") as f:
        f.write(json.dumps(entry) + "\n")


# ── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="SPEC-193 cross-turn domain tracker")
    parser.add_argument("--session", required=True, help="Session ID")
    parser.add_argument("--turn",    help="Turn ID")
    parser.add_argument("--text",    help="Turn text to classify and record")
    parser.add_argument("--report",  action="store_true", help="Report convergence status")
    parser.add_argument("--check",   action="store_true", help="Check convergence (exit 1 if alert)")
    args = parser.parse_args()
    # The session id becomes a file name under LOG_DIR: never a path.
    if not SESSION_ID_RE.fullmatch(args.session):
        parser.error("invalid --session: expected [A-Za-z0-9_-]{1,128}")

    if args.text and args.turn:
        domain = classify_domain(args.text)
        append_turn(args.session, args.turn, domain, args.text[:80])
        result = check_convergence(args.session)
        print(json.dumps(result))
        _write_telemetry(args.session, result)
        if result["convergence_alert"]:
            print(
                f"[SPEC-193 WARN] Convergence detected on sensitive domain(s): "
                f"{result['unique_domains']} ({result['sensitive_hit_count']}/{CONVERGENCE_WINDOW} turns)",
                file=sys.stderr,
            )

    elif args.report or args.check:
        result = check_convergence(args.session)
        print(json.dumps(result, indent=2))
        if args.check and result["convergence_alert"]:
            sys.exit(1)

    else:
        parser.error("provide --text + --turn, or --report, or --check")


if __name__ == "__main__":
    main()
