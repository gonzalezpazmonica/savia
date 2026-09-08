"""SE-393 schema v2 contracts for portable execution evidence.

These are validation-only value objects.  They intentionally do not discover
or execute adapters: a name on disk is never evidence or authority.
"""
from datetime import datetime
from collections.abc import Mapping

from protocol import ProtocolError, identifier

_LEVELS = {"L0", "L1", "L2"}
_OBSERVATION = {"verified", "unsupported", "unknown", "failed"}
_MODES = {"cli_managed", "direct"}
_STATES = {"succeeded", "failed", "cancelled", "blocked", "unknown"}
_DECISIONS = {"proceed", "deny", "needs_human"}


def _object(value, fields, *, optional=()):
    if not isinstance(value, dict) or not set(fields).issubset(value) or set(value) - set(fields) - set(optional):
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    if "extensions" in value:
        extensions = value["extensions"]
        if not isinstance(extensions, dict):
            raise ProtocolError("UNSUPPORTED_SCHEMA")
        for key in extensions:
            if not isinstance(key, str) or ":" not in key or key.startswith(":") or key.endswith(":"):
                raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


def _nullable_identifier(value):
    if value is not None:
        identifier(value)
    return value


def _enum(value, allowed):
    if not isinstance(value, str) or value not in allowed:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


def _strings(value):
    if not isinstance(value, list):
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    for item in value:
        identifier(item)
    return value


def execution_context(value):
    fields = {"schema", "run_id", "session_id", "repo_id", "frontend_id",
              "adapter_version", "policy_revision", "effective_config_hash",
              "provider_id", "model_id", "model_revision", "inference_mode",
              "domain_ids", "authority_ceiling"}
    _object(value, fields, optional={"extensions"})
    if type(value["schema"]) is not int or value["schema"] != 2:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _enum(value["inference_mode"], _MODES)
    _enum(value["authority_ceiling"], _LEVELS)
    for key in fields - {"schema", "provider_id", "model_id", "model_revision", "domain_ids", "inference_mode", "authority_ceiling"}:
        identifier(value[key])
    for key in ("provider_id", "model_id", "model_revision"):
        _nullable_identifier(value[key])
    _strings(value["domain_ids"])
    return value


def capability_observation(value):
    fields = {"capability_id", "status", "mechanism", "observed_at", "environment_hash", "subject_version", "evidence_ref"}
    _object(value, fields, optional={"extensions"})
    _enum(value["status"], _OBSERVATION)
    _enum(value["mechanism"], {"native", "mediated"})
    for key in fields - {"status", "mechanism", "observed_at"}:
        identifier(value[key])
    try:
        parsed = datetime.fromisoformat(value["observed_at"].replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError
    except (AttributeError, ValueError):
        raise ProtocolError("UNSUPPORTED_SCHEMA") from None
    return value


def execution_request(value):
    fields = {"request_id", "capability_id", "context_ref", "scope_ref", "input_ref", "required_capabilities", "deadline_ms", "external_effect_intent"}
    _object(value, fields, optional={"extensions"})
    for key in fields - {"required_capabilities", "deadline_ms", "external_effect_intent"}:
        identifier(value[key])
    if type(value["deadline_ms"]) is not int or value["deadline_ms"] <= 0 or type(value["external_effect_intent"]) is not bool:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _strings(value["required_capabilities"])
    return value


def execution_result(value):
    fields = {"request_id", "state", "reason", "artifacts", "usage", "external_effect_observed"}
    _object(value, fields, optional={"extensions"})
    identifier(value["request_id"])
    identifier(value["reason"])
    _enum(value["state"], _STATES)
    if value["external_effect_observed"] is not None and type(value["external_effect_observed"]) is not bool:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _strings(value["artifacts"])
    if value["usage"] is not None:
        _object(value["usage"], {"input_tokens", "output_tokens"}, optional={"extensions"})
        if any(type(value["usage"][k]) is not int or value["usage"][k] < 0
               for k in ("input_tokens", "output_tokens")):
            raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


def receipt(value):
    fields = {"schema", "context", "request_id", "event_id", "decision_id", "decision", "execution", "observation_refs", "human_gate_count", "delegated_execution", "decision_authority"}
    _object(value, fields, optional={"extensions"})
    if type(value["schema"]) is not int or value["schema"] != 2:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _enum(value["decision"], _DECISIONS)
    _enum(value["decision_authority"], {"human"})
    for key in ("request_id", "event_id", "decision_id"):
        identifier(value[key])
    execution_context(value["context"])
    if value["execution"] is not None:
        execution_result(value["execution"])
        if value["execution"]["request_id"] != value["request_id"]:
            raise ProtocolError("INCONSISTENT_RECEIPT")
        if value["decision"] == "deny" and value["execution"]["state"] == "succeeded":
            raise ProtocolError("INCONSISTENT_RECEIPT")
    _strings(value["observation_refs"])
    if type(value["human_gate_count"]) is not int or value["human_gate_count"] < 0 or type(value["delegated_execution"]) is not bool:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


class AdapterRegistry:
    """Explicit, inert adapter registry; all lookups fail closed."""
    def __init__(self, adapters=()):
        self._adapters = {}
        for adapter in adapters:
            self.register(adapter)

    def register(self, adapter):
        required_ports = ("describe", "preflight", "execute", "cancel", "observe")
        if any(not callable(getattr(adapter, port, None)) for port in required_ports):
            raise ProtocolError("UNSUPPORTED_ADAPTER")
        descriptor = adapter.describe()
        _object(descriptor, {"id", "version", "capability_ids"}, optional={"extensions"})
        identifier(descriptor["id"]); identifier(descriptor["version"]); _strings(descriptor["capability_ids"])
        if descriptor["id"] in self._adapters:
            raise ProtocolError("CONFIG_CONFLICT")
        self._adapters[descriptor["id"]] = adapter

    def get(self, adapter_id):
        identifier(adapter_id)
        if adapter_id not in self._adapters:
            raise ProtocolError("UNKNOWN_ADAPTER")
        return self._adapters[adapter_id]

    def describe(self):
        return [self._adapters[k].describe() for k in sorted(self._adapters)]


def verify_observation(value, evidence, *, expected_subject_version=None,
                       expected_environment_hash=None):
    """Verify evidence provenance separately from validating its shape."""
    capability_observation(value)
    if value["status"] != "verified" or not isinstance(evidence, Mapping):
        raise ProtocolError("STALE_EVIDENCE")
    if expected_subject_version is not None and value["subject_version"] != expected_subject_version:
        raise ProtocolError("STALE_EVIDENCE")
    if expected_environment_hash is not None and value["environment_hash"] != expected_environment_hash:
        raise ProtocolError("STALE_EVIDENCE")
    reference = evidence.get(value["evidence_ref"])
    if not isinstance(reference, Mapping) or reference.get("verified") is not True:
        raise ProtocolError("STALE_EVIDENCE")
    return value
