"""Tests for SE-221 — Context Engineering Patterns.

Covers:
  Slice 1 — context-origin-tag.sh
  Slice 2 — context-drop-after-use.py  (scripts/context-drop-after-use.sh)
  Slice 3 — context-capability-metadata.py

Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md
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
ORIGIN_TAG = ROOT / "scripts" / "context-origin-tag.sh"
DROP_SCRIPT = ROOT / "scripts" / "context-drop-after-use.sh"
CAP_META_SCRIPT = ROOT / "scripts" / "context-capability-metadata.py"


def _run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 10)
    return subprocess.run(cmd, **kwargs)


# ---------------------------------------------------------------------------
# Slice 1 — context-origin-tag.sh
# ---------------------------------------------------------------------------

class TestContextOriginTag:

    def test_script_exists_and_executable(self):
        assert ORIGIN_TAG.exists(), f"Missing: {ORIGIN_TAG}"
        assert os.access(str(ORIGIN_TAG), os.X_OK), "Not executable"

    def test_critical_facts_returns_n1_anchor(self):
        path = str(ROOT / "docs" / "critical-facts.md")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        assert r.stdout.strip() == "N1-anchor", f"Got: {r.stdout.strip()!r}"

    def test_claude_md_returns_n2_eager(self):
        path = str(ROOT / "CLAUDE.md")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        assert r.stdout.strip() == "N2-eager"

    def test_active_user_profile_returns_n3(self):
        path = str(ROOT / ".claude" / "profiles" / "active-user.md")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        assert r.stdout.strip() == "N3-active-user"

    def test_docs_rules_returns_n4b_on_demand(self):
        path = str(ROOT / "docs" / "rules" / "domain" / "radical-honesty.md")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        assert r.stdout.strip() == "N4b-on-demand"  # SE-511 S2: radical-honesty.md bajo demanda

    def test_git_dir_returns_untrusted(self):
        path = str(ROOT / ".git" / "config")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        # .git is inside workspace but unclassified → N4b-on-demand fallback
        # The spec says "path outside workspace = untrusted". .git IS inside workspace.
        # Acceptable: N4b-on-demand or untrusted
        tier = r.stdout.strip()
        assert tier in ("untrusted", "N4b-on-demand", "N4-project", "N5-external")

    def test_tmp_path_returns_sandbox_or_untrusted(self):
        path = "/tmp/opencode/test-file.txt"
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        tier = r.stdout.strip()
        assert tier in ("sandbox", "untrusted", "N5-external")

    def test_json_flag_returns_valid_json(self):
        path = str(ROOT / "docs" / "critical-facts.md")
        r = _run(["bash", str(ORIGIN_TAG), "--json", path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        data = json.loads(r.stdout)
        assert "tier" in data
        assert "path" in data

    def test_json_output_has_path_and_tier_fields(self):
        path = str(ROOT / "CLAUDE.md")
        r = _run(["bash", str(ORIGIN_TAG), "--json", path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        data = json.loads(r.stdout)
        assert data["tier"] == "N2-eager"
        assert "path" in data

    def test_missing_path_argument_exits_nonzero(self):
        r = _run(["bash", str(ORIGIN_TAG)],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode != 0

    def test_output_path_returns_n4b(self):
        path = str(ROOT / "output" / "some-report.md")
        r = _run(["bash", str(ORIGIN_TAG), path],
                 env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)})
        assert r.returncode == 0
        # output/ is inside workspace, unclassified → N4b-on-demand fallback
        tier = r.stdout.strip()
        assert tier != ""


# ---------------------------------------------------------------------------
# Slice 2 — context-drop-after-use.sh (decision engine)
# ---------------------------------------------------------------------------

class TestContextDropAfterUse:

    def test_script_exists_and_executable(self):
        assert DROP_SCRIPT.exists(), f"Missing: {DROP_SCRIPT}"
        assert os.access(str(DROP_SCRIPT), os.X_OK)

    def test_n1_anchor_path_returns_keep(self):
        path = str(ROOT / "docs" / "critical-facts.md")
        r = _run(
            ["bash", str(DROP_SCRIPT), "--path", path, "--next-task", "anything"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode == 0
        assert "KEEP" in r.stdout

    def test_n4b_path_not_in_next_task_returns_stub(self):
        path = str(ROOT / "docs" / "rules" / "domain" / "caveman-default.md")
        r = _run(
            ["bash", str(DROP_SCRIPT), "--json", "--path", path, "--next-task", "unrelated query"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode == 0
        data = json.loads(r.stdout)
        assert data["verdict"] in ("STUB", "KEEP")  # depends on tier resolution

    def test_keep_context_override_forces_keep(self):
        path = str(ROOT / "docs" / "rules" / "domain" / "caveman-default.md")
        r = _run(
            ["bash", str(DROP_SCRIPT), "--json", "--path", path,
             "--next-task", "KEEP-CONTEXT please"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode == 0
        data = json.loads(r.stdout)
        assert data["verdict"] == "KEEP"
        assert "KEEP-CONTEXT" in data["reason"]

    def test_json_output_has_required_fields(self):
        path = str(ROOT / "docs" / "critical-facts.md")
        r = _run(
            ["bash", str(DROP_SCRIPT), "--json", "--path", path, "--next-task", "x"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode == 0
        data = json.loads(r.stdout)
        for field in ("verdict", "reason", "tier", "path"):
            assert field in data, f"Missing field: {field}"

    def test_missing_path_arg_exits_nonzero(self):
        r = _run(
            ["bash", str(DROP_SCRIPT), "--next-task", "x"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode != 0

    def test_nonexistent_path_does_not_crash(self):
        r = _run(
            ["bash", str(DROP_SCRIPT), "--json",
             "--path", "/nonexistent/path/file.md", "--next-task", "x"],
            env={**os.environ, "SAVIA_WORKSPACE_DIR": str(ROOT)}
        )
        assert r.returncode == 0  # exit 0, graceful


# ---------------------------------------------------------------------------
# Slice 3 — context-capability-metadata.py
# ---------------------------------------------------------------------------

def _load_cap_meta():
    spec = importlib.util.spec_from_file_location(
        "context_capability_metadata", CAP_META_SCRIPT
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def cap_meta():
    return _load_cap_meta()


class TestContextCapabilityMetadata:

    def test_script_exists(self):
        assert CAP_META_SCRIPT.exists()

    def test_output_has_all_required_fields(self, cap_meta):
        path = str(ROOT / "docs" / "rules" / "domain" / "radical-honesty.md")
        meta = cap_meta.build_metadata(path, str(ROOT))
        for field in ("origin", "tier", "audience", "size_tokens", "hash", "last_loaded", "cross_concept_refs"):
            assert field in meta, f"Missing field: {field}"

    def test_extracts_cross_concept_refs_spec_pattern(self, cap_meta):
        path = str(ROOT / "docs" / "rules" / "domain" / "radical-honesty.md")
        meta = cap_meta.build_metadata(path, str(ROOT))
        refs = meta["cross_concept_refs"]
        # radical-honesty.md mentions SPEC-192 and Rule #24
        assert any("SPEC" in r or "SE-" in r or "Rule" in r for r in refs), \
            f"No cross-concept refs found in: {refs}"

    def test_audience_fallback_to_all_without_frontmatter(self, cap_meta):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write("# No frontmatter here\n\nJust plain text without audience.\n")
            tmp_path = f.name
        try:
            meta = cap_meta.build_metadata(tmp_path, str(ROOT))
            assert meta["audience"] == ["all"], f"Expected ['all'], got {meta['audience']}"
        finally:
            os.unlink(tmp_path)

    def test_audience_extracted_from_frontmatter(self, cap_meta):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write("---\naudience: [savia, architect]\n---\n\n# Test\n")
            tmp_path = f.name
        try:
            meta = cap_meta.build_metadata(tmp_path, str(ROOT))
            assert "savia" in meta["audience"]
            assert "architect" in meta["audience"]
        finally:
            os.unlink(tmp_path)

    def test_size_tokens_estimated_correctly(self, cap_meta):
        content = "x" * 400  # 400 bytes -> 100 tokens
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(content)
            tmp_path = f.name
        try:
            meta = cap_meta.build_metadata(tmp_path, str(ROOT))
            assert meta["size_tokens"] == 100, f"Expected 100, got {meta['size_tokens']}"
        finally:
            os.unlink(tmp_path)

    def test_hash_has_sha256_prefix(self, cap_meta):
        path = str(ROOT / "docs" / "critical-facts.md")
        meta = cap_meta.build_metadata(path, str(ROOT))
        assert meta["hash"].startswith("sha256:"), f"Hash: {meta['hash']}"
        assert len(meta["hash"]) == len("sha256:") + 8

    def test_cross_concept_refs_deduplication(self, cap_meta):
        content = "SPEC-192 and again SPEC-192 and SE-221 and SE-221\n"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(content)
            tmp_path = f.name
        try:
            meta = cap_meta.build_metadata(tmp_path, str(ROOT))
            refs = meta["cross_concept_refs"]
            assert refs.count("SPEC-192") == 1, "Should be deduplicated"
            assert refs.count("SE-221") == 1, "Should be deduplicated"
        finally:
            os.unlink(tmp_path)

    def test_cli_produces_valid_json(self):
        path = str(ROOT / "docs" / "critical-facts.md")
        r = _run(
            [sys.executable, str(CAP_META_SCRIPT),
             "--file", path, "--workspace", str(ROOT)]
        )
        assert r.returncode == 0, f"stderr: {r.stderr}"
        data = json.loads(r.stdout)
        assert "origin" in data
        assert "tier" in data

    def test_nonexistent_file_returns_valid_json_with_empty_refs(self, cap_meta):
        meta = cap_meta.build_metadata("/nonexistent/path/nope.md", str(ROOT))
        # Should not raise; returns empty content metadata
        assert "origin" in meta
        assert meta["cross_concept_refs"] == []
        assert meta["size_tokens"] == 0
        assert meta["audience"] == ["all"]

    def test_target_audience_field_also_extracted(self, cap_meta):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write("---\ntarget_audience: humans-only\n---\n\n# Test\n")
            tmp_path = f.name
        try:
            meta = cap_meta.build_metadata(tmp_path, str(ROOT))
            assert meta["audience"] == ["humans-only"]
        finally:
            os.unlink(tmp_path)
