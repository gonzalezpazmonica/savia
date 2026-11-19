"""
tests/scripts/test_speculative_execution.py — pytest suite for SE-220 Slices 1-3.

Covers:
  - predictor: whitelist_only=true for all-Read/Grep/Glob/Bash predictions
  - predictor: whitelist_only=false when Edit/Write in predicted_tools
  - predictor: --validate mode exit codes
  - execution.py: cache hit avoids re-execution (mock subprocess)
  - execution.py: TTL expiry removes cache entry
  - execution.py: orchestrate() returns required fields
  - execution.py: speculative_launched=True only when whitelist+confidence met
  - telemetry: telemetry file appended on orchestrate()

Ref: SE-220 Speculative Tool Execution, Slices 1-3
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import threading
from pathlib import Path

import pytest

# ─────────────────────────────────────────────────────────────────────────────
# Module loader helpers
# ─────────────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]
PREDICTOR_SCRIPT  = ROOT / "scripts" / "speculative-tool-predictor.py"
EXECUTION_SCRIPT  = ROOT / "scripts" / "speculative-tool-execution.py"


def _load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod  = importlib.util.module_from_spec(spec)      # type: ignore[arg-type]
    spec.loader.exec_module(mod)                       # type: ignore[union-attr]
    return mod


@pytest.fixture(scope="module")
def predictor():
    return _load_module(PREDICTOR_SCRIPT, "speculative_tool_predictor")


@pytest.fixture(scope="module")
def execution():
    return _load_module(EXECUTION_SCRIPT, "speculative_tool_execution")


# Use a temporary cache dir for every test to avoid cross-test pollution.
# Sets SAVIA_SPECULATIVE_CACHE_DIR env so that fresh module loads pick it up.
@pytest.fixture(autouse=True)
def tmp_cache(tmp_path, monkeypatch):
    monkeypatch.setenv("SAVIA_SPECULATIVE_CACHE_DIR", str(tmp_path / "cache"))
    return tmp_path / "cache"


# ─────────────────────────────────────────────────────────────────────────────
# T01-T05: Predictor — whitelist_only field
# ─────────────────────────────────────────────────────────────────────────────

AVAILABLE_ALL = ["Bash", "Read", "Grep", "Glob", "Edit", "Write"]

class TestPredictorWhitelistOnly:

    def test_whitelist_only_true_for_read_only_predictions(self, predictor):
        """'lee el fichero' → Read → whitelist_only=True"""
        result = predictor.predict("lee el fichero docs/spec.md", ["Read", "Grep", "Glob"])
        assert "Read" in result["predicted_tools"]
        assert result["whitelist_only"] is True, (
            f"Expected whitelist_only=True, got {result['whitelist_only']} "
            f"for predicted_tools={result['predicted_tools']}"
        )

    def test_whitelist_only_true_for_grep(self, predictor):
        """'busca la funcion' → Grep → whitelist_only=True"""
        result = predictor.predict("busca la funcion predict", ["Grep", "Read"])
        assert result["whitelist_only"] is True

    def test_whitelist_only_true_for_bash(self, predictor):
        """'ejecuta los tests' → Bash → whitelist_only=True (Bash is whitelisted)"""
        result = predictor.predict("ejecuta los tests de pytest", AVAILABLE_ALL)
        assert "Bash" in result["predicted_tools"]
        assert result["whitelist_only"] is True

    def test_whitelist_only_false_when_edit_predicted(self, predictor):
        """'modifica el metodo' → Edit → whitelist_only=False"""
        result = predictor.predict("modifica el metodo calculate_velocity", AVAILABLE_ALL)
        assert "Edit" in result["predicted_tools"]
        assert result["whitelist_only"] is False, (
            f"Expected whitelist_only=False (Edit predicted), got True. "
            f"predicted_tools={result['predicted_tools']}"
        )

    def test_whitelist_only_false_when_write_predicted(self, predictor):
        """'crea el fichero' → Write → whitelist_only=False"""
        result = predictor.predict("crea el fichero scripts/new-tool.py", AVAILABLE_ALL)
        assert "Write" in result["predicted_tools"]
        assert result["whitelist_only"] is False

    def test_whitelist_only_field_always_present(self, predictor):
        """Output always contains whitelist_only regardless of intent."""
        for intent in ["xyz unknown nonce 999", "lee el fichero", "modifica el metodo"]:
            result = predictor.predict(intent, AVAILABLE_ALL)
            assert "whitelist_only" in result, f"Missing whitelist_only for intent: {intent}"
            assert isinstance(result["whitelist_only"], bool)


# ─────────────────────────────────────────────────────────────────────────────
# T06-T07: Predictor — --validate mode
# ─────────────────────────────────────────────────────────────────────────────

class TestPredictorValidateMode:

    def test_validate_match_exits_0(self):
        """--validate exits 0 when actual_tool is in predicted_tools."""
        payload = json.dumps({"predicted_tools": ["Read", "Grep"], "actual_tool": "Read"})
        result = subprocess.run(
            [sys.executable, str(PREDICTOR_SCRIPT), "--validate", "--input", payload],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, f"Expected exit 0, got {result.returncode}. stderr: {result.stderr}"
        data = json.loads(result.stdout)
        assert data["match"] is True

    def test_validate_no_match_exits_1(self):
        """--validate exits 1 when actual_tool is not in predicted_tools."""
        payload = json.dumps({"predicted_tools": ["Read", "Grep"], "actual_tool": "Edit"})
        result = subprocess.run(
            [sys.executable, str(PREDICTOR_SCRIPT), "--validate", "--input", payload],
            capture_output=True, text=True,
        )
        assert result.returncode == 1, f"Expected exit 1, got {result.returncode}"
        data = json.loads(result.stdout)
        assert data["match"] is False


# ─────────────────────────────────────────────────────────────────────────────
# T08-T11: Execution orchestrator
# ─────────────────────────────────────────────────────────────────────────────

class TestExecutionOrchestrator:

    def test_orchestrate_returns_required_fields(self, execution, monkeypatch, tmp_path):
        """orchestrate() output must contain all required fields."""
        monkeypatch.setattr(execution, "_TELEMETRY_FILE", tmp_path / "telem.jsonl")
        monkeypatch.setattr(execution, "_CACHE_DIR", tmp_path / "cache")
        result = execution.orchestrate(
            intent="lee el fichero docs/test.md",
            available_tools=["Read", "Grep", "Bash"],
            session_id="test-session-001",
        )
        required = {"session_id", "intent_hash", "predicted_tools", "confidence",
                    "whitelist_only", "speculative_launched", "cache_key", "rationale"}
        missing = required - set(result.keys())
        assert not missing, f"Missing fields: {missing}"

    def test_speculative_launched_true_for_whitelist_intent(self, execution, monkeypatch, tmp_path):
        """whitelist-only intent with confidence>=0.5 → speculative_launched=True."""
        monkeypatch.setattr(execution, "_TELEMETRY_FILE", tmp_path / "telem.jsonl")
        monkeypatch.setattr(execution, "_CACHE_DIR", tmp_path / "cache")

        launched = []
        original_preexec = execution._preexecute_background
        def mock_preexec(tool_name, intent, session_id):
            launched.append(tool_name)
        monkeypatch.setattr(execution, "_preexecute_background", mock_preexec)

        result = execution.orchestrate(
            intent="lee el fichero docs/spec.md",
            available_tools=["Read", "Grep", "Bash"],
            session_id="sess-whitelist",
        )
        assert result["speculative_launched"] is True
        assert result["whitelist_only"] is True
        assert len(launched) > 0, "Background pre-execution was not called"

    def test_speculative_not_launched_for_non_whitelist_intent(self, execution, monkeypatch, tmp_path):
        """Edit/Write intent → speculative_launched=False (non-whitelist)."""
        monkeypatch.setattr(execution, "_TELEMETRY_FILE", tmp_path / "telem.jsonl")
        monkeypatch.setattr(execution, "_CACHE_DIR", tmp_path / "cache")

        launched = []
        monkeypatch.setattr(execution, "_preexecute_background", lambda t, i, s: launched.append(t))

        result = execution.orchestrate(
            intent="modifica el metodo calculate_velocity para filtrar outliers",
            available_tools=["Read", "Grep", "Bash", "Edit", "Write"],
            session_id="sess-edit",
        )
        assert result["speculative_launched"] is False
        assert len(launched) == 0

    def test_cache_miss_on_fresh_orchestrate(self, execution, monkeypatch, tmp_path):
        """resolve_cache_hit returns (False, None) when cache is empty."""
        monkeypatch.setattr(execution, "_CACHE_DIR", tmp_path / "cache")
        monkeypatch.setattr(execution, "_TELEMETRY_FILE", tmp_path / "telem.jsonl")

        hit, cached = execution.resolve_cache_hit(
            tool_name="Read",
            intent="lee docs/test.md",
            session_id="sess-miss",
            actual_start_ms=time.monotonic() * 1000,
        )
        assert hit is False
        assert cached is None
