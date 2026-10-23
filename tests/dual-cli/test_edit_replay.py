"""SE-392 S3: AC2 edit half — the same edits, as each CLI really sends them, get the same decisions.

Codex sends `apply_patch` bodies to codex-hook.py; OpenCode sends `write`/`edit` with `filePath` or
`apply_patch` with `patchText` to savia-gates. Both reach the real hooks of `.claude/settings.json`.
Before the OpenCode bridge spoke the Claude Code vocabulary (lib/hook-vocabulary.ts), four of the
five blocking cases below passed in OpenCode: tdd-gate compares `tool_name == "Edit"` and reads
`.tool_input.file_path`, and `apply_patch` matched no Edit|Write hook.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
FIXTURES = ROOT / "tests/dual-cli/fixtures"
sys.path.insert(0, str(CORE))
import gates
from protocol import ProtocolError


def bun(script, data):
    run = subprocess.run(["bun", str(FIXTURES / script)], input=json.dumps(data).encode(),
                         capture_output=True, timeout=300,
                         env=dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT)))
    if run.returncode != 0:
        raise AssertionError(run.stderr.decode())
    return json.loads(run.stdout)


def codex_blocks(event):
    run = subprocess.run([sys.executable, str(CORE / "codex-hook.py")], capture_output=True, timeout=120,
                         input=json.dumps(dict(event, cwd=str(ROOT))).encode())
    return run.returncode == 2


@unittest.skipUnless(shutil.which("jq") and shutil.which("bun"), "replay needs bun and jq")
class EditReplayEquivalenceTests(unittest.TestCase):
    def test_same_edits_same_decisions_in_codex_and_opencode(self):
        corpus = json.loads((FIXTURES / "edit_replay_corpus.json").read_text())
        native = [json.loads(json.dumps(c["opencode"]).replace("@ROOT@", str(ROOT))) for c in corpus]
        opencode = bun("ts_replay.ts", native)
        codex = [codex_blocks(c["codex"]) for c in corpus]
        expected = [c["blocked"] for c in corpus]
        ids = [c["id"] for c in corpus]
        self.assertEqual(codex, expected, ids)
        self.assertEqual(opencode, expected, ids)
        self.assertGreaterEqual(sum(expected), 4)
        self.assertGreaterEqual(len(expected) - sum(expected), 3)


PATCHES = [
    "*** Begin Patch\n*** Add File: a.txt\n+uno\n+dos\n*** End Patch\n",
    "*** Begin Patch\n*** Update File: src/b.py\n*** Move to: src/c.py\n@@\n-x\n+y\n*** End Patch",
    "*** Begin Patch\r\n  *** Delete File: ../fuera.txt\r\n*** End Patch\r\n",
    "*** Begin Patch\n\t*** Add File: /abs/d.md\n+z\n*** End of File\n*** End Patch\n",
    "*** Begin Patch\n*** Add File: e.txt\n+a *** Add File: f.txt\n+b\n*** End Patch\n",
    "*** Begin Patch\n*** Frobnicate File: x\n*** End Patch\n",
    "*** Begin Patch\n*** Add File: \n*** End Patch\n",
    "sin cabecera",
    None,
]


@unittest.skipUnless(shutil.which("bun"), "parity needs bun")
class PatchParserParityTests(unittest.TestCase):
    def test_opencode_port_splits_patches_exactly_like_the_codex_core(self):
        cases = [{"patch": p, "cwd": "/w/repo"} for p in PATCHES]
        ported = bun("ts_patch_ops.ts", cases)
        for case, got in zip(cases, ported):
            try:
                want = [list(op) for op in gates.apply_patch_operations(case["patch"], case["cwd"])]
            except ProtocolError:
                want = "INVALID_EVENT"
            self.assertEqual(got, want, case["patch"])
        self.assertGreaterEqual(sum(isinstance(g, list) for g in ported), 5)


if __name__ == "__main__":
    unittest.main()
