"""SE-400 F1 contract tests for the read-only Resource/Capability inventory."""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from ablation_consumers import build_keys  # noqa: E402
from ablation_inventory import (  # noqa: E402
    InventoryError,
    build_report,
    main,
    validate_contract,
    validate_record,
)

CONTRACT = json.loads((ROOT / "config/ablation-contract.json").read_text(encoding="utf-8"))
RECEIPT = "a" * 64


def _write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True,
                   env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})


def make_fixture(root: Path) -> None:
    contract = copy.deepcopy(CONTRACT)
    contract["generated_views"] = [
        {"path": "AGENTS.md", "generator": "scripts/gen-agents.sh"},
        {"path": "SKILLS.md", "generator": "scripts/missing-generator.sh"},
    ]
    _write(root, "config/ablation-contract.json", json.dumps(contract))
    _write(root, "config/domain-packs.json", json.dumps({"packs": [{"id": "core-local"}]}))
    hook = {"type": "command", "command": '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/guard.sh'}
    _write(root, ".claude/settings.json",
           json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [hook]}]}}))
    _write(root, ".claude/hooks/guard.sh", "#!/bin/sh\n")
    _write(root, ".claude/hooks/dormant.sh", "#!/bin/sh\n")
    _write(root, ".claude/commands/core.md", "# core\n")
    _write(root, ".claude/commands/extended.md", "# extended\n")
    _write(root, ".claude/agents/architect.md", "# mirror\n")
    _write(root, ".claude/agents/orphan.md", "# orphan\n")
    _write(root, ".opencode/agents/architect.md", "# agent\n")
    _write(root, ".claude/skills/demo/SKILL.md", "# skill\n")
    _write(root, "scripts/gen-agents.sh", "#!/bin/sh\n")
    _write(root, "scripts/tool.py", "print(1)\n")
    _write(root, "docs/rules/domain/rule.md", "# rule\n")
    _write(root, "SKILLS.md", "# generated\n")
    _write(root, "README.md", "# out of surface\n")
    _write(root, "docs/guide.md",
           "Run `scripts/tool.py`, then /core, see .opencode/skills/demo/SKILL.md.\n")
    _write(root, "tests/test-gen.bats", "run bash ./scripts/gen-agents.sh\n")
    _write(root, "CHANGELOG.md", "- docs/rules/domain/rule.md added\n")
    _write(root, "AGENTS.md", "# generated: .claude/commands/extended.md\n")
    _write(root, "scripts/selfref.sh", "# usage: scripts/selfref.sh\n")
    edges = [{"relation": "IMPLEMENTS", "source": "component/.claude/commands/core.md",
              "target": "capability/cmd:.claude/commands/core"}]
    _write(root, ".scm/sam.json", json.dumps({"model_revision": "f" * 64, "edges": edges}))
    _write(root, ".scm/resources.json", json.dumps({"hash": "abc123"}))
    (root / ".agents").mkdir()
    os.symlink("../.claude/skills", root / ".agents/skills")
    _git(root, "init", "-q")
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "fixture")


class ContractTest(unittest.TestCase):
    def test_committed_contract_is_valid(self) -> None:
        self.assertEqual(validate_contract(copy.deepcopy(CONTRACT))["contract_version"], "1.0.0")

    def test_model_as_baseline_is_rejected(self) -> None:
        bad = copy.deepcopy(CONTRACT)
        bad["baseline"]["model"] = "any-model"
        with self.assertRaises(InventoryError) as ctx:
            validate_contract(bad)
        self.assertEqual(ctx.exception.code, "MODEL_AS_BASELINE")

    def test_security_floor_cannot_be_dropped(self) -> None:
        bad = copy.deepcopy(CONTRACT)
        bad["baseline"]["non_compensable_floors"].remove("security_floors")
        with self.assertRaises(InventoryError) as ctx:
            validate_contract(bad)
        self.assertEqual(ctx.exception.code, "CONTRACT_FLOORS")

    def test_contract_must_be_versioned(self) -> None:
        bad = copy.deepcopy(CONTRACT)
        bad["contract_version"] = "latest"
        with self.assertRaises(InventoryError) as ctx:
            validate_contract(bad)
        self.assertEqual(ctx.exception.code, "CONTRACT_VERSION")

    def test_removal_states_must_require_receipt(self) -> None:
        bad = copy.deepcopy(CONTRACT)
        bad["taxonomy"]["requires_ablation_receipt"].remove("DEAD")
        with self.assertRaises(InventoryError) as ctx:
            validate_contract(bad)
        self.assertEqual(ctx.exception.code, "TAXONOMY_GATES")


