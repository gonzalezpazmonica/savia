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

from provisioning import schema_lite, state  # noqa: E402
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
        for f in sorted((FX / "manifests").glob("*.json")):
            self.assertEqual(validate(json.loads(f.read_text()), "component-manifest"), [], f.name)

    def test_pattern_anchor_rejects_trailing_newline(self):
        m = copy.deepcopy(MANIFESTS["savia-core"])
        m["targets"][0]["source"]["integrity"]["sha256"] = "a" * 64 + "\n"
        self.assertTrue(validate(m, "component-manifest"))
        m = copy.deepcopy(MANIFESTS["git"])
        m["id"] = "git\n"
        self.assertTrue(validate(m, "component-manifest"))

    def test_schema_errors_never_echo_document_values(self):
        leak = "https://user:hunter2@example.invalid/x"
        errs = schema_lite.validate(leak, {"enum": ["a"]}) + schema_lite.validate(leak, {"type": "string", "pattern": "^a$"})
        self.assertEqual(len(errs), 2)
        self.assertFalse(any("hunter2" in e for e in errs), errs)

    def test_compensation_must_name_a_declared_action(self):
        m = copy.deepcopy(MANIFESTS)
        a = m["opencode"]["targets"][0]["actions"]
        a["install"]["compensation"] = "rollback"
        a.pop("rollback", None)
        self.assertIn(("opencode", "compensation_missing"), codes(build_plan(m, host("ubuntu-x64"), ["opencode"])))
        self.assertNotIn(("savia-core", "compensation_missing"), codes(plan("ubuntu-x64", "savia-core")))

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


class SchemaLite(unittest.TestCase):
    def test_const_and_enum_do_not_conflate_bool_and_int(self):
        self.assertTrue(schema_lite.validate(True, {"const": 1}))
        self.assertTrue(schema_lite.validate(True, {"enum": [1, 2]}))
        self.assertEqual(schema_lite.validate(1, {"const": 1}), [])

    def test_unsupported_keyword_and_type_fail_loudly(self):
        self.assertTrue(schema_lite.validate("abc", {"maxLength": 1}))
        with self.assertRaises(ValueError):
            schema_lite.validate(1, {"type": "number"})


class SchemaLiteGaps(unittest.TestCase):
    def test_unique_items_ignores_key_order(self):
        sch = {"type": "array", "uniqueItems": True}
        self.assertTrue(schema_lite.validate([{"a": 1, "b": 2}, {"b": 2, "a": 1}], sch))

    def test_additional_properties_subschema_enforced(self):
        sch = {"type": "object", "additionalProperties": {"type": "string"}}
        self.assertEqual(schema_lite.validate({"x": "ok"}, sch), [])
        self.assertTrue(schema_lite.validate({"x": 1}, sch))

    def test_unsupported_keyword_in_unvisited_defs_detected(self):
        sch = {"type": "object", "$defs": {"unused": {"type": "string", "maxLength": 3}}}
        self.assertTrue(any("maxLength" in e for e in schema_lite.validate({}, sch)))

    def test_manifest_with_secret_rejected_at_load(self):
        with tempfile.TemporaryDirectory() as d:
            m = json.loads((FX / "manifests/git.json").read_text())
            m["targets"][0]["source"]["locator"] = "https://user:hunter2@example.invalid/x"
            (Path(d) / "g.json").write_text(json.dumps(m))
            with self.assertRaises(ValueError):
                load_manifests(d)


