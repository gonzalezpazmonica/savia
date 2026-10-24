"""SE-398 F1 behavioral tests for runtime/surface manifests."""
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

from sam_model import SamValidationError  # noqa: E402
from sam_surface import SURFACE_IDS, RUNTIME_IDS, load_manifests, resolve_surface  # noqa: E402

BASE = ".scm/runtime-surface"


class SamSurfaceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / BASE, self.root / BASE)

    def tearDown(self):
        self.temp.cleanup()

    def _edit(self, rel, fn):
        path = self.root / BASE / rel
        doc = json.loads(path.read_text())
        fn(doc)
        path.write_text(json.dumps(doc))

    def _invalid(self):
        with self.assertRaises(SamValidationError) as ctx:
            load_manifests(self.root)
        self.assertEqual("INVALID_SURFACE_MANIFEST", ctx.exception.code)

    def test_committed_manifests_cover_three_runtimes_six_surfaces(self):
        manifests = load_manifests(ROOT)
        self.assertEqual(set(RUNTIME_IDS), set(manifests["runtimes"]))
        self.assertEqual(set(SURFACE_IDS), set(manifests["surfaces"]))

    def test_surface_inherits_runtime_and_applies_only_deltas(self):
        manifests = load_manifests(ROOT)
        view = resolve_surface(manifests, "opencode-desktop")
        runtime = manifests["runtimes"]["opencode"]["capabilities"]
        self.assertEqual(runtime["READ_WORKSPACE"], view["capabilities"]["READ_WORKSPACE"])
        self.assertEqual("UNKNOWN", view["capabilities"]["EXECUTE_LOCAL"])
        self.assertEqual("ADAPTED", runtime["EXECUTE_LOCAL"])
        self.assertEqual("NONE_REPORT_ONLY", view["claims"])

    def test_surface_cannot_widen_runtime_capability(self):
        self._edit("surfaces/codex-desktop.json",
                   lambda d: d["capability_overrides"].update(EXTERNAL_EFFECT="NATIVE"))
        self._invalid()

    def test_supported_state_is_rejected(self):
        self._edit("surfaces/codex-desktop.json", lambda d: d.update(state="supported"))
        self._invalid()

    def test_equivalence_above_e1_is_rejected(self):
        self._edit("surfaces/opencode-tui.json", lambda d: d.update(equivalence="E3"))
        self._invalid()

    def test_policy_ownership_keys_are_rejected_anywhere(self):
        self._edit("surfaces/claude-code-cli.json",
                   lambda d: d["deltas"].update(policy_owner="surface"))
        self._invalid()

    def test_operational_evidence_is_rejected_in_f1(self):
        self._edit("runtimes/codex.json",
                   lambda d: d["provenance"].update(evidence_class="OPERATIONAL"))
        self._invalid()

    def test_missing_provenance_is_rejected(self):
        self._edit("runtimes/opencode.json", lambda d: d.pop("provenance"))
        self._invalid()

    def test_unknown_capability_state_is_rejected(self):
        self._edit("runtimes/opencode.json",
                   lambda d: d["capabilities"].update(READ_WORKSPACE="MAYBE"))
        self._invalid()

    def test_incomplete_effect_set_is_rejected(self):
        self._edit("runtimes/claude-code.json", lambda d: d["capabilities"].pop("CALL_MCP"))
        self._invalid()

    def test_surface_delta_outside_known_domains_is_rejected(self):
        self._edit("surfaces/opencode-tui.json", lambda d: d["deltas"].update(colour="x"))
        self._invalid()

    def test_surface_pointing_to_foreign_runtime_is_rejected(self):
        self._edit("surfaces/codex-cli.json", lambda d: d.update(runtime="opencode"))
        self._invalid()

    def test_missing_surface_is_rejected(self):
        (self.root / BASE / "surfaces/codex-cli.json").unlink()
        self._invalid()

    def test_duplicate_json_key_is_rejected(self):
        path = self.root / BASE / "runtimes/codex.json"
        path.write_text(path.read_text().replace('"kind": "runtime",',
                                                 '"kind": "runtime", "kind": "runtime",'))
        self._invalid()

    def test_cli_validates_and_fails_on_corruption(self):
        cmd = [sys.executable, str(ROOT / "scripts/sam.py"), "surface", "--root", str(self.root)]
        ok = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(0, ok.returncode, ok.stderr)
        self.assertIn("VALID", ok.stdout)
        self._edit("surfaces/codex-desktop.json", lambda d: d.update(state="supported"))
        bad = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(2, bad.returncode)
        self.assertIn("INVALID_SURFACE_MANIFEST", bad.stderr)

    def test_unknown_surface_resolve_fails(self):
        with self.assertRaises(SamValidationError):
            resolve_surface(load_manifests(ROOT), "nope")


if __name__ == "__main__":
    unittest.main()