class RecordGateTest(unittest.TestCase):
    def rec(self, **extra: object) -> dict:
        base = {"path": "x", "class": "Script", "essentiality": "UNKNOWN", "basis": ["PATH"]}
        return {**base, **extra}

    def assert_code(self, rec: dict, code: str) -> None:
        with self.assertRaises(InventoryError) as ctx:
            validate_record(rec, CONTRACT)
        self.assertEqual(ctx.exception.code, code)

    def test_dead_without_receipt_is_rejected(self) -> None:
        self.assert_code(self.rec(essentiality="DEAD"), "ESSENTIALITY_WITHOUT_RECEIPT")

    def test_core_without_receipt_is_rejected(self) -> None:
        self.assert_code(self.rec(essentiality="CORE_ESSENTIAL"), "ESSENTIALITY_WITHOUT_RECEIPT")

    def test_dead_without_human_gate_is_rejected(self) -> None:
        self.assert_code(self.rec(essentiality="DEAD", ablation_receipt=RECEIPT),
                         "REMOVAL_WITHOUT_HUMAN_GATE")

    def test_dead_with_receipt_and_gate_passes(self) -> None:
        validate_record(self.rec(essentiality="DEAD", ablation_receipt=RECEIPT,
                                 human_gate="operator", recommended_action="delete"), CONTRACT)

    def test_unknown_never_carries_removal(self) -> None:
        self.assert_code(self.rec(recommended_action="Delete"), "REMOVAL_ACTION_NOT_ALLOWED")

    def test_class_needs_authority_basis(self) -> None:
        self.assert_code(self.rec(basis=[]), "CLASS_WITHOUT_AUTHORITY")


class FixtureInventoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        make_fixture(self.root)
        self.report = build_report(self.root)
        self.by_path = {r["path"]: r for r in self.report["records"]}

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_classes_follow_authority_only(self) -> None:
        expect = {
            ".claude/commands/core.md": "Capability",
            ".claude/commands/extended.md": "UNKNOWN",
            ".claude/hooks/guard.sh": "Control",
            ".claude/hooks/dormant.sh": "UNKNOWN",
            ".claude/agents/architect.md": "UNKNOWN",
            "scripts/tool.py": "Script",
            "docs/rules/domain/rule.md": "UNKNOWN",
            "AGENTS.md": "GeneratedView",
            "SKILLS.md": "UNKNOWN",
            ".agents/skills": "Projection",
            "config/domain-packs.json#core-local": "DomainPack",
        }
        self.assertEqual({p: self.by_path[p]["class"] for p in expect}, expect)
        self.assertNotIn("README.md", self.by_path)

    def test_unknown_reasons_and_mirror_evidence(self) -> None:
        self.assertIn("NOT_REGISTERED_IN_SETTINGS", self.by_path[".claude/hooks/dormant.sh"]["unknowns"])
        self.assertIn("GENERATOR_MISSING", self.by_path["SKILLS.md"]["unknowns"])
        self.assertIn("MIRROR_OF:.opencode/agents/architect.md",
                      self.by_path[".claude/agents/architect.md"]["basis"])
        self.assertEqual(self.by_path[".claude/agents/orphan.md"]["basis"], [])
        self.assertEqual(self.by_path[".agents/skills"]["basis"], ["SYMLINK:../.claude/skills"])
        self.assertEqual(self.by_path[".claude/hooks/guard.sh"]["basis"], ["SETTINGS:PreToolUse"])

    def consumers(self, path: str) -> dict:
        return self.by_path[path]["static_consumers"]

    def test_static_consumers_by_literal_reference(self) -> None:
        self.assertEqual(self.consumers("scripts/tool.py"), {"active": 1, "tests": 0})
        self.assertEqual(self.consumers(".claude/commands/core.md")["active"], 1)
        self.assertEqual(self.consumers(".claude/skills/demo/SKILL.md")["active"], 1)
        self.assertEqual(self.consumers("scripts/gen-agents.sh")["tests"], 1)
        self.assertEqual(self.consumers(".claude/hooks/guard.sh")["active"], 1)

    def test_passive_and_self_references_do_not_count(self) -> None:
        for path in ("docs/rules/domain/rule.md", ".claude/commands/extended.md",
                     ".claude/hooks/dormant.sh", "scripts/selfref.sh"):
            self.assertEqual(self.consumers(path), {"active": 0, "tests": 0}, path)
            self.assertIn("NO_STATIC_CONSUMER", self.by_path[path]["unknowns"], path)
            self.assertEqual(self.by_path[path]["essentiality"], "UNKNOWN", path)

    def test_ambiguous_keys_are_dropped(self) -> None:
        keys = build_keys(self.report["records"])
        self.assertNotIn("agents/architect.md", keys)
        self.assertEqual(keys["agents/orphan.md"], ".claude/agents/orphan.md")

    def test_f1_never_emits_receipt_states(self) -> None:
        gated = set(CONTRACT["taxonomy"]["requires_ablation_receipt"])
        self.assertFalse({r["essentiality"] for r in self.report["records"]} & gated)

    def test_report_is_deterministic_and_bound_to_content(self) -> None:
        again = build_report(self.root)
        self.assertEqual(again["report_revision"], self.report["report_revision"])
        prov = self.report["provenance"]
        self.assertEqual((prov["contract_version"], prov["scm_hash"]), ("1.0.0", "abc123"))
        _write(self.root, "scripts/tool.py", "print(2)\n")
        _git(self.root, "commit", "-qam", "change")
        changed = build_report(self.root)
        self.assertNotEqual(changed["provenance"]["surface_sha256"], prov["surface_sha256"])
        self.assertNotEqual(changed["report_revision"], self.report["report_revision"])

    def test_check_detects_stale_report(self) -> None:
        out = self.root / "out"
        args = ["--root", str(self.root), "--out", str(out)]
        self.assertEqual(main(["check", *args]), 1)  # missing
        self.assertEqual(main(["generate", *args]), 0)
        self.assertEqual(main(["check", *args]), 0)
        _write(self.root, ".claude/commands/new.md", "# new\n")
        _git(self.root, "add", "-A")
        _git(self.root, "commit", "-qm", "new command")
        self.assertEqual(main(["check", *args]), 1)

    def test_invalid_contract_aborts_generation(self) -> None:
        bad = copy.deepcopy(CONTRACT)
        bad["baseline"]["provider"] = "x"
        _write(self.root, "config/ablation-contract.json", json.dumps(bad))
        self.assertEqual(main(["summary", "--root", str(self.root)]), 2)


class RepositoryInventoryTest(unittest.TestCase):
    def test_repository_inventory_respects_f1_gates(self) -> None:
        report = build_report(ROOT)
        kinds = report["summary"]["by_kind"]
        self.assertEqual(kinds["skill"]["physical"], kinds["skill"]["indexed_in_sam"])
        self.assertGreater(kinds["script"]["physical"], kinds["script"]["indexed_in_sam"])
        gated = set(CONTRACT["taxonomy"]["requires_ablation_receipt"])
        self.assertFalse(set(report["summary"]["by_essentiality"]) & gated)


if __name__ == "__main__":
    unittest.main()
