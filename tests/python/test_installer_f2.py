"""SE-399 F2 — read-only detection, dependency graph, preflight and retirement report."""
from __future__ import annotations

import dataclasses
import json
import subprocess
import sys
import tempfile
import unittest
from collections import namedtuple
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FX = ROOT / "tests/fixtures/installer"
sys.path.insert(0, str(ROOT / "scripts"))

from provisioning import graph  # noqa: E402
from provisioning.adapter import FixtureAdapter  # noqa: E402
from provisioning.local import LocalAdapter  # noqa: E402
from provisioning.planner import build_plan, find_secrets, load_manifests, validate  # noqa: E402

MANIFESTS = load_manifests(str(FX / "manifests"))
Usage = namedtuple("Usage", "total used free")


def _no_file(path):
    raise OSError("absent")


def fx_host(name, **over):
    return dataclasses.replace(FixtureAdapter(str(FX / "hosts" / f"{name}.json")).discover(), **over)


def local(**kw):
    base = dict(env={}, which=lambda n: None, system="Linux", machine="x86_64",
                disk_usage=lambda p: Usage(10, 1, 9 * 10**9), read=_no_file, geteuid=lambda: 1000, home="/h")
    base.update(kw)
    return LocalAdapter(MANIFESTS, **base)


def codes(p, kind="blockers"):
    return {(f["component"], f["code"]) for f in p[kind]}


class LocalDetection(unittest.TestCase):
    def test_detects_facts_through_path_lookup_only(self):
        present = {"apt", "npm", "sudo"}
        looked = []

        def which(n):
            looked.append(n)
            return f"/usr/bin/{n}" if n in present else None

        def read(p):
            if p == "/etc/os-release":
                return 'ID="ubuntu"\nNAME=x\n'
            raise OSError

        h = local(which=which, read=read, env={"SHELL": "/bin/zsh"}).discover()
        self.assertEqual((h.os, h.arch, h.distro, h.shell), ("linux", "x64", "ubuntu", "zsh"))
        self.assertEqual(h.package_managers, ("apt", "npm"))
        self.assertTrue(h.elevation_available)
        self.assertEqual(h.disk_free_bytes, 9 * 10**9)
        self.assertEqual(h.installed, {})  # git not on PATH
        self.assertIn("git", looked)  # the manifest's detection executable was only looked up

    def test_installed_is_presence_only_with_unknown_version(self):
        h = local(which=lambda n: "/x/" + n if n == "git" else None).discover()
        self.assertEqual(h.installed, {"git": "unknown"})

    def test_proxy_recorded_as_presence_never_value(self):
        h = local(env={"HTTPS_PROXY": "http://user:pa55@proxy.example:3128", "GITHUB_TOKEN": "ghp_" + "C" * 30}).discover()
        self.assertTrue(h.proxy_configured)
        self.assertNotIn("pa55", repr(h))
        self.assertNotIn("ghp_", repr(h))
        self.assertFalse(local(env={}).discover().proxy_configured)

    def test_wsl_root_and_windows_arm(self):
        self.assertTrue(local(env={"WSL_DISTRO_NAME": "Ubuntu"}).discover().is_wsl)
        self.assertFalse(local().discover().is_wsl)
        self.assertTrue(local(geteuid=lambda: 0).discover().is_root)
        w = local(system="Windows", machine="ARM64", which=lambda n: "w" if n == "winget" else None).discover()
        self.assertEqual((w.os, w.arch, w.distro, w.package_managers), ("windows", "arm64", "", ("winget",)))
        self.assertFalse(w.elevation_available)  # not detectable on Windows in F2: fail safe

    def test_unsupported_host_refused_not_guessed(self):
        with self.assertRaises(ValueError):
            local(system="Darwin").discover()
        with self.assertRaises(ValueError):
            local(machine="riscv64").discover()

    def test_derivative_distro_matches_via_id_like(self):
        mint = 'ID=linuxmint\nID_LIKE="ubuntu debian"\n'
        self.assertEqual(local(read=lambda p: mint).discover().distro, "ubuntu")
        other = 'ID=weird\nID_LIKE=arch\n'
        self.assertEqual(local(read=lambda p: other).discover().distro, "weird")

    def test_executable_with_path_is_never_looked_up(self):
        looked = []
        man = {"x": {"detection": {"executable": "/opt/x/bin/x", "args": []}}}
        LocalAdapter(man, env={}, which=lambda n: looked.append(n), system="Linux", machine="x86_64",
                     disk_usage=lambda p: Usage(10, 1, 9), read=_no_file, geteuid=lambda: 1000, home="/h").discover()
        self.assertNotIn("/opt/x/bin/x", looked)

    def test_disk_measure_failure_is_none(self):
        def boom(p):
            raise OSError("x")

        self.assertIsNone(local(disk_usage=boom).discover().disk_free_bytes)


