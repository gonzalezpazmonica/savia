"""
tests/scripts/test_memory_feedback.py — pytest tests for SPEC-164 Memory Feedback Loop
Tests covering the extractor logic.
"""
import json
import sys
import os
import shutil
import textwrap
import tempfile
from pathlib import Path

import importlib.util
import pytest

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).parent.parent.parent
EXTRACTOR = REPO_ROOT / "scripts" / "memory-feedback-extractor.py"


def _load_module(path: Path, module_name: str):
    """Load a Python module from a path that may contain hyphens."""
    spec = importlib.util.spec_from_file_location(module_name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Load modules once at module level
_extractor = _load_module(EXTRACTOR, "memory_feedback_extractor")
extract = _extractor.extract
_compute_entropy = _extractor._compute_entropy


# ─────────────────────────────────────────────────────────────────────────────
# Extractor tests (1-5)
# ─────────────────────────────────────────────────────────────────────────────

class TestExtractor:

    def _make_payload(self, output: str, agent: str = "dotnet-developer") -> dict:
        return {
            "tool_name": "Task",
            "tool_input": {"subagent_type": agent},
            "tool_result": output,
        }

    def test_error_in_output_yields_failure(self):
        """Output containing 'ERROR' → outcome=failure"""
        payload = self._make_payload("ERROR: connection refused on port 5432")
        result = extract(payload)
        assert result["outcome"] == "failure"

    def test_clean_output_yields_success(self):
        """Clean output without error keywords → outcome=success"""
        payload = self._make_payload(
            "All 42 tests passed. Coverage: 87%. Build completed in 3.2s."
        )
        result = extract(payload)
        assert result["outcome"] == "success"

    def test_failure_always_should_write(self):
        """should_write=True for any failure regardless of entropy"""
        payload = self._make_payload("FAILED: test_auth_login assertion error")
        result = extract(payload)
        assert result["should_write"] is True

    def test_success_low_entropy_no_write(self):
        """should_write=False for success with very low entropy (<= 0.3)"""
        # Very short output with few unique tokens → low entropy
        payload = self._make_payload("ok")
        result = extract(payload)
        assert result["outcome"] == "success"
        assert result["should_write"] is False

    def test_entropy_score_computed_correctly(self):
        """entropy_score is between 0 and 1"""
        output = " ".join([f"word{i}" for i in range(200)])
        score = _compute_entropy(output)
        assert 0.0 <= score <= 1.0

    def test_entropy_score_empty_output(self):
        """Empty output → entropy_score = 0.0"""
        assert _compute_entropy("") == 0.0

    def test_entropy_score_very_short(self):
        """Very short output (< 10 tokens) → entropy_score = 0.0"""
        assert _compute_entropy("ok done") == 0.0

    def test_agent_name_extracted_from_tool_input(self):
        """agent_name is read from tool_input.subagent_type"""
        payload = {
            "tool_name": "Task",
            "tool_input": {"subagent_type": "test-runner"},
            "tool_result": "ERROR: tests failed",
        }
        result = extract(payload)
        assert result["agent_name"] == "test-runner"

    def test_lesson_truncated_to_150_chars(self):
        """lesson is always <= 150 characters"""
        long_line = "A" * 300
        payload = self._make_payload(long_line)
        result = extract(payload)
        assert len(result["lesson"]) <= 150

    def test_exception_in_output_yields_failure(self):
        """Output with 'Exception' keyword → outcome=failure"""
        payload = self._make_payload(
            "Traceback (most recent call last):\n  File 'app.py'\nException: null ref"
        )
        result = extract(payload)
        assert result["outcome"] == "failure"
        assert result["should_write"] is True
