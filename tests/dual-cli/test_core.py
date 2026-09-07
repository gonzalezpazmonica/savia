"""Core contracts exercised with isolated databases and synthetic events."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/dual-cli"))
from protocol import ProtocolError, decode_event
from state import Store
from policy import hook_decision


def event(**changes):
    value = dict(version=1, repo_id="repo", frontend="codex", session_id="one",
                 actor_id="actor", event_id="event", call_id=None,
                 kind="PreToolUse", revision="r1", payload={})
    value.update(changes)
    return value


class ProtocolTests(unittest.TestCase):
    def test_valid_event(self):
        self.assertEqual(decode_event(json.dumps(event()).encode()), event())

    def test_invalid_inputs_fail_closed(self):
        invalid = [b"{", b"[]", b"\xff", b"x" * 1048577,
                   json.dumps(event(version=True)).encode(),
                   json.dumps(event(frontend="unknown")).encode(),
                   json.dumps(event(session_id="")).encode(),
                   json.dumps(event(payload=float("nan"))).encode(),
                   json.dumps(event(call_id=12)).encode(),
                   json.dumps(event(extra="unknown")).encode(),
                   b'{"version":1,"version":1}',
                   json.dumps(event()).replace('"payload": {}', '"payload": 1e999').encode()]
        for value in invalid:
            with self.subTest(value=value[:80]), self.assertRaises(ProtocolError):
                decode_event(value)


class PolicyTests(unittest.TestCase):
    def test_critical_failures_deny(self):
        for code, output in [(2, ""), (1, ""), (0, "garbage"),
                             (0, '{"decision":"block"}'),
                             (0, '{"hookSpecificOutput":{"permissionDecision":"deny"}}')]:
            with self.subTest(code=code, output=output):
                self.assertEqual(hook_decision(code, output)["action"], "deny")
        self.assertEqual(hook_decision(0, "", timed_out=True)["action"], "deny")

    def test_malformed_control_fields_deny(self):
        for output in ['{"continue":0}', '{"decision":[]}',
                       '{"hookSpecificOutput":{"permissionDecision":{}}}']:
            self.assertEqual(hook_decision(0, output)["action"], "deny")

    def test_allowed_mutation_and_context_survive(self):
        result = hook_decision(0, json.dumps({"hookSpecificOutput": {
            "permissionDecision": "allow", "updatedInput": {"file": "x"},
            "additionalContext": "context"}}))
        self.assertEqual(result["action"], "allow")
        self.assertEqual(result["updated_input"], {"file": "x"})
        self.assertEqual(result["context"], "context")

    def test_human_permission_is_not_approval(self):
        result = hook_decision(0, '{"hookSpecificOutput":{"permissionDecision":"ask"}}')
        self.assertEqual(result["action"], "deny")


class StateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "state.db"
        self.store = Store(self.path, "repo")
        self.store.publish("r1", expected=None)
        self.store.hello("one")
        self.store.ack("one", "r1")

    def test_publication_compare_and_swap_and_ack(self):
        self.store.publish("r2", expected="r1")
        with self.assertRaisesRegex(ProtocolError, "STALE_REVISION"):
            self.store.acquire("one", "r1", "call")
        with self.assertRaisesRegex(ProtocolError, "STALE_REVISION"):
            self.store.acquire("one", "r2", "call")
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            self.store.publish("r3", expected="r1")
        self.store.ack("one", "r2")
        self.assertTrue(self.store.acquire("one", "r2", "call"))

    def test_100_races_have_exactly_one_winner(self):
        self.store.hello("two")
        self.store.ack("two", "r1")
        def attempt(session, call):
            try:
                return session, Store(self.path, "repo").acquire(session, "r1", call)
            except ProtocolError as error:
                self.assertEqual(error.code, "CONFLICT")
                return session, None
        with ThreadPoolExecutor(max_workers=2) as pool:
            for i in range(100):
                results = list(pool.map(lambda s: attempt(s, str(i)), ["one", "two"]))
                winners = [(s, token) for s, token in results if token]
                self.assertEqual(len(winners), 1)
                self.store.release(*winners[0])

    def test_lease_survives_reopen_and_close_does_not_drop_it(self):
        token = self.store.acquire("one", "r1", "call")
        reopened = Store(self.path, "repo")
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            reopened.close_session("one")
        self.assertEqual(reopened.acquire("one", "r1", "call"), token)
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            reopened.release("stranger", token)
        reopened.release("one", token)
        reopened.close_session("one")

    def test_journal_deduplicates_and_rejects_changed_event(self):
        first = self.store.record(event(), {"action": "deny", "reason": "test"})
        self.assertEqual(first, self.store.record(event(), {"action": "deny", "reason": "test"}))
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            self.store.record(event(payload={"changed": True}), {"action": "deny"})
        self.assertEqual(self.store.status()["sequence"], 1)

    def test_completed_call_cannot_acquire_a_second_effect(self):
        token = self.store.acquire("one", "r1", "call")
        self.store.release("one", token)
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            self.store.acquire("one", "r1", "call")

    def test_database_cannot_be_reused_for_another_repo(self):
        with self.assertRaisesRegex(ProtocolError, "CONFLICT"):
            Store(self.path, "another-repo")

    def test_status_does_not_include_payload_or_lease_secret(self):
        token = self.store.acquire("one", "r1", "call")
        self.store.record(event(payload={"secret": "PRIVATE_SENTINEL"}), {"action": "deny"})
        output = json.dumps(self.store.status())
        self.assertNotIn("PRIVATE_SENTINEL", output)
        self.assertNotIn(token, output)


if __name__ == "__main__":
    unittest.main()
