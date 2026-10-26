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


# Real-repo replay: the adapters of both CLIs with the hooks of .claude/settings.json.
GATE_WRITES = ["echo '{}' > .claude/settings.json", "sed -i 's/exit 2/exit 0/' .claude/hooks/tdd-gate.sh",
               "git checkout -- .codex/hooks.json", "bash -c 'truncate -s 0 opencode.json'"]
UNRELATED = ["ls -la", "cat .claude/settings.json"]


def codex_hook(command, core=CORE):
    return subprocess.run([sys.executable, str(core / "codex-hook.py")], capture_output=True, timeout=120,
                          env=dict(os.environ, CLAUDE_PROJECT_DIR=str(core.parents[1])),
                          input=json.dumps({"tool_name": "Bash", "cwd": str(core.parents[1]),
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

    def test_the_committed_core_before_this_change_let_them_through(self):
        """Red baseline: the core of e7224df97 (parent of this change) allowed the same commands."""
        base = "e7224df97"
        if subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", base], capture_output=True).returncode:
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
