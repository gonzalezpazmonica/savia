"""Interpret synchronous critical-hook results, without granting human trust."""
from protocol import ProtocolError, decode_json


# Claude Code and Codex read plain (non-JSON) stdout of these events as context.
PLAIN_CONTEXT_EVENTS = ("SessionStart", "UserPromptSubmit", "SubagentStart")
# Authority events must answer with JSON or nothing: anything else is invalid output.
AUTHORITY_EVENTS = ("PreToolUse", "PermissionRequest")


def plain_output_mode(event):
    """How exit-0 stdout that is not JSON is read for `event`: invalid, context or ignore."""
    if event in AUTHORITY_EVENTS:
        return "invalid"
    return "context" if event in PLAIN_CONTEXT_EVENTS else "ignore"


def hook_decision(exit_code, stdout, *, timed_out=False, plain="invalid"):
    result = dict(action="deny", reason="HOOK_FAILURE", context=None, updated_input=None, level=None)
    if timed_out or type(exit_code) is not int or exit_code != 0:
        return result
    text = stdout.strip()
    if plain != "invalid" and text and not text.startswith("{"):
        # Plain text (also "[TAG] ..."), not broken JSON: what starts like an object still has to parse.
        result.update(action="allow", reason="HOOK_OK", context=text if plain == "context" else None)
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
        # A context level is only what the hook declares (savia-gates reads the same key).
        level = specific.get("saviaLevel")
        result.update(action="allow", reason="HOOK_OK", context=context, updated_input=mutation,
                      level=level if isinstance(level, str) else None)
    except (ProtocolError, UnicodeError, AttributeError):
        result["reason"] = "INVALID_HOOK_OUTPUT"
    return result
