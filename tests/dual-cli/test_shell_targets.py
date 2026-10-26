"""SE-392 S3: writes to gate files from `bash`, denied in both cores with the same decision.

Before this change `write`/`edit`/`apply_patch` on `.claude/settings.json`, `.claude/hooks`,
`.codex`, `scripts/dual-cli`, … were denied (PROTECTED_GATE_PATH) but the same rewrite through
the shell (`echo {} > .claude/settings.json`, `sed -i`, `git checkout -- .codex/hooks.json`,
a recursive remove of `.claude`) reached the CLI in Codex and in OpenCode. Commands are never
executed here: the gate decides on their text before any hook runs.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
FIXTURES = ROOT / "tests/dual-cli/fixtures"
sys.path.insert(0, str(CORE))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gates
import shell_targets
from protocol import ProtocolError
from required_tools import needs

CORPUS = json.loads((FIXTURES / "shell_targets_corpus.json").read_text())


def python_answer(command, cwd, root):
    payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}
    gate = gates.shell_writes_gate(payload, root)
    try:
        return {"hit": shell_targets.protected_target(command, cwd, root, gates.PROTECTED_PATHS),
                "invalid": False, "gate": gate}
    except ProtocolError:
        return {"hit": None, "invalid": True, "gate": gate}


def ts_answers(cases, cwd, root):
    run = subprocess.run(["bun", str(FIXTURES / "ts_shell_targets.ts")], capture_output=True, timeout=120,
                         input=json.dumps({"cases": cases, "cwd": cwd, "root": root}).encode())
    if run.returncode != 0:
        raise AssertionError(run.stderr.decode())
    return json.loads(run.stdout)


class ShellTargetCorpusTests(unittest.TestCase):
    def test_corpus_in_the_codex_core(self):
        for case in CORPUS:
            got = python_answer(case["command"], "/w", "/w")
            if case.get("invalid"):
                self.assertTrue(got["invalid"], case["id"])
            else:
                self.assertEqual((got["invalid"], got["hit"]), (False, case["hit"]), case["id"])
                self.assertEqual(got["gate"], case["hit"] is not None, case["id"])
        # The corpus must keep both kinds: a gate that denies everything or nothing would pass half.
        self.assertGreaterEqual(sum(1 for c in CORPUS if c.get("hit")), 30)
        self.assertGreaterEqual(sum(1 for c in CORPUS if "hit" in c and c["hit"] is None), 20)

    def test_unparseable_text_denies_only_when_it_names_a_gate_location(self):
        self.assertTrue(gates.shell_writes_gate({"tool_name": "Bash", "tool_input": {
            "command": "echo 'x > .codex/hooks.json"}}, "/w"))
        self.assertFalse(gates.shell_writes_gate({"tool_name": "Bash", "tool_input": {
            "command": "echo 'sin cerrar"}}, "/w"))

    def test_other_tools_and_non_string_commands_are_not_shell(self):
        self.assertFalse(gates.shell_writes_gate({"tool_name": "Read", "tool_input": {
            "command": "echo x > .claude/settings.json"}}, "/w"))
        self.assertFalse(gates.shell_writes_gate({"tool_name": "Bash", "tool_input": {"command": 3}}, "/w"))

    def test_nesting_has_a_limit(self):
        command = "echo x"
        for _ in range(shell_targets.MAX_DEPTH + 2):
            command = f"bash -c {json.dumps(command)}"
        with self.assertRaises(ProtocolError):
            shell_targets.analyse(command)

    def test_symlinked_alias_of_a_gate_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.realpath(tmp)
            os.makedirs(os.path.join(root, ".claude/hooks"))
            os.symlink(os.path.join(root, ".claude/hooks"), os.path.join(root, "alias"))
            got = python_answer("echo x > alias/tdd-gate.sh", root, root)
            self.assertEqual(got["hit"], "alias/tdd-gate.sh")
            self.assertIsNone(python_answer("echo x > aliasX/tdd-gate.sh", root, root)["hit"])

    def test_unparseable_text_naming_only_a_plain_parent_is_not_a_gate(self):
        """`scripts` alone names no gate; `scripts/dual-cli` and `.claude` do (PR #1391 review)."""
        deny = lambda c: gates.shell_writes_gate({"tool_name": "Bash", "tool_input": {"command": c}}, "/w")
        self.assertFalse(deny("ls scripts 'sin cerrar"))
        self.assertTrue(deny("ls scripts/dual-cli 'sin cerrar"))
        self.assertTrue(deny("ls .claude 'sin cerrar"))

    def test_invalid_glob_range_is_invalid_not_allowed(self):
        with self.assertRaises(ProtocolError):
            shell_targets.protected_target("rm -rf [z-a]", "/w", "/w", gates.PROTECTED_PATHS)

    def test_home_is_expanded_both_ways(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = os.path.realpath(tmp)
            root = os.path.join(home, "repo")
            saved = os.environ.get("HOME")
            os.environ["HOME"] = home
            try:
                for command in ("rm -rf ~/repo/.claude", 'rm -rf "$HOME/repo/.claude"'):
                    self.assertIsNotNone(python_answer(command, root, root)["hit"], command)
                for command in ("rm -rf ~/.claude/hooks/x", 'rm -rf "$HOME/.claude/hooks/x"'):
                    self.assertIsNone(python_answer(command, root, root)["hit"], command)
            finally:
                if saved is None:
                    os.environ.pop("HOME")
                else:
                    os.environ["HOME"] = saved


def gate_tree(tmp):
    root = os.path.realpath(tmp)
    os.makedirs(os.path.join(root, ".claude/hooks"))
    os.makedirs(os.path.join(root, "docs"))
    Path(root, ".claude/hooks/tdd-gate.sh").write_text("exit 2\n")
    os.makedirs(os.path.join(root, ".claude/hooks/__pycache__"))  # regenerable: not gate code
    Path(root, ".claude/hooks/__pycache__/x.pyc").write_text("")
    return root


# Cases whose answer depends on the files on disk (gate_tree): find -name and cd to an unknown place.
FS_CASES = [("find . -name '*.sh' -delete", True), ("find . -iname '*.SH' -exec rm -f {} +", True),
            ("find . -name '*.pyc' -delete", False), ('cd "$D" && sed -i s/2/0/ tdd-gate.sh', True),
            ('cd "$D" && rm -f other.sh', False), ("cd docs && rm -f tdd-gate.sh", False)]


class ShellTargetFilesystemTests(unittest.TestCase):
    def test_answers_that_read_the_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = gate_tree(tmp)
            got = [python_answer(c, root, root)["hit"] is not None for c, _ in FS_CASES]
            self.assertEqual(got, [want for _, want in FS_CASES])

    def test_cwd_in_a_subdirectory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = gate_tree(tmp)
            cwd = os.path.join(root, "docs")
            self.assertIsNotNone(python_answer("rm -f ../.claude/hooks/tdd-gate.sh", cwd, root)["hit"])
            self.assertIsNotNone(python_answer("cd .. && rm -f .claude/hooks/tdd-gate.sh", cwd, root)["hit"])
            self.assertIsNone(python_answer("rm -f .claude/hooks/tdd-gate.sh", cwd, root)["hit"])


@needs("bun")
class ShellTargetParityTests(unittest.TestCase):
    def test_same_corpus_same_answers_in_opencode(self):
        ts = ts_answers(CORPUS, "/w", "/w")
        self.assertEqual(len(ts), len(CORPUS))  # zip would hide dropped cases
        for case, got in zip(CORPUS, ts):
            self.assertEqual(got, python_answer(case["command"], "/w", "/w"), case["id"])

    def test_same_symlink_answers_in_opencode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.realpath(tmp)
            os.makedirs(os.path.join(root, ".claude/hooks"))
            os.symlink(os.path.join(root, ".claude/hooks"), os.path.join(root, "alias"))
            cases = [{"command": c} for c in ("echo x > alias/a.sh", "rm -r -f alias", "cp a alias/",
                                              "cat alias/a.sh", "echo x > aliasX/a.sh")]
            want = [python_answer(c["command"], root, root) for c in cases]
            self.assertEqual(ts_answers(cases, root, root), want)
            self.assertEqual([w["hit"] is not None for w in want], [True, True, True, False, False])

    def test_same_tree_answers_in_opencode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = gate_tree(tmp)
            cases = [{"command": c} for c, _ in FS_CASES]
            want = [python_answer(c["command"], root, root) for c in cases]
            self.assertEqual(ts_answers(cases, root, root), want)
            self.assertEqual([w["hit"] is not None for w in want], [w for _, w in FS_CASES])
            sub = os.path.join(root, "docs")
            cases = [{"command": "cd .. && rm -f .claude/hooks/tdd-gate.sh"}, {"command": "rm -f .claude/hooks/x"}]
            self.assertEqual(ts_answers(cases, sub, root), [python_answer(c["command"], sub, root) for c in cases])

    def test_invalid_glob_and_plain_parent_in_opencode(self):
        cases = [{"command": "rm -rf [z-a]"}, {"command": "ls scripts 'sin cerrar"},
                 {"command": "ls scripts/dual-cli 'sin cerrar"}]
        got = ts_answers(cases, "/w", "/w")
        self.assertEqual(got, [python_answer(c["command"], "/w", "/w") for c in cases])
        self.assertEqual([g["gate"] for g in got], [False, False, True])


# Real-repo replay: the adapters of both CLIs with the hooks of .claude/settings.json.
GATE_WRITES = ["echo '{}' > .claude/settings.json", "sed -i 's/exit 2/exit 0/' .claude/hooks/tdd-gate.sh",
               "git checkout -- .codex/hooks.json", "bash -c 'truncate -s 0 opencode.json'"]
UNRELATED = ["ls -la", "cat .claude/settings.json"]


def codex_hook(command, core=CORE, sub=""):
    return subprocess.run([sys.executable, str(core / "codex-hook.py")], capture_output=True, timeout=120,
                          env=dict(os.environ, CLAUDE_PROJECT_DIR=str(core.parents[1])),
                          input=json.dumps({"tool_name": "Bash", "cwd": str(core.parents[1] / sub),
                                            "tool_input": {"command": command}}).encode())


@needs("jq", "bun")
class ShellGateReplayTests(unittest.TestCase):
    def test_gate_writes_from_bash_are_denied_in_both_clis(self):
        for command in GATE_WRITES:
            run = codex_hook(command)
            self.assertEqual(run.returncode, 2, command)
            self.assertIn(b"PROTECTED_GATE_PATH", run.stderr, command)
        for command in UNRELATED:
            run = codex_hook(command)
            self.assertEqual(run.returncode, 0, (command, run.stderr))
        native = [{"tool": "bash", "input": {"command": c}} for c in GATE_WRITES + UNRELATED]
        run = subprocess.run(["bun", str(FIXTURES / "ts_replay.ts"), "--reasons"], capture_output=True,
                             timeout=300, input=json.dumps(native).encode(),
                             env=dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT)))
        self.assertEqual(run.returncode, 0, run.stderr.decode())
        got = json.loads(run.stdout)
        self.assertEqual(got[:len(GATE_WRITES)], [[True, "PROTECTED_GATE_PATH"]] * len(GATE_WRITES))
        self.assertEqual([blocked for blocked, _ in got[len(GATE_WRITES):]], [False] * len(UNRELATED))

    def test_relative_paths_from_a_subdirectory_cwd(self):
        run = codex_hook("sed -i 's/exit 2/exit 0/' ../.claude/hooks/tdd-gate.sh", sub="docs")
        self.assertEqual(run.returncode, 2, run.stderr)
        self.assertIn(b"PROTECTED_GATE_PATH", run.stderr)
        run = codex_hook("cd .. && git checkout -- .codex/hooks.json", sub="docs")
        self.assertEqual(run.returncode, 2, run.stderr)
        run = codex_hook("ls -la ..", sub="docs")
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_the_committed_core_before_this_change_let_them_through(self):
        """Red baseline: the core of e7224df97 (parent of this change) allowed the same commands."""
        base = "e7224df97"
        if subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", base], capture_output=True).returncode:
            # A shallow clone has no baseline: in CI (strict) that is a failure, the red half cannot be skipped.
            if os.environ.get("SAVIA_DUAL_CLI_STRICT") == "1":
                self.fail(f"SAVIA_DUAL_CLI_STRICT=1 and baseline {base} not in this clone")
            self.skipTest("baseline commit not in this clone")
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "base.tar"
            subprocess.run(["git", "-C", str(ROOT), "archive", "-o", str(archive), base,
                            ".claude", ".opencode", "scripts"], check=True, timeout=120)
            with tarfile.open(archive) as tar:
                tar.extractall(Path(tmp) / "repo", filter="tar")
            core = Path(tmp) / "repo/scripts/dual-cli"
            for command in GATE_WRITES:
                run = codex_hook(command, core)
                self.assertEqual((run.returncode, run.stderr), (0, b""), command)


if __name__ == "__main__":
    unittest.main()