class Planner(unittest.TestCase):
    def test_ubuntu_ready_and_ordered_by_dependencies(self):
        p = plan("ubuntu-x64", "opencode")
        self.assertEqual(p["status"], "ready_with_warnings")  # git 2.40 installed vs manifest 2.45
        self.assertIn(("git", "version_mismatch"), codes(p, "warnings"))
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

    def test_installed_component_skips_install_blockers(self):
        # P1: git installed + no elevation must not block on a root install that never runs
        h = host("ubuntu-noroot")
        h = type(h)(**{**h.__dict__, "installed": {"git": "2.45"}})
        p = build_plan(MANIFESTS, h, ["git"])
        self.assertEqual(p["status"], "ready")
        self.assertEqual([(s["component"], s["disposition"]) for s in p["steps"]], [("git", "already_installed")])
        self.assertEqual(p["preview"]["download_bytes"], 0)

    def test_installed_component_without_target_or_sha_does_not_block(self):
        h = host("fedora-x64")
        h = type(h)(**{**h.__dict__, "installed": {"git": "2.45"}})
        p = build_plan(MANIFESTS, h, ["git"])
        self.assertEqual(p["status"], "ready")
        self.assertEqual(p["steps"][0]["disposition"], "already_installed")
        self.assertEqual(validate(p, "installation-plan"), [])

    def test_reverse_conflict_installed_declares_it(self):
        h = host("ubuntu-x64")
        h = type(h)(**{**h.__dict__, "installed": {"opencode": "1.2"}})
        self.assertIn(("opencode-legacy", "conflict"), codes(build_plan(MANIFESTS, h, ["opencode-legacy"])))

    def test_installed_dependency_without_manifest_is_not_missing(self):
        m = copy.deepcopy(MANIFESTS)
        m["git"]["depends_on"] = ["ghost"]
        h = host("ubuntu-x64")
        h = type(h)(**{**h.__dict__, "installed": {"git": "2.45", "ghost": "1"}})
        self.assertNotIn(("ghost", "missing_dependency"), codes(build_plan(m, h, ["git"])))

    def test_missing_dependency_reported_once_for_shared_parent(self):
        m = copy.deepcopy(MANIFESTS)
        m["git"]["depends_on"] = ["ghost"]
        m["node"]["depends_on"] = ["ghost"]
        p = plan("ubuntu-x64", "git", "node", manifests=m)
        self.assertEqual([b["component"] for b in p["blockers"]].count("ghost"), 1)

    def test_non_https_schemes_block(self):
        for loc in ["file:///tmp/x.tgz", "git://example.invalid/x", "smb://h/x", " http://example.invalid/x", "http://example.invalid/x"]:
            m = copy.deepcopy(MANIFESTS)
            m["savia-core"]["targets"][0]["source"]["locator"] = loc
            self.assertIn(("savia-core", "integrity"), codes(plan("ubuntu-x64", "savia-core", manifests=m)), loc)

    def test_uninstall_is_never_a_copy_of_install(self):
        for cid, m in MANIFESTS.items():
            for t in m["targets"]:
                a = t["actions"]
                if "uninstall" in a:
                    self.assertNotEqual(a["install"]["invocation"], a["uninstall"]["invocation"], cid)

    def test_shell_interpreter_and_recovery_elevation_warn(self):
        p = plan("ubuntu-x64", "vendor-installer")
        self.assertIn(("vendor-installer", "shell_interpreter"), codes(p, "warnings"))
        self.assertNotIn(("vendor-installer", "shell_interpreter"), codes(p))
        h = host("ubuntu-noroot")
        self.assertFalse(h.elevation_available)
        m = copy.deepcopy(MANIFESTS)
        t = m["opencode"]["targets"][0]
        t["actions"]["uninstall"]["privilege"] = "ROOT-ADMIN"
        self.assertIn(("opencode", "recovery_needs_elevation"), codes(build_plan(m, h, ["opencode"]), "warnings"))

    def test_shell_interpreter_variants_detected(self):
        for exe, args in (("bash.exe", ["-c", "x"]), ("wsl", ["sh"]), ("/usr/bin/env", ["bash", "-c", "x"]),
                          ("busybox", ["sh", "-c", "x"]), ("python3", ["-c", "print(1)"]), ("node", ["-e", "1"]),
                          ("env", ["-u", "VAR", "bash", "-c", "x"]), ("sudo", ["-n", "sh"]), ("nohup", ["bash"]),
                          ("timeout", ["5", "sh"]), ("env", ["-S", "bash -c x"]), ("xargs", ["sh", "-c", "x"])):
            m = copy.deepcopy(MANIFESTS)
            inv = m["opencode"]["targets"][0]["actions"]["install"]["invocation"]
            inv["executable"], inv["args"] = exe, args
            self.assertIn(("opencode", "shell_interpreter"), codes(build_plan(m, host("ubuntu-x64"), ["opencode"]), "warnings"), exe)
        m = copy.deepcopy(MANIFESTS)
        inv = m["opencode"]["targets"][0]["actions"]["install"]["invocation"]
        inv["executable"], inv["args"] = "python3", ["setup.py"]
        self.assertNotIn(("opencode", "shell_interpreter"), codes(build_plan(m, host("ubuntu-x64"), ["opencode"]), "warnings"))

    def test_wrapper_without_shell_not_flagged(self):
        m = copy.deepcopy(MANIFESTS)
        inv = m["opencode"]["targets"][0]["actions"]["install"]["invocation"]
        inv["executable"], inv["args"] = "env", ["-u", "VAR", "tool", "--version"]
        self.assertNotIn(("opencode", "shell_interpreter"), codes(build_plan(m, host("ubuntu-x64"), ["opencode"]), "warnings"))

    def test_datetime_format_rejects_trailing_newline_and_unicode_digits(self):
        sch = {"type": "string", "format": "date-time"}
        self.assertEqual(schema_lite.validate("2026-01-01T00:00:00Z", sch), [])
        for bad in ("2026-01-01T00:00:00Z\n", "\u0662026-01-01T00:00:00Z"):
            self.assertNotEqual(schema_lite.validate(bad, sch), [], repr(bad))

    def test_cwd_must_be_relative_and_contained(self):
        for bad in ("/etc", "../x", "a/../../x", "C:\\Windows", "a\\..\\b"):
            m = copy.deepcopy(MANIFESTS)
            m["opencode"]["targets"][0]["actions"]["install"]["invocation"]["cwd"] = bad
            self.assertTrue(validate(m["opencode"], "component-manifest"), bad)
        m = copy.deepcopy(MANIFESTS)
        m["opencode"]["targets"][0]["actions"]["install"]["invocation"]["cwd"] = "build/out"
        self.assertEqual(validate(m["opencode"], "component-manifest"), [])

    def test_package_manager_locator_validated(self):
        for bad in ("npm:https://example.invalid/x", "apt:", "curl:x", "npm:a b"):
            m = copy.deepcopy(MANIFESTS)
            m["opencode"]["targets"][0]["source"]["locator"] = bad
            self.assertIn(("opencode", "integrity"), codes(build_plan(m, host("ubuntu-x64"), ["opencode"])), bad)
        self.assertNotIn(("opencode", "integrity"), codes(plan("ubuntu-x64", "opencode")))

    def test_plan_id_covers_invocation(self):
        m = copy.deepcopy(MANIFESTS)
        m["opencode"]["targets"][0]["actions"]["install"]["invocation"]["args"].append("--extra")
        self.assertNotEqual(build_plan(m, host("ubuntu-x64"), ["opencode"])["plan_id"], plan("ubuntu-x64", "opencode")["plan_id"])

    def test_selected_installed_without_manifest_warns(self):
        m = {k: v for k, v in MANIFESTS.items() if k != "git"}
        p = build_plan(m, host("ubuntu-x64"), ["git"])
        self.assertIn(("git", "no_manifest_for_installed"), codes(p, "warnings"))

    def test_adapter_execution_is_out_of_scope(self):
        with self.assertRaises(NotImplementedError):
            FixtureAdapter(str(FX / "hosts/ubuntu-x64.json")).invoke({"executable": "true", "args": []})


