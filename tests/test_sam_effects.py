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

from sam_effects import (DISPOSITIONS, UNKNOWN_EFFECT, classify_tool, effect_disposition,  # noqa: E402
                         load_effect_maps, surface_dispositions, tool_disposition)
from sam_model import SamValidationError  # noqa: E402
from sam_surface import EFFECTS, SURFACE_IDS, load_manifests  # noqa: E402

BASE = ".scm/runtime-surface"


class SamEffectsTest(unittest.TestCase):
    def setUp(self):
        self.manifests = load_manifests(ROOT)
        self.maps = load_effect_maps(ROOT)

    def test_unmapped_tool_fails_closed(self):
        self.assertEqual([UNKNOWN_EFFECT], classify_tool(self.maps, "claude-code", "Teleport"))
        result = tool_disposition(self.manifests, self.maps, "claude-code-cli", "Teleport")
        self.assertEqual("DEGRADED_SAFE", result["disposition"])

    def test_same_name_is_not_same_effect_across_runtimes(self):
        self.assertEqual([UNKNOWN_EFFECT], classify_tool(self.maps, "opencode", "Bash"))
        self.assertIn("EXECUTE_LOCAL", classify_tool(self.maps, "opencode", "bash"))

    def test_mcp_prefix_maps_to_call_mcp(self):
        self.assertEqual(["CALL_MCP"], classify_tool(self.maps, "claude-code", "mcp__x__y"))

    def test_shell_is_worst_case_multi_effect(self):
        effects = classify_tool(self.maps, "codex", "shell")
        for needed in ("EXECUTE_LOCAL", "ACCESS_NETWORK", "EXTERNAL_EFFECT", "WRITE_WORKSPACE"):
            self.assertIn(needed, effects)

    def test_tool_takes_strictest_effect_disposition(self):
        # codex-desktop: EXTERNAL_EFFECT is UNSUPPORTED while the rest degrade.
        result = tool_disposition(self.manifests, self.maps, "codex-desktop", "shell")
        self.assertEqual("UNSUPPORTED_FOR_EFFECT", result["disposition"])

    def test_no_disposition_is_ever_an_allow(self):
        for state in ("NATIVE", "ADAPTED", "EMULATED", "UNKNOWN", "UNSUPPORTED"):
            self.assertIn(effect_disposition(state), DISPOSITIONS)
        for sid in SURFACE_IDS:
            values = set(surface_dispositions(self.manifests, sid).values())
            self.assertFalse({v for v in values if "ALLOW" in v})

    def test_every_surface_covers_every_effect(self):
        for sid in SURFACE_IDS:
            self.assertEqual(set(EFFECTS), set(surface_dispositions(self.manifests, sid)))

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
        self.assertEqual(2, self._run("--tool", "shell").returncode)


if __name__ == "__main__":
    unittest.main()
