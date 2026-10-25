"""SE-398 F2 behavioral tests for native tool -> canonical effect mapping."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from sam_effects import (CRITICAL_EFFECTS, DELEGATING_TOOLS, DISPOSITIONS, SHELL_FLOOR,  # noqa: E402
                         SHELL_TOOLS, UNKNOWN_EFFECT, classify_tool, effect_disposition,
                         load_effect_maps, surface_dispositions, tool_disposition)
from sam_model import SamValidationError  # noqa: E402
from sam_surface import EFFECTS, SURFACE_IDS, load_manifests, resolve_surface  # noqa: E402

BASE = ".scm/runtime-surface"


class SamEffectsTest(unittest.TestCase):
    def setUp(self):
        self.manifests = load_manifests(ROOT)
        self.maps = load_effect_maps(ROOT)

    def test_unmapped_tool_fails_closed(self):
        self.assertEqual([UNKNOWN_EFFECT], classify_tool(self.maps, "claude-code", "Teleport"))
        result = tool_disposition(self.manifests, self.maps, "claude-code-cli", "Teleport")
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", result["disposition"])

    def test_same_name_is_not_same_effect_across_runtimes(self):
        self.assertEqual([UNKNOWN_EFFECT], classify_tool(self.maps, "opencode", "Bash"))
        self.assertIn("EXECUTE_LOCAL", classify_tool(self.maps, "opencode", "bash"))

    def test_mcp_prefix_maps_to_call_mcp(self):
        self.assertEqual(["CALL_MCP", "EXTERNAL_EFFECT"],
                         classify_tool(self.maps, "claude-code", "mcp__x__y"))

    def test_shell_is_worst_case_multi_effect(self):
        effects = classify_tool(self.maps, "codex", "shell")
        for needed in ("EXECUTE_LOCAL", "ACCESS_NETWORK", "EXTERNAL_EFFECT", "WRITE_WORKSPACE"):
            self.assertIn(needed, effects)

    def test_tool_takes_strictest_effect_disposition(self):
        # codex-desktop: EXTERNAL_EFFECT is UNSUPPORTED while the rest degrade.
        result = tool_disposition(self.manifests, self.maps, "codex-desktop", "shell")
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", result["disposition"])

    def test_effect_disposition_exact_table(self):
        table = {"UNSUPPORTED": "UNSUPPORTED_FOR_EFFECT", "EMULATED": "REROUTE_HUMAN",
                 "NATIVE": "CANDIDATE_GATED", "ADAPTED": "CANDIDATE_GATED",
                 "UNKNOWN": "DEGRADED_SAFE", "FOO": "UNSUPPORTED_FOR_EFFECT",
                 "": "UNSUPPORTED_FOR_EFFECT", None: "UNSUPPORTED_FOR_EFFECT"}
        for state, expected in table.items():
            self.assertEqual(expected, effect_disposition(state), state)

    def test_no_surface_disposition_is_an_allow(self):
        for sid in SURFACE_IDS:
            for value in surface_dispositions(self.manifests, sid).values():
                self.assertIn(value, DISPOSITIONS + ("NOT_CRITICAL",))

    def test_delegating_tools_carry_shell_worst_case(self):
        for runtime, names in DELEGATING_TOOLS.items():
            shell = set(classify_tool(self.maps, runtime, SHELL_TOOLS[runtime][0]))
            for name in names:
                self.assertTrue(shell <= set(classify_tool(self.maps, runtime, name)), name)

    def test_network_and_mcp_tools_carry_external_effect(self):
        for runtime, tool in (("claude-code", "WebFetch"), ("opencode", "webfetch"),
                              ("codex", "web_search"), ("claude-code", "mcp__x__y")):
            self.assertIn("EXTERNAL_EFFECT", classify_tool(self.maps, runtime, tool))

    def test_surface_dispositions_follow_resolved_capabilities(self):
        non_critical = {"READ_WORKSPACE", "SEARCH_WORKSPACE", "REQUEST_HUMAN_DECISION"}
        self.assertEqual(set(EFFECTS) - non_critical, set(CRITICAL_EFFECTS))
        for sid in SURFACE_IDS:
            caps = resolve_surface(self.manifests, sid)["capabilities"]
            got = surface_dispositions(self.manifests, sid)
            self.assertEqual(non_critical, {e for e, v in got.items() if v == "NOT_CRITICAL"}, sid)
            for effect in CRITICAL_EFFECTS:
                self.assertEqual(effect_disposition(caps[effect]), got[effect], f"{sid}/{effect}")
        self.assertEqual("UNSUPPORTED_FOR_EFFECT",
                         surface_dispositions(self.manifests, "codex-desktop")["EXTERNAL_EFFECT"])

    def test_missing_capability_fails_closed(self):
        runtime = self.manifests["runtimes"]["codex"]
        caps = dict(runtime["capabilities"])
        del caps["EXECUTE_LOCAL"]
        broken = {"runtimes": {**self.manifests["runtimes"], "codex": {**runtime, "capabilities": caps}},
                  "surfaces": self.manifests["surfaces"]}
        surface = next(s for s in SURFACE_IDS if s.startswith("codex-")
                       and "EXECUTE_LOCAL" not in self.manifests["surfaces"][s].get("capability_overrides", {}))
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", surface_dispositions(broken, surface)["EXECUTE_LOCAL"])

    def test_tool_matching_several_patterns_takes_union(self):
        maps = {"codex": {"tools": {}, "patterns": [
            {"prefix": "mcp__", "effects": ["CALL_MCP"]},
            {"prefix": "mcp__fs", "effects": ["WRITE_WORKSPACE"]}]}}
        self.assertEqual(["CALL_MCP", "WRITE_WORKSPACE"], classify_tool(maps, "codex", "mcp__fs__w"))
        self.assertEqual(["CALL_MCP"], classify_tool(maps, "codex", "mcp__x"))

    def test_opencode_mcp_tool_is_unknown(self):
        self.assertEqual([UNKNOWN_EFFECT], classify_tool(self.maps, "opencode", "mcp__x__y"))

    def test_every_shell_tool_carries_full_floor(self):
        for runtime, names in SHELL_TOOLS.items():
            for name in names:
                self.assertTrue(SHELL_FLOOR <= set(classify_tool(self.maps, runtime, name)), name)

    def test_unknown_surface_rejected(self):
        with self.assertRaises(SamValidationError):
            tool_disposition(self.manifests, self.maps, "nope", "read")


class SamEffectsValidationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / BASE, self.root / BASE)

    def tearDown(self):
        self.temp.cleanup()

    def _edit(self, fn, name="opencode"):
        path = self.root / BASE / "effects" / f"{name}.json"
        doc = json.loads(path.read_text())
        fn(doc)
        path.write_text(json.dumps(doc))

    def _invalid(self):
        with self.assertRaises(SamValidationError) as ctx:
            load_effect_maps(self.root)
        self.assertEqual("INVALID_SURFACE_MANIFEST", ctx.exception.code)

    def test_valid_copy_loads(self):
        self.assertEqual(3, len(load_effect_maps(self.root)))

    def test_rejects_unknown_effect_name(self):
        self._edit(lambda d: d["tools"].update(read=["READ_EVERYTHING"]))
        self._invalid()

    def test_rejects_empty_effect_list(self):
        self._edit(lambda d: d["tools"].update(read=[]))
        self._invalid()

    def test_rejects_forbidden_policy_key(self):
        self._edit(lambda d: d.update(policy="allow"))
        self._invalid()

    def test_rejects_operational_provenance(self):
        self._edit(lambda d: d["provenance"].update(evidence_class="OPERATIONAL"))
        self._invalid()

    def test_rejects_missing_runtime_map(self):
        (self.root / BASE / "effects" / "codex.json").unlink()
        self._invalid()

    def test_rejects_shell_tool_without_execute_local(self):
        self._edit(lambda d: d["tools"].update(bash=["READ_WORKSPACE"]))
        self._invalid()

    def test_rejects_shell_tool_below_floor_even_with_execute_local(self):
        self._edit(lambda d: d["tools"].update(bash=["EXECUTE_LOCAL"], task=["EXECUTE_LOCAL"]))
        self._invalid()

    def test_rejects_second_codex_shell_below_floor(self):
        self._edit(lambda d: d["tools"].update(exec_command=["EXECUTE_LOCAL"]), "codex")
        self._invalid()

    def test_rejects_workspace_write_without_modify_config(self):
        self._edit(lambda d: d["tools"].update(NotebookEdit=["WRITE_WORKSPACE"]), "claude-code")
        self._invalid()

    def test_rejects_delegating_tool_weaker_than_shell(self):
        self._edit(lambda d: d["tools"].update(task=["CREATE_PROCESS"]))
        self._invalid()

    def test_rejects_symlinked_effects_directory(self):
        real = self.root / "real-effects"
        (self.root / BASE / "effects").rename(real)
        (self.root / BASE / "effects").symlink_to(real)
        self._invalid()

    def test_rejects_bad_pattern(self):
        self._edit(lambda d: d.update(patterns=[{"prefix": "", "effects": ["CALL_MCP"]}]),
                   "claude-code")
        self._invalid()


class SamEffectsCliTest(unittest.TestCase):
    def _run(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts/sam.py"), "effects", *args],
                              capture_output=True, text=True, cwd=ROOT)

    def test_cli_tool_disposition(self):
        out = self._run("--surface", "codex-desktop", "--tool", "shell")
        self.assertEqual(0, out.returncode)
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", json.loads(out.stdout)["disposition"])

    def test_cli_tool_without_surface_exits_2(self):
        out = self._run("--tool", "shell")
        self.assertEqual(2, out.returncode)
        self.assertIn("INVALID_SURFACE_MANIFEST", out.stderr)
        self.assertIn("--tool requires --surface", out.stderr)

    def test_cli_unknown_surface_exits_2(self):
        out = self._run("--surface", "nope")
        self.assertEqual(2, out.returncode)
        self.assertIn("INVALID_SURFACE_MANIFEST", out.stderr)
        self.assertEqual("", out.stdout)

    def test_cli_empty_tool_fails_closed(self):
        out = self._run("--surface", "claude-code-cli", "--tool", "")
        self.assertEqual(0, out.returncode)
        result = json.loads(out.stdout)
        self.assertEqual([UNKNOWN_EFFECT], result["effects"])
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", result["disposition"])

    def test_cli_without_arguments_reports_valid(self):
        out = self._run()
        self.assertEqual(0, out.returncode)
        self.assertEqual("SAM EFFECTS: VALID (3 runtimes)", out.stdout.strip())


if __name__ == "__main__":
    unittest.main()