class SecretsAndReceipt(unittest.TestCase):
    def test_find_secrets(self):
        self.assertEqual(find_secrets({"a": {"api_key": "x"}}), ["$.a.api_key"])
        self.assertTrue(find_secrets({"u": "ghp_" + "A" * 30}))
        self.assertEqual(find_secrets(plan("ubuntu-x64", "opencode")), [])
        self.assertTrue(find_secrets({"locator": "https://user:pw@example.invalid/x"}))
        self.assertEqual(find_secrets({"locator": "https://example.invalid/a@b"}), [])

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
        for st in ("failed", "partially-rolled-back", "repair-required"):
            self.assertIn("rollback", state.recovery_options(st), st)

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
        self.assertEqual(json.loads(ok.stdout)["status"], "ready_with_warnings")
        self.assertEqual(self.run_cli("windows-arm64", "opencode").returncode, 2)
        self.assertEqual(self.run_cli("nope", "git").returncode, 1)

    def test_self_check_failure_does_not_print_values(self):
        leak = "ghp_" + "A" * 30
        with tempfile.TemporaryDirectory() as d:
            h = json.loads((FX / "hosts/ubuntu-x64.json").read_text())
            h["installed"]["git"] = leak  # flows into a version_mismatch warning
            h["os"] = leak + "-os"        # fails the plan schema enum
            hp = Path(d) / "h.json"
            hp.write_text(json.dumps(h))
            r = subprocess.run([sys.executable, str(ROOT / "scripts/installer-plan.py"), "--manifests", str(FX / "manifests"),
                                "--host", str(hp), "--select", "git"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("self-check", r.stderr)
        self.assertNotIn(leak, r.stderr + r.stdout)

    def test_secret_in_valid_plan_prints_only_count(self):
        # The plan passes the schema; only the secret scanner can stop it (mutation: drop find_secrets -> exit 0).
        leak = "ghp_" + "B" * 30
        with tempfile.TemporaryDirectory() as d:
            h = json.loads((FX / "hosts/ubuntu-x64.json").read_text())
            h["installed"]["git"] = leak  # becomes a version_mismatch warning carrying the value
            hp = Path(d) / "h.json"
            hp.write_text(json.dumps(h))
            r = subprocess.run([sys.executable, str(ROOT / "scripts/installer-plan.py"), "--manifests", str(FX / "manifests"),
                                "--host", str(hp), "--select", "git"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("secret-like content in 1 location(s)", r.stderr)
        self.assertNotIn(leak, r.stderr + r.stdout)

    def test_unknown_selection_is_invalid_input_exit_1(self):
        r = self.run_cli("ubuntu-x64", "no-such-component")
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("unknown component", r.stderr)
        self.assertEqual(self.run_cli("ubuntu-x64", "git").returncode, 0)

    def test_usage_error_is_exit_1_not_blocked(self):
        script = str(Path(__file__).resolve().parents[2] / "scripts/installer-plan.py")
        for argv in ([], ["--manifests", str(FX / "manifests")], ["--bogus"]):
            r = subprocess.run([sys.executable, script, *argv], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1, argv)


if __name__ == "__main__":
    unittest.main()
