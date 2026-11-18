"""Tests for SPEC-188 Phase 4 MVP

Covers:
- diagnostic-metrics: --record appends entry to JSONL
- diagnostic-metrics: --report calculates accuracy_rate correctly
- diagnostic-metrics: JSONL append-only (2 records -> 2 lines)
- diagnostic-metrics: --list returns N entries
- diagnostic-metrics: required fields present in entry
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
DIAG_TRACKER = ROOT / "scripts" / "diagnostic-metrics-tracker.py"

REQUIRED_ENTRY_FIELDS = {
    "ts",
    "investigation_id",
    "time_to_identify_min",
    "confidence_score",
    "was_correct",
    "rework_needed",
}


def _run_tracker(args: list, log_path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(DIAG_TRACKER), "--log", str(log_path)] + args,
        capture_output=True,
        text=True,
        timeout=30,
    )


# ── diagnostic-metrics-tracker tests ─────────────────────────────────────────

class TestDiagnosticMetricsTracker:
    def test_record_appends_entry_to_jsonl(self, tmp_path):
        """AC: --record appends one line to JSONL"""
        log = tmp_path / "metrics.jsonl"
        result = _run_tracker([
            "--record",
            "--investigation-id", "INV-001",
            "--time-to-identify", "30",
            "--confidence", "0.80",
            "--correct", "true",
        ], log)
        assert result.returncode == 0, result.stderr
        assert log.exists()
        lines = [l for l in log.read_text().splitlines() if l.strip()]
        assert len(lines) == 1

    def test_report_calculates_accuracy_rate_correctly(self, tmp_path):
        """AC: --report accuracy_rate = correct_count / total"""
        log = tmp_path / "metrics.jsonl"
        # 2 correct, 1 incorrect -> accuracy = 0.6667
        for inv_id, correct in [("I1", "true"), ("I2", "true"), ("I3", "false")]:
            _run_tracker([
                "--record",
                "--investigation-id", inv_id,
                "--time-to-identify", "20",
                "--confidence", "0.70",
                "--correct", correct,
            ], log)
        result = _run_tracker(["--report"], log)
        assert result.returncode == 0
        report = json.loads(result.stdout)
        assert "accuracy_rate" in report
        assert abs(report["accuracy_rate"] - (2/3)) < 0.01, (
            f"Expected accuracy ~0.667, got {report['accuracy_rate']}"
        )

    def test_jsonl_append_only_two_records_two_lines(self, tmp_path):
        """AC: two --record calls produce exactly 2 JSONL lines"""
        log = tmp_path / "metrics.jsonl"
        _run_tracker([
            "--record", "--investigation-id", "A", "--time-to-identify", "10",
            "--confidence", "0.5", "--correct", "true",
        ], log)
        _run_tracker([
            "--record", "--investigation-id", "B", "--time-to-identify", "20",
            "--confidence", "0.6", "--correct", "false",
        ], log)
        lines = [l for l in log.read_text().splitlines() if l.strip()]
        assert len(lines) == 2

    def test_list_returns_n_entries(self, tmp_path):
        """AC: --list --n N returns at most N entries"""
        log = tmp_path / "metrics.jsonl"
        for i in range(5):
            _run_tracker([
                "--record", "--investigation-id", f"INV-{i:03d}",
                "--time-to-identify", "15",
                "--confidence", "0.7",
                "--correct", "true",
            ], log)
        result = _run_tracker(["--list", "--n", "3"], log)
        assert result.returncode == 0
        entries = json.loads(result.stdout)
        assert len(entries) == 3

    def test_entry_has_required_fields(self, tmp_path):
        """AC: recorded entry contains all required fields"""
        log = tmp_path / "metrics.jsonl"
        _run_tracker([
            "--record", "--investigation-id", "INV-CHECK",
            "--time-to-identify", "25", "--confidence", "0.85", "--correct", "true",
        ], log)
        line = [l for l in log.read_text().splitlines() if l.strip()][0]
        entry = json.loads(line)
        missing = REQUIRED_ENTRY_FIELDS - set(entry.keys())
        assert not missing, f"Entry missing fields: {missing}"

    def test_jsonl_created_if_not_exists(self, tmp_path):
        """AC: JSONL file is created on first --record even if it did not exist"""
        log = tmp_path / "new_subdir" / "metrics.jsonl"
        assert not log.exists()
        _run_tracker([
            "--record", "--investigation-id", "NEW",
            "--time-to-identify", "10", "--confidence", "0.5", "--correct", "false",
        ], log)
        assert log.exists()

    def test_report_on_empty_log_returns_zero_stats(self, tmp_path):
        """AC: --report on empty/missing log returns all-zero stats"""
        log = tmp_path / "empty.jsonl"
        result = _run_tracker(["--report"], log)
        assert result.returncode == 0
        report = json.loads(result.stdout)
        assert report["total_investigations"] == 0
        assert report["accuracy_rate"] == 0.0

    def test_was_correct_field_is_boolean(self, tmp_path):
        """AC: was_correct stored as boolean in JSONL"""
        log = tmp_path / "booltest.jsonl"
        _run_tracker([
            "--record", "--investigation-id", "BOOL",
            "--time-to-identify", "10", "--confidence", "0.9", "--correct", "true",
        ], log)
        line = [l for l in log.read_text().splitlines() if l.strip()][0]
        entry = json.loads(line)
        assert entry["was_correct"] is True

    def test_confidence_score_stored_correctly(self, tmp_path):
        """AC: confidence_score stored as float in JSONL"""
        log = tmp_path / "floattest.jsonl"
        _run_tracker([
            "--record", "--investigation-id", "FLOAT",
            "--time-to-identify", "10", "--confidence", "0.73", "--correct", "true",
        ], log)
        line = [l for l in log.read_text().splitlines() if l.strip()][0]
        entry = json.loads(line)
        assert abs(entry["confidence_score"] - 0.73) < 0.001

    def test_mean_confidence_in_report(self, tmp_path):
        """AC: --report mean_confidence is correct average"""
        log = tmp_path / "mean.jsonl"
        for conf in ["0.60", "0.80"]:
            _run_tracker([
                "--record", "--investigation-id", f"M{conf}",
                "--time-to-identify", "20", "--confidence", conf, "--correct", "true",
            ], log)
        result = _run_tracker(["--report"], log)
        report = json.loads(result.stdout)
        assert abs(report["mean_confidence"] - 0.70) < 0.01
