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

if __name__ == "__main__": unittest.main()
