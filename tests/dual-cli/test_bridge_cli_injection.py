"""SE-396 A01b: inject the selected CLI adapter into Savia Bridge."""
import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_a01b", ROOT / "scripts" / "savia-bridge.py"
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

from bridge_cli_adapters import CodexCliAdapter, OpenCodeCliAdapter  # noqa: E402


class FakeProcess:
    def __init__(self, lines, returncode=0, stderr=""):
        self.stdout = iter(lines)
        self.stderr = io.StringIO(stderr)
        self.returncode = returncode
        self.pid = 42

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        self.returncode = -9


class BridgeCliInjectionTests(unittest.TestCase):
    def setUp(self):
        bridge._selected_cli_adapter_id = "claude"
        bridge._selected_cli_adapter = None
        bridge._adapter_native_sessions.clear()

    def test_explicit_codex_selection_never_discovers_claude(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        with patch.object(bridge, "find_claude_cli", side_effect=AssertionError):
            result = bridge.configure_cli_adapter(
                "codex", adapter_factory=lambda _adapter_id: adapter
            )
        self.assertEqual(result["status"], "AVAILABLE")
        self.assertEqual(bridge._selected_cli_adapter_id, "codex")

    def test_default_claude_selection_preserves_legacy_discovery(self):
        with patch.object(bridge, "find_claude_cli", return_value="/bin/claude"):
            result = bridge.configure_cli_adapter("claude")
        self.assertEqual(result["status"], "AVAILABLE")
        self.assertEqual(result["binary"], "/bin/claude")

    def test_unavailable_selected_adapter_fails_closed(self):
        adapter = CodexCliAdapter(which=lambda _name: None)
        with self.assertRaisesRegex(RuntimeError, "UNAVAILABLE"):
            bridge.configure_cli_adapter(
                "codex", adapter_factory=lambda _adapter_id: adapter
            )

    def test_uncertified_opencode_selection_remains_not_verified(self):
        adapter = OpenCodeCliAdapter(binary="/bin/opencode")
        with self.assertRaisesRegex(RuntimeError, "NOT_VERIFIED"):
            bridge.configure_cli_adapter(
                "opencode", adapter_factory=lambda _adapter_id: adapter
            )

    def test_parser_exposes_explicit_adapter_with_claude_default(self):
        parser = bridge.build_argument_parser()
        self.assertEqual(parser.parse_args([]).cli_adapter, "claude")
        self.assertEqual(parser.parse_args(["--cli-adapter", "codex"]).cli_adapter,
                         "codex")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["--cli-adapter", "unknown"])

    def test_codex_stream_uses_native_thread_for_second_turn(self):
        bridge.configure_cli_adapter(
            "codex", adapter_factory=lambda _adapter_id: CodexCliAdapter(
                binary="/bin/codex"
            )
        )
        commands = []
        processes = [
            FakeProcess([
                '{"type":"thread.started","thread_id":"native-1"}\n',
                '{"type":"item.completed","item":{"type":"agent_message",'
                '"text":"first"}}\n',
                '{"type":"turn.completed","usage":{}}\n',
            ]),
            FakeProcess([
                '{"type":"item.completed","item":{"type":"agent_message",'
                '"text":"second"}}\n',
                '{"type":"turn.completed","usage":{}}\n',
            ]),
        ]

        def popen(command, **_kwargs):
            commands.append(command)
            return processes.pop(0)

        with patch.object(bridge.subprocess, "Popen", side_effect=popen):
            first = list(bridge.stream_cli_response("one", "bridge-1"))
            second = list(bridge.stream_cli_response("two", "bridge-1"))

        self.assertEqual([event["type"] for event in first], ["text", "done"])
        self.assertEqual([event["type"] for event in second], ["text", "done"])
        self.assertIn(bridge._workspace_dir, commands[0])
        self.assertNotIn("bridge-1", commands[1])
        self.assertIn("native-1", commands[1])

    def test_unknown_event_cannot_synthesize_done(self):
        bridge.configure_cli_adapter(
            "codex", adapter_factory=lambda _adapter_id: CodexCliAdapter(
                binary="/bin/codex"
            )
        )
        process = FakeProcess(['{"type":"future.event"}\n'])
        with patch.object(bridge.subprocess, "Popen", return_value=process):
            events = list(bridge.stream_cli_response("one"))
        self.assertEqual(events[-1]["type"], "error")
        self.assertNotIn("done", [event["type"] for event in events])

    def test_nonzero_exit_invalidates_native_ref_and_done(self):
        bridge.configure_cli_adapter(
            "codex", adapter_factory=lambda _adapter_id: CodexCliAdapter(
                binary="/bin/codex"
            )
        )
        process = FakeProcess([
            '{"type":"thread.started","thread_id":"native-bad"}\n',
            '{"type":"turn.completed","usage":{}}\n',
        ], returncode=1, stderr="failed")
        with patch.object(bridge, "_get_session_workdir", return_value="/tmp/work"), \
                patch.object(bridge.subprocess, "Popen", return_value=process):
            events = list(bridge.stream_cli_response("one", "bridge-1"))
        self.assertNotIn("done", [event["type"] for event in events])
        self.assertNotIn(("codex", "bridge-1"), bridge._adapter_native_sessions)

    def test_interactive_support_remains_claude_only(self):
        self.assertTrue(bridge.cli_adapter_supports_interactive("claude"))
        self.assertFalse(bridge.cli_adapter_supports_interactive("codex"))
        self.assertFalse(bridge.cli_adapter_supports_interactive("opencode"))


if __name__ == "__main__":
    unittest.main()
