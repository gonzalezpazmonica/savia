"""SE-393 schema v2 contracts for portable execution evidence.

These are validation-only value objects.  They intentionally do not discover
or execute adapters: a name on disk is never evidence or authority.
"""
from datetime import datetime, timezone

from protocol import ProtocolError, identifier

_LEVELS = {"L0", "L1", "L2"}
_OBSERVATION = {"verified", "unsupported", "unknown", "failed"}
_MODES = {"cli_managed", "direct"}
_STATES = {"succeeded", "failed", "cancelled", "blocked", "unknown"}
_DECISIONS = {"proceed", "deny", "needs_human"}


def _object(value, fields):
    if not isinstance(value, dict) or set(value) != fields:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


def _nullable_identifier(value):
    if value is not None:
        identifier(value)
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
    _object(value, fields)
    if value["schema"] != 2 or value["inference_mode"] not in _MODES or value["authority_ceiling"] not in _LEVELS:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    for key in fields - {"schema", "provider_id", "model_id", "model_revision", "domain_ids", "inference_mode", "authority_ceiling"}:
        identifier(value[key])
    for key in ("provider_id", "model_id", "model_revision"):
        _nullable_identifier(value[key])
    _strings(value["domain_ids"])
    return value


def capability_observation(value):
    fields = {"capability_id", "status", "mechanism", "observed_at", "environment_hash", "subject_version", "evidence_ref"}
    _object(value, fields)
    if value["status"] not in _OBSERVATION or value["mechanism"] not in {"native", "mediated"}:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    for key in fields - {"status", "mechanism", "observed_at"}:
        identifier(value[key])
    try:
        datetime.fromisoformat(value["observed_at"].replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        raise ProtocolError("UNSUPPORTED_SCHEMA") from None
    return value


def execution_request(value):
    fields = {"request_id", "capability_id", "context_ref", "scope_ref", "input_ref", "required_capabilities", "deadline_ms", "external_effect_intent"}
    _object(value, fields)
    for key in fields - {"required_capabilities", "deadline_ms", "external_effect_intent"}:
        identifier(value[key])
    if type(value["deadline_ms"]) is not int or value["deadline_ms"] <= 0 or type(value["external_effect_intent"]) is not bool:
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _strings(value["required_capabilities"])
    return value


def execution_result(value):
    fields = {"request_id", "state", "reason", "artifacts", "usage", "external_effect_observed"}
    _object(value, fields)
    identifier(value["request_id"])
    identifier(value["reason"])
    if value["state"] not in _STATES or value["external_effect_observed"] not in (True, False, None):
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    _strings(value["artifacts"])
    if value["usage"] is not None:
        _object(value["usage"], {"input_tokens", "output_tokens"})
        if any(type(value["usage"][k]) is not int or value["usage"][k] < 0 for k in value["usage"]):
            raise ProtocolError("UNSUPPORTED_SCHEMA")
    return value


def receipt(value):
    fields = {"schema", "context", "request_id", "event_id", "decision_id", "decision", "execution", "observation_refs", "human_gate_count", "delegated_execution", "decision_authority"}
    _object(value, fields)
    if value["schema"] != 2 or value["decision"] not in _DECISIONS or value["decision_authority"] != "human":
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    for key in ("request_id", "event_id", "decision_id"):
        identifier(value[key])
    execution_context(value["context"])
    if value["execution"] is not None:
        execution_result(value["execution"])
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
        descriptor = adapter.describe()
        _object(descriptor, {"id", "version", "capability_ids"})
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
