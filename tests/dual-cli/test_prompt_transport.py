"""SE-392 S3: transport of `prompt` handlers (AC6), matcher parity and protected gate paths in both cores.

Before this change:
- both cores denied every `prompt` handler as unsupported, so `git commit` could never pass a commit
  gate that declares one, whatever the evaluator would have answered;
- OpenCode read `Bash(git commit*)` as a regex group that never matches, so block-commit-to-main,
  compliance-gate, prompt-hook-commit and the prompt handler did not run there at all;
- `Bash(bash*memory-store*save*)` matched only the literal stars in the Codex core;
- OpenCode protected the gate files only with SAVIA_GATES_PIN=1, Codex always.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
FIXTURES = ROOT / "tests/dual-cli/fixtures"
sys.path.insert(0, str(CORE))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gates
from required_tools import needs
from hooks import _matcher_applies


def bun(script, data, *args):
    run = subprocess.run(["bun", str(FIXTURES / script), *args], input=json.dumps(data).encode(),
                         capture_output=True, timeout=300,
                         env=dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT)))
    if run.returncode != 0:
        raise AssertionError(run.stderr.decode())
    return json.loads(run.stdout)


def python_prompt_decision(case):
    with tempfile.TemporaryDirectory() as tmp:
        handler = {"type": "prompt", "prompt": "Valida: $ARGUMENTS", "timeout": case.get("timeout", 5)}
        if "model" in case:
            handler["model"] = case["model"]
        settings = Path(tmp) / "settings.json"
        settings.write_text(json.dumps({"hooks": {"PreToolUse": [
            {"matcher": "Bash(git commit*)", "hooks": [handler]}]}}))
        env = dict(case.get("parent_env", {}), SAVIA_PROMPT_HOOK_CMD=case["evaluator"])
        saved = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        try:
            decision = gates.evaluate("PreToolUse", {"tool_name": "Bash", "tool_input": {
                "command": case["command"]}}, settings_path=settings, root=Path(tmp))
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
    return {"action": decision["action"], "reason": decision["reason"]}


class PromptTransportTests(unittest.TestCase):
    """AC6 in the Codex core: every failure of the evaluator denies; an unrelated call continues."""

    def test_corpus_decisions_in_the_codex_core(self):
        corpus = json.loads((FIXTURES / "prompt_replay_corpus.json").read_text())
        for case in corpus:
            got = python_prompt_decision(case)
            self.assertEqual(got, {"action": case["action"], "reason": case["reason"]}, case["id"])
        self.assertGreaterEqual(sum(c["action"] == "deny" for c in corpus), 6)
        self.assertGreaterEqual(sum(c["action"] == "allow" for c in corpus), 3)

    def test_render_prompt_follows_claude_code(self):
        self.assertEqual(gates.render_prompt("A $ARGUMENTS B", '{"x":1}'), 'A {"x":1} B')
        self.assertEqual(gates.render_prompt("Sin marcador", '{"x":1}'), 'Sin marcador\n\n{"x":1}')

    def test_invalid_prompt_timeout_is_a_configuration_error(self):
        case = {"command": "git commit -m x", "evaluator": "echo '{\"ok\": true}'", "timeout": -1}
        self.assertEqual(python_prompt_decision(case),
                         {"action": "deny", "reason": "INVALID_HOOK_CONFIGURATION"})


@needs("bun")
class PromptReplayParityTests(unittest.TestCase):
    def test_same_prompt_corpus_same_decisions_in_opencode(self):
        corpus = json.loads((FIXTURES / "prompt_replay_corpus.json").read_text())
        opencode = bun("ts_prompt_replay.ts", corpus)
        expected = [{"action": c["action"], "reason": c["reason"]} for c in corpus]
        self.assertEqual(len(opencode), len(corpus))  # zip would hide cases the replay dropped
        for case, got, want in zip(corpus, opencode, expected):
            self.assertEqual(got, want, case["id"])


def _settings_matchers():
    data = json.loads((ROOT / ".claude/settings.json").read_text())
    return sorted({e["matcher"] for entries in data["hooks"].values() for e in entries
                   if e.get("matcher")})


HEREDOC_COMMIT = "git commit -m \"$(cat <<'EOF'\nfeat: x\n\ncuerpo\nEOF\n)\""
COMMITS = ["git commit -m 'feat: x'", "git commit -m 'feat: x\n\ncuerpo'", HEREDOC_COMMIT]
CALLS = [*(("Bash", c) for c in COMMITS), ("Bash", "git status"), ("Bash", "gh pr create --draft"),
         ("Bash", "gh pr merge 12"), ("Bash", "bash scripts/memory-store.sh save --type x"),
         ("Bash", "bash scripts/memory-store.sh recall x"), ("Edit", None), ("Write", None),
         ("Read", None), ("Task", None), ("Agent", None), ("mcp__vaults__search", None)]


class MatcherSemanticsTests(unittest.TestCase):
    def matches(self, matcher, tool, command=None):
        return _matcher_applies(matcher, {"tool_name": tool, "tool_input": {} if command is None
                                          else {"command": command}})

    def test_command_scoped_glob_with_inner_stars(self):
        m = "Bash(bash*memory-store*save*)"
        self.assertTrue(self.matches(m, "Bash", "bash scripts/memory-store.sh save --type x"))
        self.assertFalse(self.matches(m, "Bash", "bash scripts/memory-store.sh recall x"))

    def test_alternation_of_command_scoped_matchers(self):
        m = "Bash(gh pr create*)|Bash(gh pr merge*)"
        self.assertTrue(self.matches(m, "Bash", "gh pr merge 12"))
        self.assertTrue(self.matches(m, "Bash", "gh pr create --draft"))
        self.assertFalse(self.matches(m, "Bash", "gh pr view 12"))

    def test_multiline_command_still_matches(self):
        # The usual agent commit is a heredoc: `.` must cross newlines or every commit gate is skipped.
        for command in COMMITS[1:]:
            self.assertTrue(self.matches("Bash(git commit*)", "Bash", command), command)
        self.assertFalse(self.matches("Bash(git commit*)", "Bash", "git status\ngit commit -m x"))

    def test_scoped_text_is_literal(self):
        self.assertFalse(self.matches("Bash(git commit*)", "Bash", "gitXcommit"))
        self.assertTrue(self.matches("Edit|Write", "Write"))
        self.assertFalse(self.matches("Edit|Write", "Read"))


@needs("bun")
class CoreParityTests(unittest.TestCase):
    def test_every_settings_matcher_selects_the_same_calls_in_both_cores(self):
        cases = [{"matcher": m, "tool": t, **({} if c is None else {"command": c})}
                 for m in _settings_matchers() for t, c in CALLS]
        ts = bun("ts_matchers.ts", {"matchers": cases, "paths": []})["matches"]
        py = [_matcher_applies(c["matcher"], {"tool_name": c["tool"], "tool_input":
                                              {"command": c["command"]} if "command" in c else {}})
              for c in cases]
        self.assertEqual((len(ts), len(py)), (len(cases), len(cases)))  # zip would hide dropped cases
        diverging = [(c["matcher"], c["tool"], c.get("command")) for c, a, b in zip(cases, py, ts) if a != b]
        self.assertEqual(diverging, [])
        commit = [b for c, b in zip(cases, ts) if c["matcher"] == "Bash(git commit*)"]
        self.assertEqual(commit, [c in COMMITS for _t, c in CALLS])  # every `git commit`, nothing else

    def test_tool_inputs_that_name_other_tools_select_the_same_hooks(self):
        # OpenCode also matched the serialized payload of a tool call: a Read of docs/Bash.md ran the
        # Bash hooks, a Grep for "Agent" the Agent hooks. Codex only matches the tool and its command.
        inputs = [("Read", {"file_path": "docs/Bash-notes.md"}), ("Grep", {"pattern": "Agent|Task"}),
                  ("Write", {"file_path": "x.md", "content": "Edit Read WebFetch mcp__vault"}),
                  ("Glob", {"pattern": "**/Write*.ts"}), ("Bash", {"command": "ls", "description": "Edit"}),
                  ("mcp__vaults__search", {"query": "Bash(git commit -m x)"})]
        cases = [{"matcher": m, "tool": t, "input": i} for m in _settings_matchers() for t, i in inputs]
        ts = bun("ts_matchers.ts", {"matchers": cases, "paths": []})["matches"]
        py = [_matcher_applies(c["matcher"], {"tool_name": c["tool"], "tool_input": c["input"]}) for c in cases]
        self.assertEqual(len(ts), len(cases))
        diverging = [(c["matcher"], c["tool"]) for c, a, b in zip(cases, py, ts) if a != b]
        self.assertEqual(diverging, [])
        read_bash = [b for c, b in zip(cases, ts) if c["matcher"] == "Bash" and c["tool"] == "Read"]
        self.assertEqual(read_bash, [False])

    def test_protected_gate_paths_are_the_same_list_and_decision(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.realpath(tmp)
            os.makedirs(os.path.join(root, ".claude/hooks"))
            os.symlink(os.path.join(root, ".claude/hooks"), os.path.join(root, "alias"))
            paths = [os.path.join(root, p) for p in (
                ".claude/settings.json", ".claude/hooks/x.sh", "alias/x.sh", ".opencode/plugins/a.ts",
                "scripts/opencode-plugin/savia-gates/index.ts", "scripts/dual-cli/gates.py",
                ".codex/hooks.json", "opencode.json", ".opencode/package.json",
                # OpenCode also reads opencode.jsonc, .opencode/opencode.json(c) and the singular .opencode/plugin/
                "opencode.jsonc", ".opencode/opencode.json", ".opencode/opencode.jsonc", ".opencode/plugin/x.ts",
                "src/app.py", ".claude/settingsXjson", "scripts/dual-cli-notes.md", "opencode.jsonc.bak",
                ".opencode/plugin-notes.md")]
            got = bun("ts_matchers.ts", {"matchers": [], "paths": [{"path": p, "root": root} for p in paths]})
            self.assertEqual(got["list"], list(gates.PROTECTED_PATHS))
            want = [gates.is_protected(p, root) for p in paths]
            self.assertEqual(got["protected"], want)
            self.assertEqual(want, [True] * 13 + [False] * 5)


@needs("bun", "jq")
class ProtectedPathReplayTests(unittest.TestCase):
    """The real repo: OpenCode write/edit/apply_patch and Codex apply_patch on gate files are denied."""

    def test_gate_files_cannot_be_rewritten_from_either_cli(self):
        patch = "*** Begin Patch\n*** Update File: .claude/settings.json\n@@\n-a\n+b\n*** End Patch\n"
        codex = subprocess.run([sys.executable, str(CORE / "codex-hook.py")], capture_output=True,
                               timeout=120, input=json.dumps({"tool_name": "apply_patch", "tool_input":
                                                              {"command": patch}, "cwd": str(ROOT)}).encode())
        self.assertEqual(codex.returncode, 2)
        self.assertIn(b"PROTECTED_GATE_PATH", codex.stderr)
        native = [
            {"tool": "write", "input": {"filePath": str(ROOT / "scripts/opencode-plugin/savia-gates/lib/gates.ts"),
                                        "content": "x"}},
            {"tool": "edit", "input": {"filePath": str(ROOT / ".opencode/hooks/tdd-gate.sh"),
                                       "oldString": "a", "newString": "b"}},
            {"tool": "apply_patch", "input": {"patchText": patch}},
        ]
        self.assertEqual(bun("ts_replay.ts", native, "--reasons"), [[True, "PROTECTED_GATE_PATH"]] * 3)


class RequiredToolsTests(unittest.TestCase):
    """CI sets SAVIA_DUAL_CLI_STRICT=1: a missing bun fails the parity suite instead of skipping it."""

    def run_probe(self, strict):
        saved = os.environ.get("SAVIA_DUAL_CLI_STRICT")
        os.environ["SAVIA_DUAL_CLI_STRICT"] = "1" if strict else "0"
        try:
            probe = needs("savia-no-such-tool")(type("Probe", (unittest.TestCase,), {"test_x": lambda self: None}))
        finally:
            if saved is None:
                os.environ.pop("SAVIA_DUAL_CLI_STRICT", None)
            else:
                os.environ["SAVIA_DUAL_CLI_STRICT"] = saved
        result = unittest.TestResult()
        unittest.defaultTestLoader.loadTestsFromTestCase(probe).run(result)
        return result

    def test_missing_tool_fails_in_strict_mode(self):
        result = self.run_probe(strict=True)
        self.assertEqual((len(result.errors), len(result.skipped)), (1, 0))

    def test_missing_tool_skips_outside_strict_mode(self):
        result = self.run_probe(strict=False)
        self.assertEqual((len(result.errors), len(result.skipped)), (0, 1))


if __name__ == "__main__":
    unittest.main()
