"""tests/scripts/test_skill_detection.py — SPEC-SE-030

pytest tests for:
  - scripts/skill-usage-tracker.py  (tracking invocations)
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# ── Load skill-usage-tracker module ──────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TRACKER_SCRIPT = REPO_ROOT / "scripts" / "skill-usage-tracker.py"


def _load_tracker():
    spec = importlib.util.spec_from_file_location("skill_usage_tracker", TRACKER_SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["skill_usage_tracker"] = mod
    spec.loader.exec_module(mod)
    return mod


tracker_mod = _load_tracker()
track_invocation = tracker_mod.track_invocation


# ── Tests — skill-usage-tracker ───────────────────────────────────────────────

def test_tracker_appends_entry(tmp_path: Path):
    log = tmp_path / "skill-invocations.jsonl"
    track_invocation("spec-driven-development", "/spec-new", "sess-001", log)
    assert log.exists()
    records = [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
    assert len(records) == 1
    r = records[0]
    assert r["skill"] == "spec-driven-development"
    assert r["command"] == "/spec-new"
    assert r["session_id"] == "sess-001"
    assert "ts" in r


def test_tracker_appends_multiple_entries(tmp_path: Path):
    log = tmp_path / "invocations.jsonl"
    for i in range(5):
        track_invocation(f"skill-{i}", f"/cmd-{i}", f"sess-{i}", log)
    records = [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
    assert len(records) == 5


def test_tracker_rolling_window_max_1000(tmp_path: Path):
    log = tmp_path / "invocations.jsonl"
    # Pre-fill with 998 entries
    with log.open("w") as fh:
        for i in range(998):
            fh.write(json.dumps({"ts": "2026-01-01T00:00:00Z", "skill": "old", "command": "/old", "session_id": f"s-{i}"}) + "\n")
    # Add 2 more: total 1000 — no trim
    track_invocation("new-skill", "/new", "new-sess-1", log)
    track_invocation("new-skill", "/new", "new-sess-2", log)
    records = [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
    assert len(records) == 1000


def test_tracker_rolling_window_trims_over_1000(tmp_path: Path):
    log = tmp_path / "invocations.jsonl"
    # Pre-fill with 1000 entries
    with log.open("w") as fh:
        for i in range(1000):
            fh.write(json.dumps({"ts": "2026-01-01T00:00:00Z", "skill": "old", "command": "/old", "session_id": f"s-{i}"}) + "\n")
    # Add one more: should trim to 1000
    track_invocation("newest", "/newest", "newest-sess", log)
    records = [json.loads(l) for l in log.read_text().splitlines() if l.strip()]
    assert len(records) == 1000
    # The newest entry should be the last one
    assert records[-1]["skill"] == "newest"


def test_tracker_creates_parent_dir(tmp_path: Path):
    log = tmp_path / "nested" / "dir" / "invocations.jsonl"
    track_invocation("some-skill", "/some-cmd", "sess-abc", log)
    assert log.exists()


def test_tracker_entry_has_required_fields(tmp_path: Path):
    log = tmp_path / "inv.jsonl"
    track_invocation("my-skill", "/my-cmd", "my-session", log)
    r = json.loads(log.read_text().strip())
    for field in ("ts", "skill", "command", "session_id"):
        assert field in r, f"Missing field: {field}"
