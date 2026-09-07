import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/dual-cli"))
from domain_packs import activate, load
from protocol import ProtocolError

class DomainPackTests(unittest.TestCase):
    def test_core_pack_does_not_require_pm_or_ado(self):
        packs=load(Path(__file__).resolve().parents[2] / "config/domain-packs.json")
        active=activate(packs,["core-local"])
        self.assertEqual(active[0]["memory_namespace"], "core-local")
        self.assertEqual(active[0]["context_refs"], [])

    def test_unknown_or_colliding_namespace_blocks_activation(self):
        packs=load(Path(__file__).resolve().parents[2] / "config/domain-packs.json")
        with self.assertRaisesRegex(ProtocolError, "CONFIG_CONFLICT"):
            activate(packs,["missing"])
        packs["other"]=dict(packs["core-local"], id="other")
        with self.assertRaisesRegex(ProtocolError, "CONFIG_CONFLICT"):
            activate(packs,["core-local","other"])

    def test_dependencies_are_resolved_and_missing_dependencies_block(self):
        packs=load(Path(__file__).resolve().parents[2] / "config/domain-packs.json")
        self.assertEqual([p["id"] for p in activate(packs,["pm-sdd-legacy"])],
                         ["core-local", "pm-sdd-legacy"])
        broken=dict(packs["pm-sdd-legacy"], dependencies=["missing@1"])
        packs["broken"]=dict(broken, id="broken", memory_namespace="broken")
        with self.assertRaisesRegex(ProtocolError, "CONFIG_CONFLICT"):
            activate(packs,["broken"])

if __name__ == "__main__": unittest.main()
