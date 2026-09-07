"""S1 inventory contract; no real hooks, network, or private configuration."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

AUDIT = Path(__file__).resolve().parents[2] / "scripts/dual-cli/audit.py"


class InventoryContract(unittest.TestCase):
    def setUp(self):
        self.assertTrue(AUDIT.exists(), "S1 audit implementation is missing")
        spec = importlib.util.spec_from_file_location("dual_cli_audit", AUDIT)
        self.audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.audit)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / ".claude").mkdir()
        (self.root / ".scm").mkdir()
        self.write(".scm/resources.json", {"resources": [
            {"kind": "skill", "name": "example", "path": "skills/example"}]})
        self.write(".claude/settings.json", {"hooks": {"PreToolUse": [
            {"matcher": "Bash", "hooks": [
                {"type": "command", "command": "echo PRIVATE_SENTINEL"},
                {"type": "http", "url": "https://PRIVATE_SENTINEL"},
                {"type": "prompt", "prompt": "PRIVATE_SENTINEL"}]}]}})

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def test_all_handler_types_are_inventoried_without_certification(self):
        result = self.audit.inventory(self.root)
        self.assertEqual(result["handler_counts"], {"command": 1, "http": 1, "prompt": 1})
        self.assertFalse(result["certified"])
        self.assertEqual(len(result["handlers"]), 3)
        for handler in result["handlers"]:
            self.assertEqual(handler["frontends"], {"codex": "untested", "opencode": "untested"})

    def test_inventory_does_not_expose_hook_payloads(self):
        self.assertNotIn("PRIVATE_SENTINEL", json.dumps(self.audit.inventory(self.root)))

    def test_revision_is_stable_and_changes_with_policy(self):
        first = self.audit.inventory(self.root)["revision"]
        self.assertEqual(first, self.audit.inventory(self.root)["revision"])
        self.write(".claude/settings.json", {"hooks": {}})
        self.assertNotEqual(first, self.audit.inventory(self.root)["revision"])

    def test_registry_capabilities_are_not_silently_certified(self):
        result = self.audit.inventory(self.root)
        self.assertEqual(result["resource_counts"], {"skill": 1})
        self.assertIn("MCP_CONTRACTS_UNTESTED", result["gaps"])
        self.assertIn("TS_GUARDS_UNCLASSIFIED", result["gaps"])

    def test_corrupt_settings_fail_closed(self):
        (self.root / ".claude/settings.json").write_text("{partial")
        with self.assertRaises(ValueError):
            self.audit.inventory(self.root)

    def test_invalid_handler_structure_fails_closed(self):
        self.write(".claude/settings.json", {"hooks": {"PreToolUse": [{}]}})
        with self.assertRaises(ValueError):
            self.audit.inventory(self.root)

    def test_unknown_handler_remains_visible(self):
        self.write(".claude/settings.json", {"hooks": {"Stop": [
            {"hooks": [{"type": "future-handler"}]}]}})
        result = self.audit.inventory(self.root)
        self.assertEqual(result["handler_counts"], {"future-handler": 1})
        self.assertIn("UNSUPPORTED_HANDLER_TYPE", result["gaps"])


if __name__ == "__main__":
    unittest.main()
