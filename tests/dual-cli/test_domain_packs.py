import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/dual-cli"))
from domain_packs import activate, compose, load
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

    def test_composition_is_restrictive_and_keeps_domains_isolated(self):
        core={"id":"core","version":"1","capability_ids":["read","edit"],
              "rule_refs":[],"context_refs":[],"test_refs":[],
              "memory_namespace":"core","dependencies":[],"compatibility_schema":2}
        alpha=dict(core, id="alpha", capability_ids=["read"],
                   memory_namespace="alpha", dependencies=["core@1"])
        beta=dict(core, id="beta", capability_ids=["edit"],
                  memory_namespace="beta", dependencies=["core@1"])
        packs={p["id"]:p for p in (core, alpha, beta)}
        alpha_policy=compose(packs,["alpha"], capability_ceiling=["read","edit","admin"])
        beta_policy=compose(packs,["beta"], capability_ceiling=["read","edit","admin"])
        self.assertEqual(alpha_policy["capability_ids"],["read"])
        self.assertEqual(beta_policy["capability_ids"],["edit"])
        self.assertEqual(alpha_policy["domain_ids"],["core","alpha"])
        self.assertEqual(beta_policy["domain_ids"],["core","beta"])
        self.assertNotIn("beta", alpha_policy["memory_namespaces"])
        self.assertNotIn("alpha", beta_policy["memory_namespaces"])

if __name__ == "__main__": unittest.main()
