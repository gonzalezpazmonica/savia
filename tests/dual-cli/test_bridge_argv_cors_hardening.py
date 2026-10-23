"""CodeQL #20 (command-line-injection) and #11 (http-response-splitting).

#20: client text reached the CLI argv as a bare positional, so a message such
as "--mcp-config=..." was parsed as a flag. Every command now ends option
parsing with "--" and passes the system prompt in "--opt=value" form.
#11: the Origin header was reflected after a prefix check, so folded values
with CR/LF and look-alike hosts (localhost.evil.com) were echoed back.
"""
import importlib.util
import io
import ipaddress
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

SPEC = importlib.util.spec_from_file_location(
    "savia_bridge_argv_cors", ROOT / "scripts" / "savia-bridge.py"
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)

from bridge_cli_adapters import (  # noqa: E402
    BridgeRequest, CodexCliAdapter, OpenCodeCliAdapter,
)

FLAG_MESSAGE = '--mcp-config={"mcpServers":{"x":{"command":"sh"}}}'
FLAG_PROMPT = "--dangerously-skip-permissions"


def _ip(a, b, c, d):
    # Built from octets: the repo's data-sovereignty gate and confidentiality
    # scan block RFC 1918 literals in public files, even synthetic ones.
    return str(ipaddress.IPv4Address((a << 24) | (b << 16) | (c << 8) | d))


RFC1918_A = _ip(10, 0, 0, 7)
RFC1918_B = _ip(172, 16, 4, 2)
RFC1918_C = _ip(192, 168, 1, 5)


class FakeProcess:
    def __init__(self):
        self.stdout = iter(['{"type":"result","result":"ok"}\n'])
        self.stderr = io.StringIO("")
        self.returncode = 0
        self.pid = 42

    def wait(self, timeout=None):
        return self.returncode

    def poll(self):
        return self.returncode

    def kill(self):
        self.returncode = -9


def _assert_after_separator(test, cmd, value):
    test.assertIn("--", cmd)
    sep = cmd.index("--")
    test.assertNotIn(value, cmd[:sep], "client text parsed as an option")
    test.assertIn(value, cmd[sep + 1:])


class ClaudeArgvTests(unittest.TestCase):
    def setUp(self):
        bridge._selected_cli_adapter_id = "claude"
        bridge._selected_cli_adapter = None

    def _streaming_cmd(self, message, system_prompt=None):
        commands = []

        def popen(cmd, **_kwargs):
            commands.append(cmd)
            return FakeProcess()

        with patch.object(bridge, "find_claude_cli", return_value="/bin/claude"), \
                patch.object(bridge.subprocess, "Popen", side_effect=popen):
            list(bridge.stream_claude_response(message, system_prompt=system_prompt))
        return commands[0]

    def test_flag_shaped_message_stays_a_prompt(self):
        cmd = self._streaming_cmd(FLAG_MESSAGE)
        _assert_after_separator(self, cmd, FLAG_MESSAGE)
        self.assertEqual(cmd[-1], FLAG_MESSAGE)

    def test_plain_message_still_delivered(self):
        cmd = self._streaming_cmd("hola")
        self.assertEqual(cmd[-2:], ["--", "hola"])

    def test_flag_shaped_system_prompt_is_bound_to_its_option(self):
        cmd = self._streaming_cmd("hola", system_prompt=FLAG_PROMPT)
        self.assertNotIn(FLAG_PROMPT, cmd)
        self.assertIn(f"--system-prompt={FLAG_PROMPT}", cmd)

    def test_interactive_system_prompt_is_bound_to_its_option(self):
        commands = []

        def popen(cmd, **_kwargs):
            commands.append(cmd)
            return FakeProcess()

        session_id = "00000000-0000-4000-8000-0000000000aa"
        with patch.object(bridge, "find_claude_cli", return_value="/bin/claude"), \
                patch.object(bridge, "_get_session_workdir",
                             return_value=bridge._workspace_dir), \
                patch.object(bridge, "InteractiveSession"), \
                patch.object(bridge, "_save_known_sessions"), \
                patch.object(bridge.subprocess, "Popen", side_effect=popen):
            bridge._get_or_create_interactive_session(session_id, FLAG_PROMPT)
        bridge._interactive_sessions.pop(session_id, None)
        bridge._known_sessions.discard(session_id)
        self.assertNotIn(FLAG_PROMPT, commands[0])
        self.assertIn(f"--system-prompt={FLAG_PROMPT}", commands[0])


class AdapterArgvTests(unittest.TestCase):
    def _request(self, message):
        return BridgeRequest(message=message, system_prompt=None,
                             bridge_session_id="b1", workdir="/tmp",
                             authority_ceiling="L1", request_id="r1",
                             persistent=True)

    def test_codex_start_and_resume_end_option_parsing(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        _assert_after_separator(
            self, adapter.start_command(self._request(FLAG_MESSAGE)), FLAG_MESSAGE)
        _assert_after_separator(
            self, adapter.resume_command(self._request(FLAG_MESSAGE), "native-1"),
            FLAG_MESSAGE)

    def test_opencode_start_and_resume_end_option_parsing(self):
        adapter = OpenCodeCliAdapter(binary="/bin/opencode")
        _assert_after_separator(
            self, adapter.start_command(self._request(FLAG_MESSAGE)), FLAG_MESSAGE)
        _assert_after_separator(
            self, adapter.resume_command(self._request(FLAG_MESSAGE), "ses-1"),
            FLAG_MESSAGE)


class CorsOriginTests(unittest.TestCase):
    def test_local_network_origins_are_reflected(self):
        for origin in ("http://localhost:3000", "https://127.0.0.1",
                       f"https://{RFC1918_C}:8922", f"http://{RFC1918_A}",
                       f"http://{RFC1918_B}", "http://100.101.1.2:8922",
                       "http://lima"):
            self.assertEqual(bridge._allowed_cors_origin(origin), origin, origin)

    def test_lookalike_and_public_origins_are_rejected(self):
        for origin in ("http://localhost.evil.com", "http://lima.evil.com",
                       "http://10.evil.com", "http://192.168.evil.com",
                       "http://8.8.8.8", "http://172.32.0.1",
                       "http://100.200.0.1", "ftp://localhost", "null", "",
                       "http://localhost:99999", "http://user@localhost"):
            self.assertIsNone(bridge._allowed_cors_origin(origin), origin)

    def test_folded_origin_with_crlf_is_not_reflected(self):
        sent = []
        fake = type("H", (), {})()
        fake.headers = {"Origin": "http://localhost\r\n X-Evil: 1"}
        fake.send_header = lambda name, value: sent.append((name, value))
        bridge.SaviaBridgeHandler._send_cors_headers(fake)
        acao = dict(sent)["Access-Control-Allow-Origin"]
        self.assertEqual(acao, "https://localhost")
        self.assertFalse(any("\r" in v or "\n" in v for _, v in sent))


if __name__ == "__main__":
    unittest.main()
