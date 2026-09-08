"""SE-393 v2 contracts use only local fixtures; no CLI/provider is exercised."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/dual-cli"))
from contracts import AdapterRegistry, capability_observation, execution_context, execution_request, execution_result, receipt, verify_observation
from protocol import ProtocolError
from autonomy import AutonomyPolicy, write_receipt

CONTEXT = {"schema":2,"run_id":"run","session_id":"session","repo_id":"repo","frontend_id":"fixture-cli","adapter_version":"1","policy_revision":"p","effective_config_hash":"h","provider_id":None,"model_id":None,"model_revision":None,"inference_mode":"cli_managed","domain_ids":["core-local"],"authority_ceiling":"L2"}
REQUEST = {"request_id":"request","capability_id":"edit","context_ref":"context","scope_ref":"scope","input_ref":"private-ref","required_capabilities":[],"deadline_ms":1,"external_effect_intent":False}
RESULT = {"request_id":"request","state":"succeeded","reason":"ok","artifacts":[],"usage":None,"external_effect_observed":False}

class FixtureAdapter:
    def __init__(self, name): self.name = name
    def describe(self): return {"id":self.name,"version":"1","capability_ids":["edit"]}
    def preflight(self, context): return {"ok": True}
    def execute(self, request): return None
    def cancel(self, request_id): return None
    def observe(self, request_id): return None

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

    def test_observation_rejects_non_scalar_status_with_stable_error(self):
        value={"capability_id":"edit","status":["verified"],"mechanism":"native","observed_at":"2026-09-07T00:00:00Z","environment_hash":"env","subject_version":"1","evidence_ref":"private-evidence"}
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            capability_observation(value)

    def test_all_enum_fields_reject_non_scalars_with_stable_error(self):
        observation={"capability_id":"edit","status":"verified","mechanism":["native"],"observed_at":"2026-09-07T00:00:00Z","environment_hash":"env","subject_version":"1","evidence_ref":"private-evidence"}
        result=dict(RESULT, state=["succeeded"])
        value={"schema":2,"context":CONTEXT,"request_id":"request","event_id":"event","decision_id":"decision","decision":["proceed"],"execution":RESULT,"observation_refs":[],"human_gate_count":0,"delegated_execution":True,"decision_authority":"human"}
        cases=(
            (execution_context, dict(CONTEXT, inference_mode=["cli_managed"])),
            (execution_context, dict(CONTEXT, authority_ceiling=["L2"])),
            (capability_observation, observation),
            (execution_result, result),
            (receipt, value),
        )
        for validator, malformed in cases:
            with self.subTest(validator=validator.__name__, malformed=malformed):
                with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
                    validator(malformed)

    def test_result_accepts_namespaced_usage_extensions(self):
        value=dict(RESULT, usage={"input_tokens":3,"output_tokens":2,
                                  "extensions":{"savia:cached_tokens":1}})
        self.assertEqual(execution_result(value), value)

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

    def test_v2_rejects_bool_as_integer_and_requires_zoned_timestamp(self):
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            execution_context(dict(CONTEXT, schema=2.0))
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            execution_result(dict(RESULT, external_effect_observed=1))
        observation = {"capability_id":"edit","status":"verified","mechanism":"native",
                       "observed_at":"2026-09-07","environment_hash":"env",
                       "subject_version":"1","evidence_ref":"evidence"}
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_SCHEMA"):
            capability_observation(observation)

    def test_receipt_requires_correlated_execution_and_valid_transition(self):
        value={"schema":2,"context":CONTEXT,"request_id":"request","event_id":"event",
               "decision_id":"decision","decision":"deny",
               "execution":dict(RESULT, request_id="other"),"observation_refs":[],
               "human_gate_count":1,"delegated_execution":True,"decision_authority":"human"}
        with self.assertRaisesRegex(ProtocolError, "INCONSISTENT_RECEIPT"):
            receipt(value)

    def test_adapter_without_execution_ports_is_rejected(self):
        class DescriptorOnly:
            def describe(self): return {"id":"fixture","version":"1","capability_ids":["edit"]}
        with self.assertRaisesRegex(ProtocolError, "UNSUPPORTED_ADAPTER"):
            AdapterRegistry([DescriptorOnly()])

    def test_verified_observation_requires_matching_evidence(self):
        value={"capability_id":"edit","status":"verified","mechanism":"native",
               "observed_at":"2026-09-07T00:00:00Z","environment_hash":"env",
               "subject_version":"1","evidence_ref":"run"}
        with self.assertRaisesRegex(ProtocolError, "STALE_EVIDENCE"):
            verify_observation(value, {})
        self.assertEqual(verify_observation(value, {"run":{"verified":True}}), value)

if __name__ == "__main__": unittest.main()
