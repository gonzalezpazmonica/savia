"""S4 config/client/preflight contracts; stdlib fixtures, no provider execution."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
sys.path.insert(0, str(CORE))


def load(name):
    path = CORE / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"dual_cli_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RepoFixture:
    def __init__(self, root):
        self.root = Path(root)
        self.write_json(".scm/resources.json", {"resources": [
            {"kind": "script", "path": "scripts/gate.sh", "name": "gate"},
            {"kind": "skill", "path": ".claude/skills/demo/SKILL.md", "name": "demo"},
            {"kind": "cmd", "path": ".claude/commands/demo.md", "name": "demo"},
        ]})
        self.write(".scm/INDEX.scm", "derived capability index\n")
        self.write(".scm/categories/quality.scm", "quality sources\n")
        self.write_json(".claude/settings.json", {"hooks": {"PreToolUse": [{"hooks": [
            {"type": "command", "command": '"$CLAUDE_PROJECT_DIR"/.opencode/hooks/gate.sh'}
        ]}]}})
        self.write("scripts/gate.sh", "#!/bin/sh\nexit 2\n")
        self.write(".opencode/hooks/gate.sh", "#!/bin/sh\nexit 2\n")
        self.write(".claude/skills/demo/SKILL.md", "# Demo\nSee references/policy.md\n")
        self.write(".claude/skills/demo/references/policy.md", "deny by default\n")
        self.write(".claude/commands/demo.md", "not part of the requested source scope\n")

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding="utf-8")

    def write_json(self, name, value):
        self.write(name, json.dumps(value))


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.config = load("config")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        RepoFixture(self.root)

    def test_manifest_hashes_authoritative_sources_and_referenced_files(self):
        result = self.config.build_manifest(self.root)
        paths = {item["path"] for item in result["sources"]}
        self.assertEqual(result["schema"], 1)
        self.assertFalse(result["certified"])
        self.assertIn(".scm/resources.json", paths)
        self.assertIn(".scm/categories/quality.scm", paths)
        self.assertIn(".claude/settings.json", paths)
        self.assertIn("scripts/gate.sh", paths)
        self.assertIn(".opencode/hooks/gate.sh", paths)
        self.assertIn(".claude/skills/demo/SKILL.md", paths)
        self.assertIn(".claude/skills/demo/references/policy.md", paths)
        self.assertNotIn(".claude/commands/demo.md", paths)
        for item in result["sources"]:
            data = (self.root / item["path"]).read_bytes()
            self.assertEqual(item["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(result, self.config.build_manifest(self.root))

    def test_revision_changes_when_a_referenced_skill_asset_changes(self):
        before = self.config.build_manifest(self.root)["revision"]
        (self.root / ".claude/skills/demo/references/policy.md").write_text("new policy\n")
        after = self.config.build_manifest(self.root)["revision"]
        self.assertNotEqual(before, after)

    def test_invalid_registry_paths_fail_closed(self):
        RepoFixture(self.root).write_json(".scm/resources.json", {"resources": [
            {"kind": "script", "path": "../escape.sh"}]})
        with self.assertRaisesRegex(self.config.ConfigError, "UNTRUSTED_SOURCE"):
            self.config.build_manifest(self.root)

    def test_symlinked_source_fails_closed(self):
        external = Path(self.tmp.name) / "external.sh"
        external.write_text("outside\n")
        (self.root / "scripts/gate.sh").unlink()
        (self.root / "scripts/gate.sh").symlink_to(external)
        with self.assertRaisesRegex(self.config.ConfigError, "UNTRUSTED_SOURCE"):
            self.config.build_manifest(self.root)


class GeneratedConfigTests(unittest.TestCase):
    def setUp(self):
        self.config = load("config")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        RepoFixture(self.root)
        self.target = Path(self.tmp.name) / "state" / "config"

    def test_generation_is_idempotent_and_does_not_duplicate_source_content(self):
        first = self.config.generate(self.root, self.target)
        generated = self.target / self.config.GENERATED_NAME
        before = generated.read_bytes()
        second = self.config.generate(self.root, self.target)
        self.assertEqual(first, second)
        self.assertEqual(before, generated.read_bytes())
        payload = generated.read_text()
        self.assertNotIn("deny by default", payload)
        self.assertEqual(json.loads(payload)["revision"], first["revision"])

    def test_generation_refuses_to_overwrite_foreign_or_modified_files(self):
        self.target.mkdir(parents=True)
        generated = self.target / self.config.GENERATED_NAME
        generated.write_text("foreign")
        with self.assertRaisesRegex(self.config.ConfigError, "FOREIGN_FILE"):
            self.config.generate(self.root, self.target)
        generated.unlink()
        self.config.generate(self.root, self.target)
        generated.write_text("operator edit")
        with self.assertRaisesRegex(self.config.ConfigError, "MANAGED_FILE_MODIFIED"):
            self.config.generate(self.root, self.target)

    def test_rollback_only_removes_unmodified_managed_files(self):
        self.target.mkdir(parents=True)
        foreign = self.target / "keep.txt"
        foreign.write_text("operator")
        self.config.generate(self.root, self.target)
        result = self.config.rollback(self.target)
        self.assertEqual(result, {"removed": [self.config.GENERATED_NAME], "conflicts": []})
        self.assertEqual(foreign.read_text(), "operator")
        self.assertFalse((self.target / self.config.GENERATED_NAME).exists())

    def test_rollback_preserves_modified_managed_file(self):
        self.config.generate(self.root, self.target)
        generated = self.target / self.config.GENERATED_NAME
        generated.write_text("operator edit")
        result = self.config.rollback(self.target)
        self.assertEqual(result["removed"], [])
        self.assertEqual(result["conflicts"], [self.config.GENERATED_NAME])
        self.assertEqual(generated.read_text(), "operator edit")

    def test_generation_never_writes_project_codex_configuration(self):
        with self.assertRaisesRegex(self.config.ConfigError, "FORBIDDEN_TARGET"):
            self.config.generate(self.root, self.root / ".codex")
        self.assertFalse((self.root / ".codex/hooks.json").exists())


class OneShotUnixServer:
    def __init__(self, path, responder):
        self.path = str(path)
        self.responder = responder
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.ready = threading.Event()

    def start(self):
        self.thread.start()
        self.ready.wait(2)
        return self

    def run(self):
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(self.path)
            server.listen(1)
            self.ready.set()
            connection, _ = server.accept()
            with connection, connection.makefile("rb") as stream:
                request = json.loads(stream.readline())
                response = self.responder(request)
                if isinstance(response, bytes):
                    connection.sendall(response)
                else:
                    connection.sendall(json.dumps(response).encode() + b"\n")


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.client_module = load("client")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.socket_path = Path(self.tmp.name) / "runtime.sock"

    def test_hello_ack_uses_session_token_without_exposing_it(self):
        seen = []
        responses = iter([
            {"revision": "r1", "session_token": "secret", "certified": False},
            {"ok": True},
        ])
        for _ in range(2):
            server = OneShotUnixServer(self.socket_path, lambda request: (seen.append(request), next(responses))[1]).start()
            if len(seen) == 0:
                client = self.client_module.Client(self.socket_path)
                hello = client.hello("session")
                self.assertNotIn("secret", repr(client))
            else:
                client.ack()
            server.thread.join(2)
            self.socket_path.unlink(missing_ok=True)
        self.assertEqual(hello["revision"], "r1")
        self.assertEqual(seen[0], {"op": "hello", "session_id": "session"})
        self.assertEqual(seen[1], {"op": "ack", "session_id": "session",
                         "session_token": "secret", "revision": "r1"})

    def test_dispatch_is_fail_closed_on_malformed_or_allow_shaped_errors(self):
        client = self.client_module.Client(self.socket_path)
        client.session_id, client.session_token, client.revision = "s", "t", "r"
        for raw in (b"not-json\n", b'{"action":"allow","error":"UNAVAILABLE"}\n'):
            server = OneShotUnixServer(self.socket_path, lambda _request, raw=raw: raw).start()
            with self.assertRaisesRegex(self.client_module.ClientError, "UNAVAILABLE"):
                client.dispatch({"version": 1})
            server.thread.join(2)
            self.socket_path.unlink(missing_ok=True)

    def test_unavailable_socket_fails_closed(self):
        client = self.client_module.Client(self.socket_path, timeout=.1)
        with self.assertRaisesRegex(self.client_module.ClientError, "UNAVAILABLE"):
            client.status()


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.config = load("config")
        self.preflight = load("preflight")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        RepoFixture(self.root)
        self.target = Path(self.tmp.name) / "config"
        self.generated = self.config.generate(self.root, self.target)
        self.revision = self.generated["revision"]

    def complete_evidence(self):
        return {
            "schema": 1,
            "revision": self.revision,
            "kind": "native-e2e-observation",
            "versions": {"codex": "0.153.4", "opencode": "1.18.21"},
            "trust": {
                "codex": {"native": True, "revision": self.revision, "verified": True},
                "opencode": {"native": True, "revision": self.revision, "verified": True},
            },
            "sandbox": {"command": ["codex", "sandbox", "--", "/usr/bin/true"],
                        "passed": True},
            "replay": {"revision": self.revision, "passed": True},
            "e2e": {"revision": self.revision, "passed": True},
            "capabilities": {"gaps": []},
        }

    def test_certified_mode_rejects_missing_evidence_and_arbitrary_flag(self):
        report = self.preflight.validate(self.root, self.target, None,
            runtime_status={"revision": self.revision, "certified": False, "gaps": []},
            observed_versions={"codex": "0.153.4", "opencode": "1.18.21"},
            sandbox_passed=False)
        self.assertFalse(report["certified"])
        self.assertIn("NATIVE_EVIDENCE_MISSING", report["gaps"])
        self.assertIn("SANDBOX_UNAVAILABLE", report["gaps"])

        evidence = {"certified": True, "gaps": []}
        report = self.preflight.validate(self.root, self.target, evidence,
            runtime_status={"revision": self.revision, "certified": True, "gaps": []},
            observed_versions={"codex": "0.153.4", "opencode": "1.18.21"},
            sandbox_passed=True)
        self.assertFalse(report["certified"])
        self.assertIn("NATIVE_EVIDENCE_INVALID", report["gaps"])

    def test_versions_trust_sandbox_and_runtime_are_mandatory(self):
        evidence = self.complete_evidence()
        evidence["trust"]["codex"]["verified"] = False
        report = self.preflight.validate(self.root, self.target, evidence,
            runtime_status={"revision": self.revision, "certified": False,
                            "gaps": ["EXECUTION_ADAPTERS_UNIMPLEMENTED"]},
            observed_versions={"codex": "0.999.0", "opencode": "1.18.21"},
            sandbox_passed=False)
        self.assertFalse(report["certified"])
        self.assertIn("CLI_VERSION_MISMATCH", report["gaps"])
        self.assertIn("NATIVE_TRUST_UNVERIFIED", report["gaps"])
        self.assertIn("SANDBOX_UNAVAILABLE", report["gaps"])
        self.assertIn("RUNTIME_UNCERTIFIED", report["gaps"])
        self.assertIn("EXECUTION_ADAPTERS_UNIMPLEMENTED", report["gaps"])

    def test_complete_current_revision_evidence_can_pass_only_with_runtime(self):
        report = self.preflight.validate(self.root, self.target, self.complete_evidence(),
            runtime_status={"revision": self.revision, "certified": True, "gaps": []},
            observed_versions={"codex": "0.153.4", "opencode": "1.18.21"},
            sandbox_passed=True)
        self.assertEqual(report, {"certified": True, "revision": self.revision, "gaps": []})

    def test_v2_evidence_accepts_an_explicit_third_adapter(self):
        evidence = self.complete_evidence()
        evidence["schema"] = 2
        evidence["adapters"] = [
            {"id": "codex", "version": "0.153.4"},
            {"id": "opencode", "version": "1.18.21"},
            {"id": "fixture-cli", "version": "1"},
        ]
        evidence["trust"]["fixture-cli"] = {"verified": True, "revision": self.revision}
        report = self.preflight.validate(self.root, self.target, evidence,
            runtime_status={"revision": self.revision, "certified": True, "gaps": []},
            observed_versions={"codex":"0.153.4", "opencode":"1.18.21", "fixture-cli":"1"},
            sandbox_passed=True)
        self.assertTrue(report["certified"])

    def test_v2_evidence_rejects_duplicate_adapter_or_truthy_certification(self):
        evidence = self.complete_evidence()
        evidence["schema"] = 2
        evidence["adapters"] = [
            {"id": "codex", "version": "0.153.4"},
            {"id": "codex", "version": "0.153.4"},
        ]
        evidence["trust"]["codex"]["verified"] = "yes"
        report = self.preflight.validate(self.root, self.target, evidence,
            runtime_status={"revision": self.revision, "certified": "yes", "gaps": []},
            observed_versions={"codex":"0.153.4"}, sandbox_passed=True)
        self.assertFalse(report["certified"])
        self.assertIn("NATIVE_TRUST_UNVERIFIED", report["gaps"])
        self.assertIn("RUNTIME_UNCERTIFIED", report["gaps"])

    def test_stale_generated_config_or_evidence_is_rejected(self):
        (self.root / "scripts/gate.sh").write_text("changed\n")
        report = self.preflight.validate(self.root, self.target, self.complete_evidence(),
            runtime_status={"revision": self.revision, "certified": True, "gaps": []},
            observed_versions={"codex": "0.153.4", "opencode": "1.18.21"},
            sandbox_passed=True)
        self.assertFalse(report["certified"])
        self.assertIn("STALE_GENERATED_CONFIG", report["gaps"])


if __name__ == "__main__":
    unittest.main()
