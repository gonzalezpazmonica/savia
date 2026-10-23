"""SE-392 S3: shared gate core, Codex adapter and replay against the OpenCode bridge.

Handlers are real processes. The replay and adapter tests execute the real repo
hooks; nothing here installs hooks, trusts anything or touches CLI state.
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
import gates

BASH = {"tool_name": "Bash", "tool_input": {"command": "echo hi"}}


class GateCoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.settings = self.root / "settings.json"

    def configure(self, *handlers, matcher="Bash", event="PreToolUse"):
        rules = [{"matcher": matcher, "hooks": list(handlers)}]
        self.settings.write_text(json.dumps({"hooks": {event: rules}}))

    def cmd(self, command, **extra):
        return dict(type="command", command=command, **extra)

    def run_gate(self, payload=BASH):
        return gates.evaluate("PreToolUse", payload, settings_path=self.settings, root=self.root)

    def test_exit_2_blocks_and_keeps_reason(self):
        self.configure(self.cmd("echo NOPE >&2; exit 2"))
        decision = self.run_gate()
        self.assertEqual((decision["action"], decision["reason"]), ("deny", "NOPE"))

    def test_crash_and_invalid_output_block(self):
        for command, reason in (("exit 1", "HOOK_FAILURE"), ("echo not-json", "INVALID_HOOK_OUTPUT"),
                                ("echo '[1]'", "INVALID_HOOK_OUTPUT")):
            self.configure(self.cmd(command))
            decision = self.run_gate()
            self.assertEqual((decision["action"], decision["reason"]), ("deny", reason), command)

    def test_json_block_and_ask_never_allow(self):
        for body in ('{"decision":"block"}', '{"continue":false}',
                     '{"hookSpecificOutput":{"permissionDecision":"deny"}}',
                     '{"hookSpecificOutput":{"permissionDecision":"ask"}}'):
            self.configure(self.cmd(f"echo '{body}'"))
            self.assertEqual(self.run_gate()["action"], "deny", body)

    def test_timeout_blocks_and_kills_the_whole_process_group(self):
        pidfile = self.root / "child.pid"
        self.configure(self.cmd(f"sleep 30 & echo $! > {pidfile}; wait", timeout=1))
        started = time.monotonic()
        decision = self.run_gate()
        self.assertEqual((decision["action"], decision["reason"]), ("deny", "HOOK_TIMEOUT"))
        self.assertLess(time.monotonic() - started, 5)
        child = int(pidfile.read_text())
        time.sleep(.2)
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)

    def test_first_block_stops_later_handlers(self):
        marker = self.root / "second-ran"
        self.configure(self.cmd("exit 2"), self.cmd(f"touch {marker}"))
        self.assertEqual(self.run_gate()["action"], "deny")
        self.assertFalse(marker.exists())

    def test_matcher_selects_handlers(self):
        marker = self.root / "ran"
        self.configure(self.cmd(f"touch {marker}; exit 2"), matcher="Edit|Write")
        self.assertEqual(self.run_gate()["action"], "allow")
        self.assertFalse(marker.exists())

    def test_handler_receives_the_event_on_stdin(self):
        self.configure(self.cmd("jq -e '.tool_input.command == \"echo hi\"' >/dev/null"))
        self.assertEqual(self.run_gate()["action"], "allow")

    def test_unexecutable_critical_handler_blocks(self):
        for handler in ({"type": "http", "url": "http://127.0.0.1:1/gate"},
                        {"type": "prompt", "prompt": "x"}):
            self.configure(handler)
            decision = self.run_gate()
            self.assertEqual((decision["action"], decision["reason"]),
                             ("deny", "UNSUPPORTED_CRITICAL_HOOK"))

    def test_async_telemetry_is_skipped_only_outside_authority_events(self):
        self.configure({"type": "prompt", "prompt": "x", "async": True}, event="PostToolUse")
        post = gates.evaluate("PostToolUse", BASH, settings_path=self.settings, root=self.root)
        self.assertEqual(post["action"], "allow")
        self.configure({"type": "prompt", "prompt": "x", "async": True})
        self.assertEqual(self.run_gate()["action"], "deny")

    def test_missing_or_malformed_configuration_blocks(self):
        self.assertEqual(self.run_gate()["reason"], "INVALID_HOOK_CONFIGURATION")
        self.settings.write_text("{not json")
        self.assertEqual(self.run_gate()["reason"], "INVALID_HOOK_CONFIGURATION")

    def test_context_and_updated_input_flow_through(self):
        out = {"hookSpecificOutput": {"additionalContext": "ctx", "updatedInput": {"command": "ls"}}}
        self.configure(self.cmd(f"echo '{json.dumps(out)}'"))
        decision = self.run_gate()
        self.assertEqual((decision["action"], decision["context"], decision["updated_input"]),
                         ("allow", "ctx", {"command": "ls"}))

    def test_handler_that_ignores_stdin_still_decides(self):
        self.configure(self.cmd("exit 2"))
        self.assertEqual(self.run_gate({"tool_name": "Bash",
                                        "tool_input": {"command": "x" * 900000}})["action"], "deny")


class ApplyPatchTests(unittest.TestCase):
    PATCH = ("*** Begin Patch\n*** Add File: a.txt\n+x\n*** Update File: src/b.py\n"
             "*** Move to: src/c.py\n@@\n-a\n+b\n*** Delete File: old.md\n*** End Patch\n")

    def test_split_into_per_file_effects_including_move_and_delete(self):
        ops = [o[:3] for o in gates.apply_patch_operations(self.PATCH, "/w")]
        self.assertEqual(ops, [("Write", "/w/a.txt", "add"), ("Edit", "/w/src/b.py", "update"),
                               ("Write", "/w/src/c.py", "move"), ("Write", "/w/old.md", "delete")])

    def test_malformed_patch_is_invalid(self):
        for body in ("", "no markers", "*** Begin Patch\n*** End Patch\n", None):
            with self.assertRaises(gates.ProtocolError):
                gates.apply_patch_operations(body, "/w")

    def test_any_file_in_a_patch_can_block_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            guard = root / "guard.sh"
            guard.write_text("jq -e '.tool_input.file_path | test(\"secret\")' >/dev/null && "
                             "{ echo 'secret path' >&2; exit 2; }; exit 0\n")
            settings = root / "settings.json"
            settings.write_text(json.dumps({"hooks": {"PreToolUse": [
                {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": f"bash {guard}"}]}]}}))
            patch = lambda name: {"tool_name": "apply_patch", "cwd": str(root),
                                  "tool_input": {"command": f"*** Begin Patch\n*** Add File: ok.txt\n+1\n"
                                                            f"*** Delete File: {name}\n*** End Patch\n"}}
            blocked = gates.evaluate_codex_pretool(patch("secret.txt"), settings_path=settings, root=root)
            self.assertEqual((blocked["action"], blocked["reason"]), ("deny", "secret path"))
            self.assertEqual(gates.evaluate_codex_pretool(
                patch("fine.txt"), settings_path=settings, root=root)["action"], "allow")


class ApplyPatchHardeningTests(unittest.TestCase):
    """Review findings on PR 1339 (P0/P1)."""

    def ops(self, body):
        return gates.apply_patch_operations("*** Begin Patch\n" + body + "*** End Patch\n", "/w")

    def test_indented_tabbed_and_crlf_headers_are_still_gated(self):
        for sep, indent in (("\n", "  "), ("\n", "\t"), ("\r\n", ""), ("\r\n", "  ")):
            body = f"*** Add File: ok.txt{sep}+1{sep}{indent}*** Add File: /etc/evil{sep}+2{sep}"
            paths = [o[1] for o in self.ops(body)]
            self.assertIn("/etc/evil", paths, repr((sep, indent)))

    def test_unknown_header_fails_closed(self):
        with self.assertRaises(gates.ProtocolError):
            self.ops("*** Add File: a\n+1\n*** Frobnicate: b\n")

    def test_events_carry_the_written_content(self):
        payload = {"tool_name": "apply_patch", "cwd": "/w", "tool_input": {"command":
                   "*** Begin Patch\n*** Add File: a.txt\n+line1\n+line2\n"
                   "*** Update File: b.py\n@@\n-old\n+new\n ctx\n*** End Patch\n"}}
        add, upd = gates.normalize_codex_pretool(payload)
        self.assertEqual(add["tool_input"]["content"], "line1\nline2")
        self.assertEqual((upd["tool_input"]["new_string"], upd["tool_input"]["old_string"]), ("new", "old"))

    def test_paths_are_normalized(self):
        ops = gates.apply_patch_operations(
            "*** Begin Patch\n*** Add File: docs/../x.txt\n+1\n*** End Patch\n", "/w")
        self.assertEqual(ops[0][1], "/w/x.txt")

    def test_gate_configuration_and_hooks_are_protected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".claude").mkdir()
            settings = root / ".claude/settings.json"
            settings.write_text(json.dumps({"hooks": {"PreToolUse": []}}))
            for name in (".claude/settings.json", ".opencode/hooks/x.sh", "scripts/dual-cli/gates.py",
                         "docs/../.claude/settings.json"):
                payload = {"tool_name": "apply_patch", "cwd": str(root), "tool_input": {"command":
                           f"*** Begin Patch\n*** Add File: {name}\n+1\n*** End Patch\n"}}
                decision = gates.evaluate_codex_pretool(payload, settings_path=settings, root=root)
                self.assertEqual((decision["action"], decision["reason"]), ("deny", "PROTECTED_GATE_PATH"), name)

    def test_content_reaches_content_handlers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            settings.write_text(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Edit|Write", "hooks": [
                {"type": "command", "command": "jq -e '.tool_input.content|test(\"TOPSECRET\")' >/dev/null && exit 2; exit 0"}]}]}}))
            payload = {"tool_name": "apply_patch", "cwd": str(root), "tool_input": {"command":
                       "*** Begin Patch\n*** Add File: n.txt\n+TOPSECRET\n*** End Patch\n"}}
            self.assertEqual(gates.evaluate_codex_pretool(payload, settings_path=settings, root=root)["action"], "deny")

    def test_ms_timeout_heuristic(self):
        self.assertEqual(gates._timeout({"timeout": 5000}), 5.0)
        self.assertEqual(gates._timeout({"timeout": 5}), 5.0)

    def test_large_payload_is_not_denied_for_env_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            settings.write_text(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                {"type": "command", "command": "cat >/dev/null; exit 0"}]}]}}))
            big = {"tool_name": "Bash", "tool_input": {"command": "x" * 300000}}
            self.assertEqual(gates.evaluate("PreToolUse", big, settings_path=settings, root=root)["action"], "allow")

    def test_bypass_switches_are_not_inherited_by_handlers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            settings = root / "settings.json"
            settings.write_text(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
                {"type": "command", "command": "[ -z \"$SAVIA_PAT_BLOCK$SAVIA_SHIELD_ENABLED$SAVIA_HOOK_PROFILE\" ] || exit 2"}]}]}}))
            old = {k: os.environ.get(k) for k in ("SAVIA_PAT_BLOCK", "SAVIA_SHIELD_ENABLED", "SAVIA_HOOK_PROFILE")}
            os.environ.update(SAVIA_PAT_BLOCK="off", SAVIA_SHIELD_ENABLED="false", SAVIA_HOOK_PROFILE="minimal")
            try:
                d = gates.evaluate("PreToolUse", BASH, settings_path=settings, root=root)
            finally:
                for k, v in old.items():
                    os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
            self.assertEqual(d["action"], "allow")


def codex_hook(payload, root=ROOT, raw=None):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))
    return subprocess.run([sys.executable, str(CORE / "codex-hook.py")], env=env, capture_output=True,
                          input=raw if raw is not None else json.dumps(payload).encode(), timeout=60)


@unittest.skipUnless(shutil.which("jq"), "real hooks need jq")
class CodexAdapterTests(unittest.TestCase):
    def test_real_command_is_blocked_with_exit_2_and_stderr_reason(self):
        run = codex_hook({"tool_name": "Bash", "cwd": str(ROOT),
                          "tool_input": {"command": "git push --force origin main"}})
        self.assertEqual(run.returncode, 2)
        self.assertIn(b"SAVIA_GATE_BLOCK", run.stderr)
        self.assertIn(b"force", run.stderr)

    def test_harmless_command_passes_silently(self):
        run = codex_hook({"tool_name": "Bash", "cwd": str(ROOT), "tool_input": {"command": "ls -la"}})
        self.assertEqual((run.returncode, run.stdout), (0, b""))

    def test_invalid_input_blocks(self):
        for raw in (b"", b"{", b"[]", b'{"tool_name":"Bash"}', b'{"tool_name":"apply_patch","tool_input":{}}'):
            self.assertEqual(codex_hook(None, raw=raw).returncode, 2, raw)


@unittest.skipUnless(shutil.which("jq"), "real hooks need jq")
class CodexAdapterFailClosedTests(unittest.TestCase):
    def run_copy(self, mutate, payload=None):
        with tempfile.TemporaryDirectory() as tmp:
            dst = Path(tmp)
            for f in ("codex-hook.py", "gates.py", "hooks.py", "policy.py", "protocol.py"):
                shutil.copy(CORE / f, dst / f)
            mutate(dst)
            return subprocess.run([sys.executable, str(dst / "codex-hook.py")], capture_output=True,
                                  input=json.dumps(payload or {"tool_name": "Bash", "tool_input": {"command": "ls"}}).encode(),
                                  timeout=60)

    def test_missing_core_module_exits_2(self):
        self.assertEqual(self.run_copy(lambda d: (d / "gates.py").unlink()).returncode, 2)

    def test_syntax_error_in_core_exits_2(self):
        self.assertEqual(self.run_copy(lambda d: (d / "gates.py").write_text("def (:\n")).returncode, 2)

    def test_updated_input_is_denied_not_emitted(self):
        def mutate(d):
            (d / "gates.py").write_text(
                "MAX_OUTPUT=1024\nfrom protocol import decode_json\n"
                "def _deny(r,h=None): return {'action':'deny','reason':r}\n"
                "def evaluate_codex_pretool(p,**k): return {'action':'allow','context':None,'updated_input':{'command':'x'}}\n")
        run = self.run_copy(mutate)
        self.assertEqual(run.returncode, 2)

    def test_project_dir_env_cannot_redirect_the_gate_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / ".claude").mkdir()
            (Path(tmp) / ".claude/settings.json").write_text(json.dumps({"hooks": {"PreToolUse": []}}))
            run = codex_hook({"tool_name": "Bash", "cwd": str(ROOT),
                              "tool_input": {"command": "git push --force origin main"}}, root=tmp)
            self.assertEqual(run.returncode, 2)


@unittest.skipUnless(shutil.which("jq") and shutil.which("bun"), "replay needs bun and jq")
class ReplayEquivalenceTests(unittest.TestCase):
    """AC2 (command half): the same corpus gives the same decision in both cores."""

    def test_same_corpus_same_blocks_in_codex_core_and_opencode_bridge(self):
        corpus = json.loads((ROOT / "tests/dual-cli/fixtures/replay_corpus.json").read_text())
        env = dict(os.environ, CLAUDE_PROJECT_DIR=str(ROOT))
        # OpenCode names the shell tool `bash`; the bridge must still reach the `Bash` hooks.
        native = [{"tool": c["tool"].lower(), "input": c["input"]} for c in corpus]
        ts = subprocess.run(["bun", str(ROOT / "tests/dual-cli/fixtures/ts_replay.ts")], env=env,
                            input=json.dumps(native).encode(), capture_output=True, timeout=120)
        self.assertEqual(ts.returncode, 0, ts.stderr.decode())
        opencode = json.loads(ts.stdout)
        codex = [codex_hook({"tool_name": c["tool"], "cwd": str(ROOT), "tool_input": c["input"]}).returncode == 2
                 for c in corpus]
        self.assertEqual(codex, opencode, [c["id"] for c in corpus])
        self.assertGreaterEqual(sum(codex), 4)
        self.assertGreaterEqual(len(codex) - sum(codex), 3)


if __name__ == "__main__":
    unittest.main()
