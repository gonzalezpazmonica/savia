"""SE-400 F2/F3 — grafos tipados, kernel candidato aislado y receipt.

Fixtures mínimas en repos git temporales: no tocan el árbol real salvo el
test de integración, que solo lee y escribe en un directorio temporal.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import ablation_graphs as graphs  # noqa: E402
import ablation_kernel as kernel  # noqa: E402

BLOCK_HOOK = """#!/bin/bash
LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
INPUT=$(cat)
case "$INPUT" in *danger*) echo "BLOQUEADO" >&2; exit 2;; esac
exit 0
"""
GATE_LIB = """profile_gate() { case "${SAVIA_HOOK_PROFILE:-standard}" in
  minimal) [[ "$1" == security ]] && return 0; exit 0;;
  standard|ci) [[ "$1" == security || "$1" == standard ]] && return 0; exit 0;;
  *) return 0;; esac; }
"""
ADVISORY_HOOK = """#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/profile-gate.sh" && profile_gate "automation"
echo advisory
"""


def _write(root: Path, rel: str, text: str, mode: int = 0o644) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def make_repo(root: Path, extra_hooks: dict | None = None) -> None:
    _write(root, ".claude/hooks/lib/profile-gate.sh", GATE_LIB)
    _write(root, ".claude/hooks/block-danger.sh", BLOCK_HOOK, 0o755)
    _write(root, ".claude/hooks/advisory.sh", ADVISORY_HOOK, 0o755)
    for rel, text in (extra_hooks or {}).items():
        _write(root, rel, text, 0o755)
    hooks = [{"type": "command", "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/block-danger.sh',
              "timeout": 5}]
    hooks += [{"type": "command", "command": f'"$CLAUDE_PROJECT_DIR"/{rel}', "timeout": 5}
              for rel in (extra_hooks or {})]
    settings = {"hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": hooks},
                       {"matcher": "Bash", "hooks": [hooks[0]]}],
        "Stop": [{"hooks": [{"type": "command", "async": True,
                             "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/advisory.sh'}]}],
    }}
    _write(root, ".claude/settings.json", json.dumps(settings))
    _write(root, "scripts/helper.sh", "echo helper\n", 0o755)
    _write(root, "scripts/main.sh", 'source "$(dirname "${BASH_SOURCE[0]}")/helper.sh"\n'
           "bash scripts/tool.py\n", 0o755)
    _write(root, "scripts/tool.py", "import libmod\n")
    _write(root, "scripts/libmod.py", "X = 1\n")
    _write(root, ".claude/skills/demo/SKILL.md", "---\nname: demo\n---\n")
    _write(root, ".claude/agents/worker.md", "---\nname: worker\nskills: [demo, ghost]\n---\n")
    _write(root, ".claude/commands/run.md", "---\nagent: missing-agent\n---\n")
    _write(root, "docs/rules/domain/pack-rule.md", "regla del pack\n")
    _write(root, "config/ablation-contract.json",
           (ROOT / "config/ablation-contract.json").read_text(encoding="utf-8"))
    _write(root, "config/domain-packs.json", json.dumps({"schema": 2, "packs": [
        {"id": "core-local", "rule_refs": [], "context_refs": [], "test_refs": []},
        {"id": "legacy", "rule_refs": ["docs/rules/domain/pack-rule.md"],
         "context_refs": [], "test_refs": []}]}))
    git = ["git", "-C", str(root), "-c", "user.name=t", "-c", "user.email=t@invalid",
           "-c", "core.hooksPath=/dev/null"]
    subprocess.run(["git", "init", "-q", "-b", "agent/fixture", str(root)], check=True)
    subprocess.run(git + ["add", "-A"], check=True)
    subprocess.run(git + ["commit", "-qm", "fixture"], check=True)


class GraphTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        make_repo(self.root)
        self.files = graphs.tracked_files(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _edges(self) -> set[tuple[str, str, str]]:
        return {(e["source"], e["target"], e["relation"])
                for e in graphs.dependency_edges(self.root, self.files)}

    def test_sources_invokes_imports_are_resolved(self) -> None:
        edges = self._edges()
        self.assertIn(("scripts/main.sh", "scripts/helper.sh", "SOURCES"), edges)
        self.assertIn(("scripts/main.sh", "scripts/tool.py", "INVOKES"), edges)
        self.assertIn(("scripts/tool.py", "scripts/libmod.py", "IMPORTS"), edges)
        self.assertIn((".claude/hooks/block-danger.sh", ".claude/hooks/lib/profile-gate.sh",
                       "SOURCES"), edges)

    def test_declared_dependencies_and_dangling_references(self) -> None:
        edges = self._edges()
        self.assertIn((".claude/agents/worker.md", ".claude/skills/demo/SKILL.md",
                       "DECLARES_SKILL"), edges)
        self.assertIn((".claude/agents/worker.md", "MISSING:skill/ghost", "DECLARES_SKILL"), edges)
        self.assertIn((".claude/commands/run.md", "MISSING:agent/missing-agent",
                       "DELEGATES_TO"), edges)

    def test_hook_matrix_findings(self) -> None:
        rows = graphs.hook_matrix(self.root, self.files)
        danger = [r for r in rows if r["hook"].endswith("block-danger.sh")]
        self.assertEqual(len(danger), 2)
        self.assertTrue(all(r["blocking_capable"] for r in danger))
        self.assertTrue(all("DUPLICATE_REGISTRATION" in r["findings"] for r in danger))
        self.assertEqual(danger[0]["profiles"], list(graphs.PROFILES))
        advisory = next(r for r in rows if r["hook"].endswith("advisory.sh"))
        self.assertFalse(advisory["blocking_capable"])
        self.assertIn("UNKNOWN_TIER_SKIPPED_IN_DEFAULT_PROFILE", advisory["findings"])
        self.assertEqual(advisory["profiles"], ["strict"])

    def test_contract_links_only_with_code_authority(self) -> None:
        links = graphs.contract_links(graphs.hook_matrix(self.root, self.files))
        self.assertEqual([l["source"] for l in links], [".claude/hooks/block-danger.sh"])

    def test_matcher_semantics(self) -> None:
        self.assertTrue(graphs.matcher_matches("Bash(git commit*)", "Bash", "git commit -m x"))
        self.assertFalse(graphs.matcher_matches("Bash(git commit*)", "Bash", "git status"))
        self.assertTrue(graphs.matcher_matches("Edit|Write", "Write"))
        self.assertFalse(graphs.matcher_matches("Edit|Write", "Bash"))
        self.assertTrue(graphs.matcher_matches(".*", "Read"))


class KernelTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()
        make_repo(self.root)
        self.files = graphs.tracked_files(self.root)
        self.candidate = {"schema": 1, "candidate_id": "fixture", "version": "0.1.0",
                          "allowed_packs": ["core-local"],
                          "areas": {"authority": [".claude/hooks/block-danger.sh"],
                                    "tooling": ["scripts/main.sh"]}}

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_closure_follows_executable_edges(self) -> None:
        plan = kernel.plan_kernel(self.root, self.files, self.candidate)
        self.assertIn(".claude/hooks/lib/profile-gate.sh", plan["paths"])
        self.assertIn("scripts/libmod.py", plan["paths"])
        self.assertNotIn(".claude/hooks/advisory.sh", plan["paths"])
        self.assertEqual(plan["pack_dependencies"], [])

    def test_accidental_pack_dependency_is_reported(self) -> None:
        self.candidate["areas"]["rules"] = ["docs/rules/domain/pack-rule.md"]
        plan = kernel.plan_kernel(self.root, self.files, self.candidate)
        self.assertEqual(plan["pack_dependencies"],
                         [{"path": "docs/rules/domain/pack-rule.md", "pack": "legacy"}])

    def test_missing_seed_is_invalid(self) -> None:
        self.candidate["areas"]["authority"].append(".claude/hooks/nope.sh")
        with self.assertRaises(kernel.InventoryError) as ctx:
            kernel.plan_kernel(self.root, self.files, self.candidate)
        self.assertEqual(ctx.exception.code, "KERNEL_SEED_MISSING")

    def test_settings_projection_keeps_only_kernel_hooks(self) -> None:
        settings = json.loads((self.root / ".claude/settings.json").read_text())
        projected = kernel.project_settings(settings, {".claude/hooks/block-danger.sh"})
        self.assertNotIn("Stop", projected["hooks"])
        self.assertEqual(len(projected["hooks"]["PreToolUse"]), 2)

    def test_materialize_refuses_destination_inside_repository(self) -> None:
        with self.assertRaises(kernel.InventoryError) as ctx:
            kernel.ensure_isolated(self.root, self.root / "output" / "k")
        self.assertEqual(ctx.exception.code, "DEST_NOT_ISOLATED")

    def test_dispatch_blocks_and_allows(self) -> None:
        snap = kernel.materialize(self.root, self.files, sorted(self.files),
                                  Path(self.tmp.name) / "full", None)
        home = Path(self.tmp.name) / "home"
        blocked = kernel.dispatch(snap, home, "PreToolUse", "Bash", {"command": "danger"})
        allowed = kernel.dispatch(snap, home, "PreToolUse", "Bash", {"command": "ls"})
        self.assertEqual(blocked["decision"], "BLOCK")
        self.assertEqual(allowed["decision"], "ALLOW")
        self.assertEqual(len(blocked["hooks"]), 2)

    def test_compare_false_allow_aborts(self) -> None:
        case = {"id": "c1", "type": "event", "expect": "BLOCK"}
        verdict = kernel.compare_case(case, {"decision": "BLOCK"}, {"decision": "ALLOW"})
        self.assertEqual(verdict, "FALSE_ALLOW")
        decision = kernel.decide([{"id": "c1", "verdict": verdict}])
        self.assertEqual(decision, "ABORT_FALSE_ALLOW")

    def test_compare_control_invalid_is_inconclusive(self) -> None:
        case = {"id": "c1", "type": "event", "expect": "BLOCK"}
        verdict = kernel.compare_case(case, {"decision": "ALLOW"}, {"decision": "ALLOW"})
        self.assertEqual(verdict, "CONTROL_INVALID")
        self.assertEqual(kernel.decide([{"verdict": verdict}]), "INCONCLUSIVE")
        self.assertEqual(kernel.decide([{"verdict": "MATCH"}]), "KERNEL_PRESERVES_CORPUS")

    def test_kernel_without_blocker_yields_false_allow_end_to_end(self) -> None:
        corpus = {"schema": 1, "corpus_id": "fx", "cases": [
            {"id": "danger", "category": "blocked_dangerous_effect", "type": "event",
             "event": "PreToolUse", "tool": "Bash", "input": {"command": "danger"},
             "expect": "BLOCK"},
            {"id": "safe", "category": "safe_exec", "type": "event", "event": "PreToolUse",
             "tool": "Bash", "input": {"command": "ls"}, "expect": "ALLOW"}],
            "not_verified": []}
        self.candidate["areas"] = {"tooling": ["scripts/main.sh"]}
        receipt = kernel.run_experiment(self.root, self.candidate, corpus,
                                        Path(self.tmp.name) / "work")
        self.assertEqual(receipt["decision"], "ABORT_FALSE_ALLOW")
        verdicts = {c["id"]: c["verdict"] for c in receipt["cases"]}
        self.assertEqual(verdicts, {"danger": "FALSE_ALLOW", "safe": "MATCH"})
        self.candidate["areas"] = {"authority": [".claude/hooks/block-danger.sh"]}
        receipt = kernel.run_experiment(self.root, self.candidate, corpus,
                                        Path(self.tmp.name) / "work2")
        self.assertEqual(receipt["decision"], "KERNEL_PRESERVES_CORPUS")
        self.assertRegex(receipt["receipt_sha256"], r"^[0-9a-f]{64}$")
        self.assertLess(receipt["vector"]["kernel"]["files"], receipt["vector"]["full"]["files"])


class RepositoryCandidateTests(unittest.TestCase):
    def test_repository_candidate_and_corpus_are_valid(self) -> None:
        candidate = kernel.load_json(ROOT / kernel.CANDIDATE_PATH)
        corpus = kernel.validate_corpus(kernel.load_json(ROOT / kernel.CORPUS_PATH))
        plan = kernel.plan_kernel(ROOT, graphs.tracked_files(ROOT), candidate)
        self.assertGreater(len(plan["paths"]), 0)
        categories = {c["category"] for c in corpus["cases"]}
        self.assertTrue({"blocked_dangerous_effect", "secrets", "human_gate",
                         "safe_exec"} <= categories)

    def test_corpus_rejects_model_as_baseline(self) -> None:
        corpus = kernel.load_json(ROOT / kernel.CORPUS_PATH)
        corpus["baseline_model"] = "x"
        with self.assertRaises(kernel.InventoryError):
            kernel.validate_corpus(corpus)


if __name__ == "__main__":
    unittest.main()
