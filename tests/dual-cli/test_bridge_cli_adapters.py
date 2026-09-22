"""SE-396 A01a: provider-specific CLI details stay behind bridge adapters."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from bridge_cli_adapters import (  # noqa: E402
    AdapterContractError,
    BridgeRequest,
    CodexCliAdapter,
    OpenCodeCliAdapter,
    adapter_by_id,
)


class CliAdapterTests(unittest.TestCase):
    def request(self, *, persistent=False):
        return BridgeRequest(
            message="hello", system_prompt=None, bridge_session_id="bridge-1",
            workdir="/tmp/work", authority_ceiling="L2", request_id="req-1",
            persistent=persistent,
        )

    def test_unknown_adapter_fails_closed(self):
        with self.assertRaisesRegex(AdapterContractError, "UNKNOWN_ADAPTER"):
            adapter_by_id("missing")
        with self.assertRaisesRegex(AdapterContractError, "UNKNOWN_ADAPTER"):
            adapter_by_id([])

    def test_request_rejects_non_scalar_contract_fields(self):
        for change in ({"message": []}, {"authority_ceiling": []},
                       {"request_id": None}, {"workdir": []}):
            values = dict(message="hello", system_prompt=None,
                          bridge_session_id="bridge-1", workdir="/tmp/work",
                          authority_ceiling="L2", request_id="req-1")
            values.update(change)
            with self.subTest(change=change):
                with self.assertRaisesRegex(AdapterContractError, "INVALID_REQUEST"):
                    BridgeRequest(**values)

    def test_codex_start_uses_safe_json_contract(self):
        cmd = CodexCliAdapter(binary="/bin/codex").start_command(self.request())
        self.assertEqual(cmd[:3], ["/bin/codex", "exec", "--json"])
        self.assertIn("--ephemeral", cmd)
        self.assertIn("workspace-write", cmd)
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", cmd)

    def test_codex_persistent_start_and_resume_keep_native_identity_separate(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        start = adapter.start_command(self.request(persistent=True))
        self.assertNotIn("--ephemeral", start)
        resume = adapter.resume_command(self.request(persistent=True), "native-thread")
        self.assertIn("native-thread", resume)
        self.assertNotIn("bridge-1", resume)

    def test_codex_ephemeral_resume_is_rejected_before_execution(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        with self.assertRaisesRegex(AdapterContractError, "UNSUPPORTED_RESUME"):
            adapter.resume_command(self.request(), "native-thread")

    def test_codex_translates_observed_jsonl(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        started = adapter.translate('{"type":"thread.started","thread_id":"native-1"}')
        self.assertEqual(started.native_session_ref, "native-1")
        self.assertEqual(started.events, ())
        message = adapter.translate(
            '{"type":"item.completed","item":{"id":"i","type":"agent_message","text":"ok"}}'
        )
        self.assertEqual(message.events, ({"type": "text", "text": "ok"},))
        done = adapter.translate(
            '{"type":"turn.completed","usage":{"input_tokens":2,"output_tokens":1}}'
        )
        self.assertEqual(done.events[0]["type"], "done")

    def test_malformed_or_unknown_codex_event_never_synthesizes_success(self):
        adapter = CodexCliAdapter(binary="/bin/codex")
        for line in ("not-json", '{"type":"future.event"}'):
            with self.subTest(line=line):
                with self.assertRaises(AdapterContractError):
                    adapter.translate(line)

    def test_opencode_command_disables_plugins_and_never_auto_approves(self):
        cmd = OpenCodeCliAdapter(binary="/bin/opencode").start_command(self.request())
        self.assertEqual(cmd[:3], ["/bin/opencode", "run", "--pure"])
        self.assertIn("json", cmd)
        self.assertNotIn("--auto", cmd)

    def test_opencode_stream_stays_not_verified(self):
        adapter = OpenCodeCliAdapter(binary="/bin/opencode")
        with self.assertRaisesRegex(AdapterContractError, "NOT_VERIFIED"):
            adapter.translate('{"type":"text","text":"guessed"}')

    def test_opencode_resume_uses_native_not_bridge_session(self):
        adapter = OpenCodeCliAdapter(binary="/bin/opencode")
        cmd = adapter.resume_command(self.request(persistent=True), "native-session")
        self.assertIn("native-session", cmd)
        self.assertNotIn("bridge-1", cmd)
        self.assertNotIn("--auto", cmd)

    def test_missing_binary_is_unavailable_not_verified(self):
        adapter = CodexCliAdapter(which=lambda _name: None)
        self.assertEqual(adapter.preflight()["status"], "UNAVAILABLE")


if __name__ == "__main__":
    unittest.main()
