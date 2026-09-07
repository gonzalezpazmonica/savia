"""Interpret synchronous critical-hook results, without granting human trust."""
from protocol import ProtocolError, decode_json


def hook_decision(exit_code, stdout, *, timed_out=False):
    result = dict(action="deny", reason="HOOK_FAILURE", context=None, updated_input=None)
    if timed_out or type(exit_code) is not int or exit_code != 0:
        return result
    try:
        value = decode_json(stdout.encode("utf-8")) if stdout.strip() else {}
        if not isinstance(value, dict):
            raise ProtocolError("INVALID_EVENT")
        if "continue" in value and type(value["continue"]) is not bool:
            raise ProtocolError("INVALID_EVENT")
        specific = value.get("hookSpecificOutput", {})
        if not isinstance(specific, dict):
            raise ProtocolError("INVALID_EVENT")
        if value.get("decision") not in (None, "approve", "block"):
            raise ProtocolError("INVALID_EVENT")
        permission = specific.get("permissionDecision")
        if permission not in (None, "allow", "deny", "ask"):
            raise ProtocolError("INVALID_EVENT")
        if value.get("decision") == "block" or value.get("continue") is False or permission in ("deny", "ask"):
            result["reason"] = "HUMAN_PERMISSION_REQUIRED" if permission == "ask" else "HOOK_BLOCK"
            return result
        context = specific.get("additionalContext")
        mutation = specific.get("updatedInput")
        if context is not None and not isinstance(context, str):
            raise ProtocolError("INVALID_EVENT")
        if mutation is not None and not isinstance(mutation, dict):
            raise ProtocolError("INVALID_EVENT")
        result.update(action="allow", reason="HOOK_OK", context=context, updated_input=mutation)
    except (ProtocolError, UnicodeError, AttributeError):
        result["reason"] = "INVALID_HOOK_OUTPUT"
    return result