class Graph(unittest.TestCase):
    def test_edges_cover_selection_closure(self):
        p = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=10**12), ["opencode"])
        edges = {(e["from"], e["to"]) for e in p["graph"]["edges"]}
        self.assertIn(("opencode", "node"), edges)
        self.assertIn(("opencode", "savia-core"), edges)
        self.assertEqual({n["id"] for n in p["graph"]["nodes"]}, {s["component"] for s in p["steps"]})
        self.assertEqual(validate(p, "installation-plan"), [])

    def test_dependents_are_transitive_and_exclude_absent(self):
        # opencode -> savia-core -> node
        self.assertEqual(graph.dependents(MANIFESTS, {"node", "savia-core", "opencode"}, "node"), ["opencode", "savia-core"])
        self.assertEqual(graph.dependents(MANIFESTS, {"node", "savia-core", "opencode"}, "savia-core"), ["opencode"])
        self.assertEqual(graph.dependents(MANIFESTS, {"node", "savia-core"}, "savia-core"), [])  # opencode not present

    def test_retirement_safe_only_when_nothing_present_depends(self):
        self.assertFalse(graph.retirement(MANIFESTS, {"savia-core", "opencode"}, "savia-core")["safe"])
        self.assertTrue(graph.retirement(MANIFESTS, {"savia-core", "opencode"}, "opencode")["safe"])


    def test_retirement_fails_closed_when_presence_is_undetectable(self):
        # --local: opencode declares no detection, so it may be installed and depend on savia-core
        r = graph.retirement(MANIFESTS, {"savia-core"}, "savia-core", undetectable=["opencode"])
        self.assertFalse(r["safe"])
        self.assertEqual(r["undetermined"], ["opencode"])
        # the component itself cannot be detected: presence is unknown, never "safe"
        u = graph.retirement(MANIFESTS, set(), "opencode", undetectable=["opencode"])
        self.assertEqual((u["present"], u["safe"]), ("unknown", False))
        # detectable and absent: known absent, nothing to break
        self.assertEqual(graph.retirement(MANIFESTS, set(), "vendor-installer", undetectable=["opencode"])["safe"], True)


