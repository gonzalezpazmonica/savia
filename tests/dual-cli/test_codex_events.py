"""SE-392 S3: every Codex hook event through the shared gates, and lifecycle parity with OpenCode.

Handlers are real processes in a temporary root; the last class runs the real repo hooks.
Nothing here installs hooks, trusts anything or touches CLI state.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
sys.path.insert(0, str(CORE))
import codex_events
import gates
from policy import hook_decision

N1_CONTEXT = "echo '{\"hookSpecificOutput\":{\"additionalContext\":\"public\",\"saviaLevel\":\"N1\"}}'"
BARE_CONTEXT = "echo '{\"hookSpecificOutput\":{\"additionalContext\":\"private\"}}'"
PATCH = "*** Begin Patch\n*** Update File: a.py\n-old\n+new\n*** Add File: b.txt\n+hi\n*** End Patch\n"


class CodexEventTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.settings = self.root / "settings.json"

    def configure(self, event, *commands, matcher=None, **extra):
        rule = {"hooks": [dict(type="command", command=c, **extra) for c in commands]}
        if matcher is not None:
            rule["matcher"] = matcher
        self.settings.write_text(json.dumps({"hooks": {event: [rule]}}))

    def handle(self, event, **fields):
        payload = dict(hook_event_name=event, session_id="s", cwd=str(self.root), **fields)
        return codex_events.handle(payload, settings_path=self.settings, root=self.root)

    def test_user_prompt_block_is_exit_2_and_prompt_reaches_handler(self):
        self.configure("UserPromptSubmit", "jq -e '.prompt|test(\"rm -rf\")' >/dev/null && { echo NOPE >&2; exit 2; }; exit 0")
        self.assertEqual(self.handle("UserPromptSubmit", prompt="please rm -rf /")[0], 2)
        self.assertEqual(self.handle("UserPromptSubmit", prompt="hola"), (0, "", ""))

    def test_only_context_declared_n1_is_shipped(self):
        self.configure("UserPromptSubmit", N1_CONTEXT, BARE_CONTEXT, "echo plain-text")
        code, out, _ = self.handle("UserPromptSubmit", prompt="x")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["hookSpecificOutput"]["additionalContext"], "public")
        self.configure("UserPromptSubmit", BARE_CONTEXT, "echo plain-text")
        self.assertEqual(self.handle("UserPromptSubmit", prompt="x"), (0, "", ""))

    def test_lifecycle_failure_warns_and_never_blocks(self):
        for event in ("SessionStart", "SubagentStart", "PreCompact", "PostCompact"):
            self.configure(event, "echo BOOM >&2; exit 2")
            code, out, _ = self.handle(event)
            self.assertEqual(code, 0, event)
            self.assertEqual(json.loads(out), {"systemMessage": f"Savia hook {event}: BOOM"}, event)

    def test_stop_always_answers_json_and_never_forces_continuation(self):
        for command in ("exit 0", "echo '{\"decision\":\"block\",\"reason\":\"more\"}'", "exit 2"):
            for event in ("Stop", "SubagentStop"):
                self.configure(event, command)
                code, out, _ = self.handle(event, stop_hook_active=False)
                body = json.loads(out)
                self.assertEqual(code, 0, command)
                self.assertNotIn("decision", body, command)
                self.assertNotIn("continue", body, command)

    def test_permission_request_denies_but_never_allows(self):
        self.configure("PermissionRequest", "exit 0", matcher="Bash")
        self.assertEqual(self.handle("PermissionRequest", tool_name="Bash", tool_input={"command": "ls"}), (0, "", ""))
        self.configure("PermissionRequest", "echo NO >&2; exit 2", matcher="Bash")
        code, out, _ = self.handle("PermissionRequest", tool_name="Bash", tool_input={"command": "ls"})
        decision = json.loads(out)["hookSpecificOutput"]["decision"]
        self.assertEqual((code, decision["behavior"]), (0, "deny"))
        self.assertNotIn("allow", out)

    def test_permission_request_refuses_protected_gate_paths(self):
        self.configure("PermissionRequest", "exit 0")
        patch = "*** Begin Patch\n*** Add File: .codex/hooks.json\n+{}\n*** End Patch\n"
        code, out, _ = self.handle("PermissionRequest", tool_name="apply_patch", tool_input={"command": patch})
        self.assertIn("PROTECTED_GATE_PATH", json.loads(out)["hookSpecificOutput"]["decision"]["message"])

    def test_post_tool_use_sees_one_claude_event_per_patched_file(self):
        log = self.root / "seen.jsonl"
        self.configure("PostToolUse", f"jq -c '[.tool_name,.tool_input.file_path]' >> {log}", matcher="Edit|Write")
        code, out, _ = self.handle("PostToolUse", tool_name="apply_patch", tool_input={"command": PATCH},
                                   tool_response={"ok": True})
        seen = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual((code, out), (0, ""))
        self.assertEqual(seen, [["Edit", str(self.root / "a.py")], ["Write", str(self.root / "b.txt")]])

    def test_post_tool_use_block_is_only_a_warning(self):
        self.configure("PostToolUse", "echo LATE >&2; exit 2", matcher="Bash")
        code, out, _ = self.handle("PostToolUse", tool_name="Bash", tool_input={"command": "ls"})
        self.assertEqual((code, json.loads(out)), (0, {"systemMessage": "Savia hook PostToolUse: LATE"}))

    def test_async_handlers_run_detached_and_are_not_awaited(self):
        marker = self.root / "async-ran"
        self.configure("PostToolUse", f"sleep 1; touch {marker}", matcher="Bash", **{"async": True})
        started = time.monotonic()
        self.assertEqual(self.handle("PostToolUse", tool_name="Bash", tool_input={"command": "ls"}), (0, "", ""))
        self.assertLess(time.monotonic() - started, 0.9)
        deadline = time.monotonic() + 10
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertTrue(marker.exists())

    def test_async_handlers_are_skipped_without_spawn(self):
        marker = self.root / "async-ran"
        self.configure("PostToolUse", f"touch {marker}", matcher="Bash", **{"async": True})
        gates.evaluate("PostToolUse", {"tool_name": "Bash", "tool_input": {}}, settings_path=self.settings, root=self.root)
        time.sleep(0.5)
        self.assertFalse(marker.exists())

    def test_unknown_event_fails_closed_and_interrupt_runs_nothing(self):
        self.assertEqual(self.handle("NotAnEvent")[0], 2)
        self.assertEqual(codex_events.handle([], settings_path=self.settings, root=self.root)[0], 2)
        self.settings.write_text("{broken")
        self.assertEqual(self.handle("Interrupt"), (0, "", ""))

    def test_unreadable_configuration_blocks_prompts(self):
        self.settings.write_text("{broken")
        self.assertEqual(self.handle("UserPromptSubmit", prompt="x")[0], 2)


class PlainOutputTests(unittest.TestCase):
    """Plain stdout: context for SessionStart/UserPromptSubmit/SubagentStart, never a block off-authority."""

    def test_plain_text_is_context_where_codex_and_claude_read_it_so(self):
        result = hook_decision(0, "[SPEC-SH02] aviso\n", plain="context")
        self.assertEqual((result["action"], result["context"], result["level"]), ("allow", "[SPEC-SH02] aviso", None))
        self.assertEqual(hook_decision(0, "noise", plain="ignore")["context"], None)

    def test_authority_events_still_reject_plain_text_and_broken_json(self):
        self.assertEqual(hook_decision(0, "plain")["reason"], "INVALID_HOOK_OUTPUT")
        for plain in ("context", "ignore"):
            self.assertEqual(hook_decision(0, "{broken", plain=plain)["reason"], "INVALID_HOOK_OUTPUT")

    def test_plain_first_handler_no_longer_stops_later_session_start_handlers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "second-ran"
            settings = root / "settings.json"
            settings.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [
                {"type": "command", "command": "echo 'PM-Workspace Init'"},
                {"type": "command", "command": f"touch {marker}"}]}]}}))
            decision = gates.evaluate("SessionStart", {}, settings_path=settings, root=root)
            self.assertEqual(decision["action"], "allow")
            self.assertTrue(marker.exists())


LIFECYCLE_CASES = [
    ("SessionStart", "echo 'plain init'"), ("SessionStart", N1_CONTEXT), ("SessionStart", "echo '{broken'"),
    ("UserPromptSubmit", "echo 'plain ctx'"), ("UserPromptSubmit", "exit 2"), ("UserPromptSubmit", "echo '[SPEC-SH02] aviso'"),
    ("PreCompact", "echo 'backup done'"), ("Stop", "exit 1"), ("Stop", "echo '{\"continue\":false}'"),
    ("SubagentStart", "echo 'sub ctx'"), ("PreToolUse", "echo 'plain'"),
]


@unittest.skipUnless(shutil.which("bun"), "replay needs bun")
class LifecycleReplayTests(unittest.TestCase):
    """The same handlers give the same block and context in the Codex core and the OpenCode bridge."""

    def test_same_lifecycle_decisions_in_both_cores(self):
        python, ts = [], []
        for event, command in LIFECYCLE_CASES:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / ".claude").mkdir()
                settings = root / ".claude/settings.json"
                settings.write_text(json.dumps({"hooks": {event: [{"hooks": [
                    {"type": "command", "command": command}]}]}}))
                d = gates.evaluate(event, {"hook_event_name": event}, settings_path=settings, root=root)
                python.append({"blocked": d["action"] != "allow", "contexts": [c["text"] for c in d["contexts"]]})
                run = subprocess.run(["bun", str(ROOT / "tests/dual-cli/fixtures/ts_lifecycle_replay.ts")],
                                     env=dict(os.environ, CLAUDE_PROJECT_DIR=str(root)), capture_output=True,
                                     input=json.dumps([{"event": event, "payload": {}}]).encode(), timeout=60)
                self.assertEqual(run.returncode, 0, run.stderr.decode())
                ts.extend(json.loads(run.stdout))
        self.assertEqual(python, ts, [f"{e}: {c}" for e, c in LIFECYCLE_CASES])
        self.assertEqual([p["blocked"] for p in python],
                         [False, False, True, False, True, False, False, True, True, False, True])


def codex_hook(payload):
    return subprocess.run([sys.executable, str(CORE / "codex-hook.py")], capture_output=True,
                          input=json.dumps(payload).encode(), timeout=120)


@unittest.skipUnless(shutil.which("jq"), "real hooks need jq")
class RealHooksCodexEventsTests(unittest.TestCase):
    """The repo's own handlers, through the adapter, as a live Codex would call it."""

    def base(self, event, **fields):
        return dict(hook_event_name=event, session_id="se392-test", cwd=str(ROOT),
                    transcript_path=None, model="test", **fields)

    def test_harmless_prompt_is_not_blocked(self):
        run = codex_hook(self.base("UserPromptSubmit", turn_id="t", prompt="estado del sprint"))
        self.assertEqual(run.returncode, 0, run.stderr.decode())

    def test_session_start_runs_every_handler_without_invalid_output(self):
        run = codex_hook(self.base("SessionStart", source="startup"))
        self.assertEqual(run.returncode, 0)
        self.assertNotIn(b"INVALID_HOOK_OUTPUT", run.stdout)


if __name__ == "__main__":
    unittest.main()
