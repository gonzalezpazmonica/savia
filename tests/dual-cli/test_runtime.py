"""Real Unix socket and process-crash tests; no CLI hooks are installed."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

CORE = Path(__file__).resolve().parents[2] / "scripts/dual-cli"
sys.path.insert(0, str(CORE))
from state import Store
from runtime import Runtime
from contracts import execution_result
from protocol import ProtocolError

class FixtureAdapter:
    def describe(self): return {"id":"fixture","version":"1","capability_ids":["local"]}
    def preflight(self, context): return {"ok": True}
    def execute(self, request):
        return {"request_id": request["request_id"], "state":"succeeded", "reason":"fixture",
                "artifacts":[], "usage":None, "external_effect_observed":False}
    def cancel(self, request_id): return {"request_id":request_id,"state":"cancelled"}
    def observe(self, request_id): return None


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sock = self.root / "runtime.sock"
        self.process = subprocess.Popen([sys.executable, str(CORE / "runtime.py"),
            "--state-dir", str(self.root), "--repo-id", "repo", "--revision", "r1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.addCleanup(self.stop)
        deadline = time.monotonic() + 5
        while not self.sock.exists() and self.process.poll() is None and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue(self.sock.exists(), "runtime did not create socket")

    def stop(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=5)
        self.process.stderr.close()

    def request(self, value):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(3)
            client.connect(str(self.sock))
            client.sendall(json.dumps(value).encode() + b"\n")
            with client.makefile("rb") as stream:
                return json.loads(stream.readline())

    def test_handshake_ack_and_status(self):
        hello = self.request({"op": "hello", "session_id": "test"})
        self.assertEqual(hello["revision"], "r1")
        token = hello["session_token"]
        self.assertEqual(self.request({"op": "ack", "session_id": "test",
            "session_token": token, "revision": "r1"}), {"ok": True})
        status = self.request({"op": "status"})
        self.assertFalse(status["certified"])
        self.assertNotIn(token, json.dumps(status))
        self.assertEqual(os.stat(self.sock).st_mode & 0o777, 0o600)

    def test_second_runtime_cannot_replace_live_socket(self):
        second = subprocess.run([sys.executable, str(CORE / "runtime.py"),
            "--state-dir", str(self.root), "--repo-id", "repo", "--revision", "r1"],
            capture_output=True, timeout=5)
        self.assertEqual(second.returncode, 2)
        self.assertEqual(self.request({"op": "status"})["revision"], "r1")
        self.assertIsNone(self.process.poll())

    def test_runtime_recovers_its_stale_socket_after_sigkill(self):
        self.process.kill()
        self.process.wait(timeout=5)
        self.process.stderr.close()
        self.process = subprocess.Popen([sys.executable, str(CORE / "runtime.py"),
            "--state-dir", str(self.root), "--repo-id", "repo", "--revision", "r1"],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while self.process.poll() is None and time.monotonic() < deadline:
            try:
                if self.request({"op": "status"})["revision"] == "r1":
                    break
            except (ConnectionError, OSError, socket.timeout, json.JSONDecodeError):
                time.sleep(.01)
        self.assertIsNone(self.process.poll(), "replacement runtime exited")
        self.assertEqual(self.request({"op": "status"})["revision"], "r1")

    def test_session_impersonation_is_denied(self):
        self.request({"op": "hello", "session_id": "test"})
        self.assertEqual(self.request({"op": "ack", "session_id": "test",
            "session_token": "wrong", "revision": "r1"})["error"], "UNTRUSTED")
        self.assertEqual(self.request({"op": "hello", "session_id": "test"})["error"], "CONFLICT")

    def test_dispatch_never_allows_unimplemented_capabilities(self):
        hello = self.request({"op": "hello", "session_id": "test"})
        event = dict(version=1, repo_id="repo", frontend="codex", session_id="test",
                     actor_id="test", event_id="e1", call_id="c1", kind="PreToolUse",
                     revision="r1", payload={"command": "echo sensitive"})
        request = {"op": "dispatch", "session_id": "test",
                   "session_token": hello["session_token"], "event": event}
        self.assertEqual(self.request(request)["error"], "STALE_REVISION")
        self.request({"op": "ack", "session_id": "test",
                      "session_token": hello["session_token"], "revision": "r1"})
        first = self.request(request)
        self.assertEqual(first["action"], "deny")
        self.assertEqual(first["reason"], "UNSUPPORTED_CAPABILITY")
        self.assertEqual(first, self.request(request))
        self.assertNotIn("sensitive", json.dumps(self.request({"op": "status"})))

    def test_registered_adapter_executes_only_a_valid_local_request(self):
        store=Store(self.root / "direct.db", "repo")
        store.publish("r1", expected=None)
        runtime=Runtime(store, [FixtureAdapter()])
        hello=runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct","session_token":hello["session_token"],"revision":"r1"})
        request={"request_id":"req","capability_id":"local","context_ref":"ctx",
                 "scope_ref":"scope","input_ref":"input","required_capabilities":[],
                 "deadline_ms":1000,"external_effect_intent":False}
        event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct",
                   actor_id="test", event_id="e2", call_id="c2", kind="PreToolUse",
                   revision="r1", payload={"schema":2,"adapter_id":"fixture",
                                           "request":request})
        result=runtime.handle({"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":event})
        self.assertEqual(result["state"], "succeeded")
        self.assertEqual(result["request_id"], "req")
        with self.assertRaisesRegex(ProtocolError, "UNKNOWN_ADAPTER"):
            runtime.handle({"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":dict(event, event_id="e3", payload={"schema":2,"adapter_id":"missing","request":request})})

    def test_registered_adapter_is_not_reexecuted_for_same_event(self):
        class CountingAdapter(FixtureAdapter):
            count = 0
            def execute(self, request):
                self.count += 1
                return super().execute(request)
        store=Store(self.root / "dedupe.db", "repo")
        store.publish("r1", expected=None)
        adapter=CountingAdapter()
        runtime=Runtime(store, [adapter])
        hello=runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct","session_token":hello["session_token"],"revision":"r1"})
        request={"request_id":"req","capability_id":"local","context_ref":"ctx","scope_ref":"scope","input_ref":"input","required_capabilities":[],"deadline_ms":1000,"external_effect_intent":False}
        event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct", actor_id="test", event_id="same", call_id="call", kind="PreToolUse", revision="r1", payload={"schema":2,"adapter_id":"fixture","request":request})
        dispatch={"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":event}
        first=runtime.handle(dispatch)
        second=runtime.handle(dispatch)
        self.assertEqual(first, second)
        self.assertEqual(adapter.count, 1)
        self.assertEqual(store.status()["reservations"], 0)

    def test_result_request_id_mismatch_keeps_reservation(self):
        class BadAdapter(FixtureAdapter):
            def execute(self, request):
                result=super().execute(request)
                result["request_id"]="other"
                return result
        store=Store(self.root / "mismatch.db", "repo")
        store.publish("r1", expected=None)
        runtime=Runtime(store, [BadAdapter()])
        hello=runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct","session_token":hello["session_token"],"revision":"r1"})
        request={"request_id":"req","capability_id":"local","context_ref":"ctx","scope_ref":"scope","input_ref":"input","required_capabilities":[],"deadline_ms":1000,"external_effect_intent":False}
        event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct", actor_id="test", event_id="bad", call_id="call", kind="PreToolUse", revision="r1", payload={"schema":2,"adapter_id":"fixture","request":request})
        with self.assertRaisesRegex(ProtocolError, "INCONSISTENT_RESULT"):
            runtime.handle({"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":event})
        self.assertEqual(store.status()["reservations"], 1)
        with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
            runtime.handle({"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":event})

    def test_concurrent_dispatch_reserves_before_execute(self):
        entered = threading.Event()
        unblock = threading.Event()

        class BlockingAdapter(FixtureAdapter):
            count = 0
            def execute(self, request):
                self.count += 1
                entered.set()
                self.assert_unblocked = unblock.wait(timeout=5)
                return super().execute(request)

        store=Store(self.root / "concurrent.db", "repo")
        store.publish("r1", expected=None)
        adapter=BlockingAdapter()
        runtime=Runtime(store, [adapter])
        hello=runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct","session_token":hello["session_token"],"revision":"r1"})
        request={"request_id":"req","capability_id":"local","context_ref":"ctx","scope_ref":"scope","input_ref":"input","required_capabilities":[],"deadline_ms":1000,"external_effect_intent":False}
        event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct", actor_id="test", event_id="same", call_id="call", kind="PreToolUse", revision="r1", payload={"schema":2,"adapter_id":"fixture","request":request})
        dispatch={"op":"dispatch","session_id":"direct","session_token":hello["session_token"],"event":event}
        outcomes=[]
        worker=threading.Thread(target=lambda: outcomes.append(runtime.handle(dispatch)))
        worker.start()
        self.assertTrue(entered.wait(timeout=5), "first execution did not start")
        with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
            runtime.handle(dispatch)
        unblock.set()
        worker.join(timeout=5)
        self.assertFalse(worker.is_alive())
        self.assertTrue(adapter.assert_unblocked)
        self.assertEqual(adapter.count, 1)
        self.assertEqual(outcomes[0]["state"], "succeeded")
        self.assertEqual(store.status()["reservations"], 0)


class CrashTests(unittest.TestCase):
    def test_sigkill_retains_committed_reservation(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Path(folder) / "state.db"
            store = Store(database, "repo")
            store.publish("r1", expected=None)
            child_code = (
                "import sys,time; sys.path.insert(0,sys.argv[1]); from state import Store; "
                "s=Store(sys.argv[2],'repo'); s.hello('writer'); s.ack('writer','r1'); "
                "s.acquire('writer','r1','call'); print('reserved',flush=True); time.sleep(60)"
            )
            child = subprocess.Popen([sys.executable, "-c", child_code, str(CORE), str(database)],
                                     stdout=subprocess.PIPE)
            try:
                import selectors
                with selectors.DefaultSelector() as selector:
                    selector.register(child.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=5), "writer did not reserve")
                    self.assertEqual(child.stdout.readline(), b"reserved\n")
                child.kill()
                child.wait(timeout=5)
                self.assertEqual(Store(database, "repo").status()["reservations"], 1)
            finally:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=5)
                child.stdout.close()