class Preflight(unittest.TestCase):
    def test_disk_boundary_is_exact(self):
        need = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=10**12), ["opencode"])["preview"]
        need = need["download_bytes"] + need["disk_bytes"]
        eq = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=need), ["opencode"])
        short = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=need - 1), ["opencode"])
        self.assertNotIn(("host", "preflight_disk"), codes(eq))
        self.assertIn(("host", "preflight_disk"), codes(short))

    def test_disk_insufficient_blocks(self):
        p = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=1000), ["opencode"])
        self.assertEqual(p["status"], "blocked")
        self.assertIn(("host", "preflight_disk"), codes(p))
        self.assertEqual(p["preflight"]["status"], "blockers")

    def test_disk_sufficient_ok_and_unknown_warns(self):
        ok = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=10**12), ["opencode"])
        self.assertNotIn(("host", "preflight_disk"), codes(ok) | codes(ok, "warnings"))
        unk = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=None), ["opencode"])
        self.assertIn(("host", "preflight_disk"), codes(unk, "warnings"))

    def test_missing_package_manager_blocks(self):
        h = fx_host("ubuntu-x64", disk_free_bytes=10**12, package_managers=("apt",))  # npm missing
        p = build_plan(MANIFESTS, h, ["opencode"])
        self.assertIn(("opencode", "preflight_package_manager"), codes(p))

    def test_nothing_to_install_never_blocks_on_disk(self):
        p = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=0), ["git"])
        self.assertNotIn(("host", "preflight_disk"), codes(p))

    def test_proxy_and_wsl_warn_and_network_not_probed(self):
        h = fx_host("ubuntu-x64", disk_free_bytes=10**12, proxy_configured=True, is_wsl=True)
        p = build_plan(MANIFESTS, h, ["opencode"])
        self.assertTrue({("host", "preflight_proxy"), ("host", "preflight_wsl")} <= codes(p, "warnings"))
        st = {c["id"]: c["status"] for c in p["preflight"]["checks"]}
        self.assertEqual(st["network"], "not_probed")
        self.assertEqual(st["certificates"], "not_probed")

    def test_unknown_version_warns_instead_of_mismatch(self):
        p = build_plan(MANIFESTS, fx_host("ubuntu-x64", disk_free_bytes=10**12, installed={"git": "unknown"}), ["git"])
        self.assertIn(("git", "version_unknown"), codes(p, "warnings"))
        self.assertNotIn(("git", "version_mismatch"), codes(p, "warnings"))

    def test_plan_has_no_secrets_and_is_deterministic(self):
        h = fx_host("ubuntu-x64", disk_free_bytes=10**12)
        a, b = build_plan(MANIFESTS, h, ["opencode"]), build_plan(MANIFESTS, h, ["opencode"])
        self.assertEqual(a, b)
        self.assertEqual(find_secrets(a), [])


class Cli(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts/installer-plan.py"), "--manifests", str(FX / "manifests"), *args],
                              capture_output=True, text=True)

    def test_retire_exit_codes_and_unknown(self):
        with tempfile.TemporaryDirectory() as d:
            h = json.loads((FX / "hosts/ubuntu-x64.json").read_text())
            h["installed"] = {"savia-core": "1.0", "opencode": "1.2"}
            hp = Path(d) / "h.json"
            hp.write_text(json.dumps(h))
            unsafe = self.run_cli("--host", str(hp), "--retire", "savia-core")
            safe = self.run_cli("--host", str(hp), "--retire", "opencode")
            unknown = self.run_cli("--host", str(hp), "--retire", "nope")
        self.assertEqual(unsafe.returncode, 2, unsafe.stderr)
        self.assertEqual(json.loads(unsafe.stdout)["dependents"], ["opencode"])
        self.assertEqual(safe.returncode, 0, safe.stderr)
        self.assertEqual(unknown.returncode, 1)

    def test_retire_local_fails_closed_for_undetectable_components(self):
        r = self.run_cli("--local", "--retire", "savia-core")
        if r.returncode == 1 and "unsupported host" in r.stderr:
            self.skipTest("host outside the MVP matrix")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("opencode", json.loads(r.stdout)["undetermined"])

    def test_empty_retire_is_invalid_input_not_a_traceback(self):
        r = self.run_cli("--host", str(FX / "hosts/ubuntu-x64.json"), "--retire", "")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("Traceback", r.stderr)

    def test_local_and_host_are_exclusive_and_one_is_required(self):
        self.assertEqual(self.run_cli("--select", "git").returncode, 1)
        both = self.run_cli("--host", str(FX / "hosts/ubuntu-x64.json"), "--local", "--select", "git")
        self.assertEqual(both.returncode, 1)

    def test_local_runs_on_this_machine_and_prints_valid_plan(self):
        r = self.run_cli("--local", "--select", "git")
        if r.returncode == 1 and "unsupported host" in r.stderr:
            self.skipTest("host outside the MVP matrix")
        self.assertIn(r.returncode, (0, 2), r.stderr)
        self.assertEqual(validate(json.loads(r.stdout), "installation-plan"), [])


if __name__ == "__main__":
    unittest.main()
