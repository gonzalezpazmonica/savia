"""SE-399 F1 — contracts, planner and state machine (read-only, fixtures only)."""
from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FX = ROOT / "tests/fixtures/installer"
sys.path.insert(0, str(ROOT / "scripts"))

from provisioning import state  # noqa: E402
from provisioning.adapter import FixtureAdapter, PlatformAdapter  # noqa: E402
from provisioning.planner import build_plan, find_secrets, load_manifests, load_schema, validate  # noqa: E402

MANIFESTS = load_manifests(str(FX / "manifests"))


def host(name):
    return FixtureAdapter(str(FX / "hosts" / f"{name}.json")).discover()


def plan(name, *sel, manifests=None):
    return build_plan(manifests or MANIFESTS, host(name), list(sel))


def codes(p, kind="blockers"):
    return {(f["component"], f["code"]) for f in p[kind]}


class ManifestSchema(unittest.TestCase):
    def test_fixture_manifests_valid(self):
        self.assertEqual(len(MANIFESTS), 7)

    def test_rejects_shell_string_executable(self):
        m = copy.deepcopy(MANIFESTS["git"])
        m["targets"][0]["actions"]["install"]["invocation"]["executable"] = "apt-get install git; true"
        self.assertTrue(validate(m, "component-manifest"))

    def test_rejects_unknown_field_and_bad_privilege(self):
        m = copy.deepcopy(MANIFESTS["git"])
        m["shell"] = "bash -c x"
        m["targets"][0]["actions"]["install"]["privilege"] = "SUDO"
        errs = validate(m, "component-manifest")
        self.assertTrue(any("shell" in e for e in errs) and any("privilege" in e for e in errs))

    def test_f1_delta_fields_present(self):
        core = MANIFESTS["savia-core"]
        act = core["targets"][0]["actions"]["install"]
        self.assertTrue(act["atomic_replace"])
        self.assertEqual(act["compensation"], "rollback")
        self.assertEqual(core["ownership"]["link_mode"], "isolated")
        self.assertIn("previous_successful_sync_at", core["freshness"])
        self.assertEqual(MANIFESTS["opencode"]["compat"]["min_runtime_version"], "1.0")

    def test_duplicate_ids_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            shutil.copy(FX / "manifests/git.json", Path(d) / "a.json")
            shutil.copy(FX / "manifests/git.json", Path(d) / "b.json")
            with self.assertRaises(ValueError):
                load_manifests(d)

    def test_agrees_with_real_jsonschema_when_available(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest("jsonschema not installed; cross-check only, validation itself is stdlib")
        v = jsonschema.Draft202012Validator(load_schema("component-manifest"))
        for m in MANIFESTS.values():
            v.validate(m)
        bad = copy.deepcopy(MANIFESTS["git"])
        bad["targets"][0]["actions"]["install"]["privilege"] = "SUDO"
        self.assertTrue(validate(bad, "component-manifest"))
        with self.assertRaises(jsonschema.ValidationError):
            v.validate(bad)


class Planner(unittest.TestCase):
    def test_ubuntu_ready_and_ordered_by_dependencies(self):
        p = plan("ubuntu-x64", "opencode")
        self.assertEqual(p["status"], "ready")
        order = [s["component"] for s in p["steps"]]
        self.assertLess(order.index("node"), order.index("savia-core"))
        self.assertLess(order.index("savia-core"), order.index("opencode"))
        self.assertEqual({s["component"]: s["disposition"] for s in p["steps"]}["git"], "already_installed")
        self.assertEqual(validate(p, "installation-plan"), [])

    def test_deterministic_plan_id(self):
        a, b = plan("ubuntu-x64", "opencode"), plan("ubuntu-x64", "opencode", "opencode")
        self.assertEqual(a, b)
        self.assertNotEqual(a["plan_id"], plan("windows-x64", "opencode")["plan_id"])

    def test_preview_aggregates_only_pending_work(self):
        p = plan("ubuntu-x64", "opencode")
        self.assertEqual(p["preview"]["download_bytes"], 30000000)  # git already installed
        self.assertEqual(p["preview"]["privileges"], ["USER", "ROOT-ADMIN"])
        self.assertIn({"component": "savia-core", "kind": "path", "target": "~/.savia/bin"}, p["preview"]["changes"])

    def test_arm64_windows_unsupported_node_blocks(self):
        p = plan("windows-arm64", "opencode")
        self.assertEqual(p["status"], "blocked")
        self.assertIn(("node", "unsupported_platform"), codes(p))

    def test_unsupported_distro_blocks(self):
        self.assertIn(("git", "unsupported_platform"), codes(plan("fedora-x64", "git")))

    def test_no_elevation_blocks_root_action(self):
        p = plan("ubuntu-noroot", "git")
        self.assertEqual(p["status"], "blocked")
        self.assertIn(("git", "no_elevation"), codes(p))

    def test_conflict_with_selected_component(self):
        self.assertIn(("opencode", "conflict"), codes(plan("ubuntu-x64", "opencode", "opencode-legacy")))

    def test_conflict_with_installed_component(self):
        h = host("ubuntu-x64")
        h = type(h)(**{**h.__dict__, "installed": {"opencode-legacy": "0.9"}})
        self.assertIn(("opencode", "conflict"), codes(build_plan(MANIFESTS, h, ["opencode"])))

    def test_missing_dependency_and_cycle_block(self):
        m = copy.deepcopy(MANIFESTS)
        m["git"]["depends_on"] = ["ghost"]
        self.assertIn(("ghost", "missing_dependency"), codes(plan("ubuntu-x64", "git", manifests=m)))
        m = copy.deepcopy(MANIFESTS)
        m["git"]["depends_on"] = ["node"]
        m["node"]["depends_on"] = ["git"]
        self.assertTrue(any(c == "dependency_cycle" for _, c in codes(plan("ubuntu-x64", "git", manifests=m))))

    def test_integrity_missing_checksum_blocks(self):
        self.assertIn(("vendor-installer", "integrity"), codes(plan("ubuntu-x64", "vendor-installer")))

    def test_http_source_blocks(self):
        m = copy.deepcopy(MANIFESTS)
        m["savia-core"]["targets"][0]["source"]["locator"] = "http://example.invalid/x.tgz"
        self.assertIn(("savia-core", "integrity"), codes(plan("ubuntu-x64", "savia-core", manifests=m)))

    def test_irreversible_restart_and_manual_are_surfaced(self):
        p = plan("windows-x64", "restart-demo")
        self.assertEqual(p["preview"]["irreversible"], ["restart-demo"])
        self.assertEqual(p["preview"]["restarts"], ["restart-demo"])
        self.assertIn(("restart-demo", "manual_source"), codes(p, "warnings"))
        self.assertEqual(p["status"], "ready_with_warnings")

    def test_adapter_execution_is_out_of_scope(self):
        with self.assertRaises(NotImplementedError):
            FixtureAdapter(str(FX / "hosts/ubuntu-x64.json")).invoke({"executable": "true", "args": []})


class SecretsAndReceipt(unittest.TestCase):
    def test_find_secrets(self):
        self.assertEqual(find_secrets({"a": {"api_key": "x"}}), ["$.a.api_key"])
        self.assertTrue(find_secrets({"u": "ghp_" + "A" * 30}))
        self.assertEqual(find_secrets(plan("ubuntu-x64", "opencode")), [])

    @staticmethod
    def receipt():
        return {
            "schema_version": 1, "receipt_id": "rcpt-0001", "timestamp": "2026-10-24T10:00:00Z",
            "savia_version": "1.0", "installer_version": "0.1", "platform": {"os": "linux", "arch": "x64"},
            "plan_id": "a" * 64, "components": [{"id": "git", "version": "2.45", "source": {"kind": "package_manager"}}],
            "actions": [{"component": "git", "action": "install", "privilege": "ROOT-ADMIN", "result": "ok"}],
            "verification": {"doctor": "INSTALLED_NOT_VERIFIED"}, "warnings": [], "failures": [],
        }

    def test_receipt_valid_and_installer_cannot_claim_supported(self):
        r = self.receipt()
        self.assertEqual(validate(r, "installation-receipt"), [])
        r["verification"]["doctor"] = "SUPPORTED"
        self.assertTrue(validate(r, "installation-receipt"))

    def test_receipt_rejects_bad_timestamp_and_extra_field(self):
        r = self.receipt()
        r["timestamp"] = "yesterday"
        r["token"] = "x"
        errs = validate(r, "installation-receipt")
        self.assertTrue(any("timestamp" in e for e in errs) and any("token" in e for e in errs))


class StateMachine(unittest.TestCase):
    def test_states_match_schema(self):
        self.assertEqual(set(state.TRANSITIONS), set(load_schema("installation-state")["properties"]["state"]["enum"]))

    def test_happy_path_and_illegal_jumps(self):
        s = "discovery"
        for nxt in ["planning", "ready", "installing", "verifying", "completed"]:
            s = state.transition(s, nxt)
        with self.assertRaises(ValueError):
            state.transition("ready", "completed")  # never assume completion
        with self.assertRaises(ValueError):
            state.transition("completed", "installing")

    def test_crash_recovery_offers_resume_rollback_inspect(self):
        self.assertEqual(state.recovery_options("installing"), ["resume", "rollback", "inspect"])
        self.assertEqual(state.recovery_options("completed"), ["inspect"])

    def test_state_document_schema(self):
        doc = {"schema_version": 1, "plan_id": "b" * 64, "state": "installing", "last_successful_sync_at": None}
        self.assertEqual(validate(doc, "installation-state"), [])
        doc["state"] = "done"
        self.assertTrue(validate(doc, "installation-state"))


class Cli(unittest.TestCase):
    def run_cli(self, name, *sel):
        args = [sys.executable, str(ROOT / "scripts/installer-plan.py"), "--manifests", str(FX / "manifests"),
                "--host", str(FX / "hosts" / f"{name}.json")]
        for s in sel:
            args += ["--select", s]
        return subprocess.run(args, capture_output=True, text=True)

    def test_exit_codes(self):
        ok = self.run_cli("ubuntu-x64", "opencode")
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertEqual(json.loads(ok.stdout)["status"], "ready")
        self.assertEqual(self.run_cli("windows-arm64", "opencode").returncode, 2)
        self.assertEqual(self.run_cli("nope", "git").returncode, 1)


if __name__ == "__main__":
    unittest.main()
