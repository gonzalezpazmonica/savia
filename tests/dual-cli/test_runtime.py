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
from contracts import ExecutionAuthority, execution_result
from protocol import ProtocolError

class FixtureAdapter:
    def describe(self): return {"id":"fixture","version":"1","capability_ids":["local"]}
    def preflight(self, context):
        return {"ok": True, "request_id":context["request_id"],
                "policy_revision":context["policy_revision"],
                "capability_ids":context["capability_ids"]}
    def execute(self, request):
        return {"request_id": request["request_id"], "state":"succeeded", "reason":"fixture",
                "artifacts":[], "usage":None, "external_effect_observed":False}
    def cancel(self, request_id): return {"request_id":request_id,"state":"cancelled"}
    def observe(self, request_id): return None


def authority(*, session="direct", capability_ids=("local",), policy_revision="r1"):
    references = []
    for ref_id, kind in (("ctx", "context"), ("scope", "scope"), ("input", "input")):
        references.append({"ref_id":ref_id, "kind":kind, "repo_id":"repo",
                           "session_id":session, "policy_revision":policy_revision,
                           "capability_ids":list(capability_ids)})
    return ExecutionAuthority(references, capability_ids, policy_revision)


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
        runtime=Runtime(store, [FixtureAdapter()], authority=authority())
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

    def test_dispatch_rejects_unresolved_refs_and_capability_elevation_without_effects(self):
        class CountingAdapter(FixtureAdapter):
            count = 0
            def execute(self, request):
                self.count += 1
                return super().execute(request)

        store=Store(self.root / "authority.db", "repo")
        store.publish("r1", expected=None)
        adapter=CountingAdapter()
        runtime=Runtime(store, [adapter], authority=authority())
        hello=runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct",
                        "session_token":hello["session_token"],"revision":"r1"})
        base={"request_id":"req","capability_id":"local","context_ref":"ctx",
              "scope_ref":"scope","input_ref":"input","required_capabilities":[],
              "deadline_ms":1000,"external_effect_intent":False}

        for event_id, request, error in (
            ("missing-ref", dict(base, input_ref="foreign"), "UNTRUSTED_REFERENCE"),
            ("elevated", dict(base, required_capabilities=["admin"]), "UNSUPPORTED_CAPABILITY"),
        ):
            event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct",
                       actor_id="test", event_id=event_id, call_id=event_id,
                       kind="PreToolUse", revision="r1",
                       payload={"schema":2,"adapter_id":"fixture","request":request})
            with self.assertRaisesRegex(ProtocolError, error):
                runtime.handle({"op":"dispatch","session_id":"direct",
                                "session_token":hello["session_token"],"event":event})

        self.assertEqual(adapter.count, 0)
        self.assertEqual(store.status()["reservations"], 0)

    def test_dispatch_rejects_stale_policy_and_uncorrelated_preflight_without_effects(self):
        class BadPreflightAdapter(FixtureAdapter):
            count = 0
            def preflight(self, context):
                result=super().preflight(context)
                result["request_id"]="other"
                return result
            def execute(self, request):
                self.count += 1
                return super().execute(request)

        store=Store(self.root / "policy.db", "repo")
        store.publish("r1", expected=None)
        adapter=BadPreflightAdapter()
        request={"request_id":"req","capability_id":"local","context_ref":"ctx",
                 "scope_ref":"scope","input_ref":"input","required_capabilities":[],
                 "deadline_ms":1000,"external_effect_intent":False}
        event=dict(version=1, repo_id="repo", frontend="codex", session_id="direct",
                   actor_id="test", event_id="policy", call_id="policy",
                   kind="PreToolUse", revision="r1",
                   payload={"schema":2,"adapter_id":"fixture","request":request})

        stale=Runtime(store, [adapter], authority=authority(policy_revision="r2"))
        hello=stale.handle({"op":"hello","session_id":"direct"})
        stale.handle({"op":"ack","session_id":"direct",
                      "session_token":hello["session_token"],"revision":"r1"})
        with self.assertRaisesRegex(ProtocolError, "STALE_POLICY"):
            stale.handle({"op":"dispatch","session_id":"direct",
                          "session_token":hello["session_token"],"event":event})

        correlated=Runtime(store, [adapter], authority=authority())
        hello=correlated.handle({"op":"hello","session_id":"correlated"})
        correlated.handle({"op":"ack","session_id":"correlated",
                           "session_token":hello["session_token"],"revision":"r1"})
        correlated_event=dict(event, session_id="correlated", event_id="preflight",
                              call_id="preflight")
        correlated._authority=authority(session="correlated")
        with self.assertRaisesRegex(ProtocolError, "INCONSISTENT_PREFLIGHT"):
            correlated.handle({"op":"dispatch","session_id":"correlated",
                               "session_token":hello["session_token"],"event":correlated_event})
        self.assertEqual(adapter.count, 0)
        self.assertEqual(store.status()["reservations"], 0)

    def test_domain_pack_composition_is_consumed_by_runtime_without_cross_domain_leakage(self):
        class DomainAdapter(FixtureAdapter):
            contexts = []
            count = 0
            def describe(self):
                return {"id":"fixture","version":"1",
                        "capability_ids":["read","edit"]}
            def preflight(self, context):
                self.contexts.append(context)
                return {"ok":True, "request_id":context["request_id"],
                        "policy_revision":context["policy_revision"],
                        "capability_ids":context["capability_ids"]}
            def execute(self, request):
                self.count += 1
                return super().execute(request)

        core={"id":"core","version":"1","capability_ids":["read","edit"],
              "rule_refs":[],"context_refs":[],"test_refs":[],
              "memory_namespace":"core","dependencies":[],"compatibility_schema":2}
        alpha=dict(core, id="alpha", capability_ids=["read"],
                   memory_namespace="alpha", dependencies=["core@1"])
        beta=dict(core, id="beta", capability_ids=["edit"],
                  memory_namespace="beta", dependencies=["core@1"])
        packs={p["id"]:p for p in (core, alpha, beta)}

        for domain_id, capability in (("alpha","read"),("beta","edit")):
            session=domain_id
            refs=[]
            for ref_id, kind in (("ctx","context"),("scope","scope"),("input","input")):
                refs.append({"ref_id":ref_id,"kind":kind,"repo_id":"repo",
                             "session_id":session,"policy_revision":"r1",
                             "capability_ids":["read","edit"]})
            store=Store(self.root / f"{domain_id}.db", "repo")
            store.publish("r1", expected=None)
            adapter=DomainAdapter()
            domain_authority=ExecutionAuthority.for_domains(
                refs, ["read","edit","admin"], "r1", packs, [domain_id])
            runtime=Runtime(store,[adapter],authority=domain_authority)
            hello=runtime.handle({"op":"hello","session_id":session})
            runtime.handle({"op":"ack","session_id":session,
                            "session_token":hello["session_token"],"revision":"r1"})
            request={"request_id":f"req-{domain_id}","capability_id":capability,
                     "context_ref":"ctx","scope_ref":"scope","input_ref":"input",
                     "required_capabilities":[],"deadline_ms":1000,
                     "external_effect_intent":False}
            event=dict(version=1,repo_id="repo",frontend="codex",session_id=session,
                       actor_id="test",event_id=f"event-{domain_id}",call_id="call",
                       kind="PreToolUse",revision="r1",
                       payload={"schema":2,"adapter_id":"fixture","request":request})
            result=runtime.handle({"op":"dispatch","session_id":session,
                                   "session_token":hello["session_token"],"event":event})
            self.assertEqual(result["state"],"succeeded")
            self.assertEqual(adapter.contexts[-1]["domain_ids"],["core",domain_id])
            self.assertEqual(adapter.contexts[-1]["memory_namespaces"],["core",domain_id])

            denied=dict(request,request_id=f"denied-{domain_id}",
                        capability_id="edit" if capability == "read" else "read")
            denied_event=dict(event,event_id=f"denied-{domain_id}",call_id="deny",
                              payload={"schema":2,"adapter_id":"fixture","request":denied})
            with self.assertRaisesRegex(ProtocolError,"UNSUPPORTED_CAPABILITY"):
                runtime.handle({"op":"dispatch","session_id":session,
                                "session_token":hello["session_token"],"event":denied_event})
            self.assertEqual(adapter.count,1)

    def test_registered_adapter_is_not_reexecuted_for_same_event(self):
        class CountingAdapter(FixtureAdapter):
            count = 0
            def execute(self, request):
                self.count += 1
                return super().execute(request)
        store=Store(self.root / "dedupe.db", "repo")
        store.publish("r1", expected=None)
        adapter=CountingAdapter()
        runtime=Runtime(store, [adapter], authority=authority())
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
        runtime=Runtime(store, [BadAdapter()], authority=authority())
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
        runtime=Runtime(store, [adapter], authority=authority())
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

    def test_deadline_requests_cancel_and_late_result_stays_ambiguous(self):
        entered = threading.Event()
        release = threading.Event()
        finished = threading.Event()
        cancelled = threading.Event()

        class SlowAdapter(FixtureAdapter):
            execute_count = 0
            cancel_count = 0

            def execute(self, request):
                self.execute_count += 1
                entered.set()
                release.wait(timeout=5)
                finished.set()
                return super().execute(request)

            def cancel(self, request_id):
                self.cancel_count += 1
                cancelled.set()
                return super().cancel(request_id)

        store = Store(self.root / "deadline.db", "repo")
        store.publish("r1", expected=None)
        adapter = SlowAdapter()
        runtime = Runtime(store, [adapter], authority=authority())
        hello = runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct",
                        "session_token":hello["session_token"],"revision":"r1"})
        request = {"request_id":"req","capability_id":"local","context_ref":"ctx",
                   "scope_ref":"scope","input_ref":"input","required_capabilities":[],
                   "deadline_ms":20,"external_effect_intent":False}
        event = dict(version=1, repo_id="repo", frontend="codex", session_id="direct",
                     actor_id="test", event_id="deadline", call_id="call",
                     kind="PreToolUse", revision="r1",
                     payload={"schema":2,"adapter_id":"fixture","request":request})
        dispatch = {"op":"dispatch","session_id":"direct",
                    "session_token":hello["session_token"],"event":event}

        try:
            with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
                runtime.handle(dispatch)
            self.assertTrue(entered.is_set())
            self.assertTrue(cancelled.wait(timeout=1), "cancel was not requested")
            self.assertEqual(adapter.execute_count, 1)
            self.assertEqual(adapter.cancel_count, 1)
            self.assertEqual(store.status()["reservations"], 1)
        finally:
            release.set()
        self.assertTrue(finished.wait(timeout=1), "late execution did not finish")
        self.assertIsNone(store.prior_record(event))
        self.assertEqual(store.status()["reservations"], 1)
        with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
            Store(self.root / "deadline.db", "repo").admit(event, "direct", "r1", "call")
        self.assertEqual(adapter.execute_count, 1)
        self.assertEqual(adapter.cancel_count, 1)

    def test_execute_exception_stays_ambiguous_and_is_not_retried(self):
        class RaisingAdapter(FixtureAdapter):
            count = 0

            def execute(self, request):
                self.count += 1
                raise RuntimeError("fixture failure")

        store = Store(self.root / "exception.db", "repo")
        store.publish("r1", expected=None)
        adapter = RaisingAdapter()
        runtime = Runtime(store, [adapter], authority=authority())
        hello = runtime.handle({"op":"hello","session_id":"direct"})
        runtime.handle({"op":"ack","session_id":"direct",
                        "session_token":hello["session_token"],"revision":"r1"})
        request = {"request_id":"req","capability_id":"local","context_ref":"ctx",
                   "scope_ref":"scope","input_ref":"input","required_capabilities":[],
                   "deadline_ms":1000,"external_effect_intent":False}
        event = dict(version=1, repo_id="repo", frontend="codex", session_id="direct",
                     actor_id="test", event_id="exception", call_id="call",
                     kind="PreToolUse", revision="r1",
                     payload={"schema":2,"adapter_id":"fixture","request":request})
        dispatch = {"op":"dispatch","session_id":"direct",
                    "session_token":hello["session_token"],"event":event}

        with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
            runtime.handle(dispatch)
        self.assertEqual(store.status()["reservations"], 1)
        with self.assertRaisesRegex(ProtocolError, "AMBIGUOUS_EXECUTION"):
            runtime.handle(dispatch)
        self.assertEqual(adapter.count, 1)


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
