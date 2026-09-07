"""SE-393 v2 contracts use only local fixtures; no CLI/provider is exercised."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/dual-cli"))
from contracts import AdapterRegistry, capability_observation, execution_context, execution_request, execution_result, receipt
from protocol import ProtocolError
from autonomy import AutonomyPolicy, write_receipt

CONTEXT = {"schema":2,"run_id":"run","session_id":"session","repo_id":"repo","frontend_id":"fixture-cli","adapter_version":"1","policy_revision":"p","effective_config_hash":"h","provider_id":None,"model_id":None,"model_revision":None,"inference_mode":"cli_managed","domain_ids":["core-local"],"authority_ceiling":"L2"}
REQUEST = {"request_id":"request","capability_id":"edit","context_ref":"context","scope_ref":"scope","input_ref":"private-ref","required_capabilities":[],"deadline_ms":1,"external_effect_intent":False}
RESULT = {"request_id":"request","state":"succeeded","reason":"ok","artifacts":[],"usage":None,"external_effect_observed":False}

class FixtureAdapter:
    def __init__(self, name): self.name = name
    def describe(self): return {"id":self.name,"version":"1","capability_ids":["edit"]}

class ContractsTests(unittest.TestCase):
    def test_context_request_result_and_receipt_are_explicit(self):
        self.assertEqual(execution_context(CONTEXT), CONTEXT)
        self.assertEqual(execution_request(REQUEST), REQUEST)
        self.assertEqual(execution_result(RESULT), RESULT)
        value={"schema":2,"context":CONTEXT,"request_id":"request","event_id":"event","decision_id":"decision","decision":"proceed","execution":RESULT,"observation_refs":["evidence"],"human_gate_count":0,"delegated_execution":True,"decision_authority":"human"}
        self.assertEqual(receipt(value), value)

    def test_unknown_or_malformed_contract_fails_closed(self):
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            execution_context(dict(CONTEXT, authority_ceiling="L3"))
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            execution_request(dict(REQUEST, deadline_ms=0))
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            receipt({"schema":2})

    def test_adapter_registry_is_open_but_not_discovered_or_trusted(self):
        registry=AdapterRegistry([FixtureAdapter("one"), FixtureAdapter("two"), FixtureAdapter("third")])
        self.assertEqual([x["id"] for x in registry.describe()], ["one","third","two"])
        with self.assertRaisesRegex(ProtocolError, "UNKNOWN_ADAPTER"):
            registry.get("unregistered")

    def test_observation_requires_its_subject_and_evidence(self):
        value={"capability_id":"edit","status":"verified","mechanism":"native","observed_at":"2026-09-07T00:00:00Z","environment_hash":"env","subject_version":"1","evidence_ref":"private-evidence"}
        self.assertEqual(capability_observation(value), value)
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            capability_observation(dict(value, status="pass"))

    def test_v2_writer_never_marks_a_failed_execution_as_pass(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            decision=AutonomyPolicy([], []).decide("edit")
            value=write_receipt(Path(tmp) / "receipt.json", decision, "scope", "policy", ["edit"],
                frontend="fixture-cli", request_id="request", event_id="event", decision_id="decision",
                execution={"request_id":"request","state":"failed","reason":"test-failure","artifacts":[],"usage":None,"external_effect_observed":False})
        self.assertEqual(value["schema"], 2)
        self.assertEqual(value["decision"], "proceed")
        self.assertEqual(value["execution"]["state"], "failed")
        receipt(value)

if __name__ == "__main__": unittest.main()
