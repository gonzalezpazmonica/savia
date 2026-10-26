"""SE-400 F4 — ablación A0/A2 por unidad sobre fixtures en repos git temporales.

El fixture tiene dos hooks bloqueantes en ``PreToolUse/Bash``: ``block-danger``
(solo «danger») y ``block-other`` («other» y también «danger»). Quitar
``block-other`` pierde un fallo que nadie más atrapa; quitar ``block-danger``
no pierde nada porque ``block-other`` lo solapa.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

import ablation_units as units  # noqa: E402
from ablation_inventory import InventoryError  # noqa: E402
from test_ablation_kernel import _write, make_repo  # noqa: E402

OTHER_HOOK = """#!/bin/bash
INPUT=$(cat)
case "$INPUT" in *other*|*danger*) echo "BLOQUEADO" >&2; exit 2;; esac
exit 0
"""
CORPUS = {"schema": 1, "cases": [
    {"id": "case-danger", "category": "blocked_dangerous_effect", "type": "event",
     "event": "PreToolUse", "tool": "Bash", "input": {"command": "echo danger"}, "expect": "BLOCK"},
    {"id": "case-other", "category": "blocked_dangerous_effect", "type": "event",
     "event": "PreToolUse", "tool": "Bash", "input": {"command": "echo other"}, "expect": "BLOCK"},
    {"id": "case-safe", "category": "safe_exec", "type": "event", "event": "PreToolUse",
     "tool": "Bash", "input": {"command": "ls"}, "expect": "ALLOW"},
    {"id": "case-read", "category": "read_search", "type": "event", "event": "PreToolUse",
     "tool": "Read", "input": {"file_path": "x"}, "expect": "ALLOW"}]}


def prereg(**overrides) -> dict:
    doc = {"schema": 1, "spec": "SE-400", "phase": "F4", "registry_id": "fixture",
           "version": "0.1.0", "scope": {"event": "PreToolUse", "matcher": "Bash"},
           "corpora": ["config/f4-corpus.json"], "decision_rule": {"x": "y"},
           "units": [
               {"id": "u-danger", "unit": ".claude/hooks/block-danger.sh", "modes": ["A0", "A2"],
                "hypothesis": "solapado por block-other", "expected_unique_catches": []},
               {"id": "u-other", "unit": ".claude/hooks/block-other.sh", "modes": ["A0", "A2"],
                "hypothesis": "único en other", "expected_unique_catches": ["case-safe"]}]}
    doc.update(overrides)
    return doc


class UnitAblationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root, self.work = base / "repo", base / "work"
        make_repo(self.root, {".claude/hooks/block-other.sh": OTHER_HOOK})
        self.commit(prereg())

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def commit(self, doc: dict, corpus: dict = CORPUS) -> None:
        _write(self.root, units.PREREG_PATH, json.dumps(doc))
        _write(self.root, "config/f4-corpus.json", json.dumps(corpus))
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@i",
                        "-c", "core.hooksPath=/dev/null", "commit", "-qm", "prereg",
                        "--allow-empty"], check=True)

    def run_units(self) -> dict:
        doc = json.loads((self.root / units.PREREG_PATH).read_text(encoding="utf-8"))
        return units.run_units(self.root, doc, self.work)

    def by(self, receipt: dict) -> dict:
        return {(r["unit_id"], r["mode"]): r for r in receipt["units"]}

    def test_unique_catch_aborts_and_overlap_does_not(self) -> None:
        rows = self.by(self.run_units())
        for mode in ("A0", "A2"):
            other, danger = rows[("u-other", mode)], rows[("u-danger", mode)]
            self.assertEqual(other["decision"], "ABORT_FALSE_ALLOW")
            self.assertEqual(other["unique_failures_caught"], ["case-other"])
            self.assertEqual(danger["decision"], "NO_UNIQUE_CATCH_ON_CORPUS")
            self.assertEqual(danger["unique_failures_caught"], [])
            self.assertEqual(danger["control_blocks_by_unit"], ["case-danger"])

    def test_expectation_is_compared_with_observation(self) -> None:
        receipt = self.run_units()
        rows = self.by(receipt)
        self.assertEqual(rows[("u-danger", "A0")]["expectation"], "MATCH")
        other = rows[("u-other", "A0")]
        self.assertEqual(other["expectation"], "MISMATCH")
        self.assertEqual(other["unexpected_catches"], ["case-other"])
        self.assertEqual(other["predicted_not_caught"], ["case-safe"])
        self.assertIn("u-other:A2", receipt["summary"]["expectation_mismatches"])

    def test_a0_runs_only_traversed_cases_a2_runs_all(self) -> None:
        rows = self.by(self.run_units())
        self.assertEqual(rows[("u-other", "A0")]["cases_run"], 3)
        self.assertEqual(rows[("u-other", "A2")]["cases_run"], 4)

    def test_repository_is_not_mutated(self) -> None:
        self.run_units()
        status = subprocess.run(["git", "-C", str(self.root), "status", "--porcelain"],
                                capture_output=True, text=True, check=True).stdout
        self.assertEqual(status, "")
        self.assertIn("exit 2", (self.root / ".claude/hooks/block-other.sh").read_text())

    def test_scope_must_match_f2_group(self) -> None:
        doc = prereg()
        doc["units"] = doc["units"][:1]
        self.commit(doc)
        with self.assertRaises(InventoryError) as ctx:
            self.run_units()
        self.assertIn("PREREG_SCOPE_INCOMPLETE", str(ctx.exception))
        doc = prereg()
        doc["units"].append({"id": "u-adv", "unit": ".claude/hooks/advisory.sh", "modes": ["A0"],
                             "hypothesis": "h", "expected_unique_catches": []})
        self.commit(doc)
        with self.assertRaises(InventoryError) as ctx:
            self.run_units()
        self.assertIn("PREREG_UNIT_OUT_OF_SCOPE", str(ctx.exception))

    def test_prereg_must_be_committed_before_run(self) -> None:
        _write(self.root, units.PREREG_PATH, json.dumps(prereg(version="0.1.1")))
        with self.assertRaises(InventoryError) as ctx:
            self.run_units()
        self.assertIn("PREREG_NOT_COMMITTED", str(ctx.exception))

    def test_invalid_preregistrations_are_rejected(self) -> None:
        bad = [prereg(model="x"), prereg(phase="F3"), prereg(units=[]),
               prereg(units=[{**prereg()["units"][0], "modes": ["A6"]}]),
               prereg(excluded_cases=[{"id": "case-safe"}])]
        for doc in bad:
            with self.assertRaises(InventoryError):
                units.validate_prereg(doc)

    def test_exclusions_are_reported_and_go_stale(self) -> None:
        self.commit(prereg(excluded_cases=[{"id": "case-safe", "reason": "defecto conocido"}]))
        receipt = self.run_units()
        self.assertEqual(receipt["control"]["excluded"],
                         [{"id": "case-safe", "reason": "defecto conocido", "control": "ALLOW",
                           "stale": True}])
        self.assertEqual(self.by(receipt)[("u-other", "A2")]["cases_run"], 3)
        self.commit(prereg(excluded_cases=[{"id": "ghost", "reason": "r"}]))
        with self.assertRaises(InventoryError) as ctx:
            self.run_units()
        self.assertIn("PREREG_EXCLUSION_UNKNOWN", str(ctx.exception))

    def test_invalid_control_is_reported_not_hidden(self) -> None:
        corpus = json.loads(json.dumps(CORPUS))
        corpus["cases"][2]["expect"] = "BLOCK"
        self.commit(prereg(), corpus)
        receipt = self.run_units()
        self.assertEqual(receipt["control"]["invalid"], ["case-safe"])
        self.assertTrue(all(r["decision"] == "INCONCLUSIVE" for r in receipt["units"]))

    def test_drop_registrations_removes_every_registration(self) -> None:
        settings = json.loads((self.root / ".claude/settings.json").read_text())
        dropped = units.drop_registrations(settings, ".claude/hooks/block-danger.sh")
        text = json.dumps(dropped)
        self.assertNotIn("block-danger.sh", text)
        self.assertIn("block-other.sh", text)
        self.assertEqual(len(dropped["hooks"]["PreToolUse"]), 1)


if __name__ == "__main__":
    unittest.main()
