"""Every Codex hook event -> the shared gates -> the output that event accepts (SE-392 S3).

Codex names its events like Claude Code, so each one runs the same-named handlers of
`.claude/settings.json`. What a decision may do follows what savia-gates does with
the same event in OpenCode, so both CLIs act alike:
- PreToolUse and UserPromptSubmit: a block stops the call (exit 2, reason on stderr).
- PermissionRequest: only `deny`; never `allow`, a gate is not a human approval.
- Lifecycle and PostToolUse: advisory. A failing handler is reported as a warning;
  it never forces a continuation (Stop) nor halts a compaction, as OpenCode never does.
Context goes to a cloud model, so only context declared N1 (`saviaLevel`) is shipped,
the rule savia-gates applies to a provider not declared local. Codex payloads do not
carry the provider, hence no local lane here. An unknown event fails closed (exit 2).
"""
import json

import gates

SHIPPABLE_LEVEL = "N1"
BLOCKING = {"PreToolUse", "UserPromptSubmit"}
TOOL_EVENTS = {"PreToolUse", "PermissionRequest", "PostToolUse"}
CONTEXT = {"PreToolUse", "UserPromptSubmit", "SessionStart", "SubagentStart"}
# Events whose output accepts `systemMessage` (Codex hooks reference).
SYSTEM_MESSAGE = {"SessionStart", "SubagentStart", "PostToolUse", "PreCompact", "PostCompact",
                  "Stop", "SubagentStop", "Interrupt"}
# Exit 0 with plain or empty stdout is invalid here: always answer with a JSON object.
JSON_REQUIRED = {"Stop", "SubagentStop"}
# Codex events without a Claude Code counterpart in settings.json: nothing to run.
UNMAPPED = {"Interrupt"}
EVENTS = BLOCKING | TOOL_EVENTS | SYSTEM_MESSAGE | {"SessionEnd"}


def _block(reason):
    return 2, "", f"SAVIA_GATE_BLOCK {reason}\n"


def shippable(decision):
    """Context texts a cloud model may receive: only those a hook declared N1."""
    return [c["text"] for c in decision.get("contexts") or [] if c.get("level") == SHIPPABLE_LEVEL]


def respond(event, decision):
    """(exit code, stdout, stderr) for one Codex event, given the shared decision."""
    denied = decision["action"] != "allow"
    if event in ("PreToolUse", "PermissionRequest") and decision.get("updated_input") is not None:
        # Codex input rewriting is unverified: a handler that sanitized the call must not let the original run.
        denied, decision = True, gates._deny("UPDATED_INPUT_UNSUPPORTED")
    if denied and event in BLOCKING:
        return _block(decision["reason"])
    out = {}
    if denied and event == "PermissionRequest":
        out["hookSpecificOutput"] = {"hookEventName": event, "decision": {
            "behavior": "deny", "message": f"SAVIA_GATE_BLOCK {decision['reason']}"}}
    elif denied and event in SYSTEM_MESSAGE:
        out["systemMessage"] = f"Savia hook {event}: {decision['reason']}"[:500]
    context = shippable(decision) if not denied and event in CONTEXT else []
    if context:
        out["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": "\n".join(context)}
    if out or event in JSON_REQUIRED:
        return 0, json.dumps(out) + "\n", ""
    return 0, "", ""


def handle(payload, *, settings_path, root):
    if not isinstance(payload, dict):
        return _block("INVALID_EVENT")
    # Codex always names the event; an unnamed payload is treated as the strictest one.
    event = payload.get("hook_event_name", "PreToolUse")
    if event not in EVENTS:
        return _block("UNSUPPORTED_EVENT")
    if event in UNMAPPED:
        return 0, "", ""
    if event == "PreToolUse":
        decision = gates.evaluate_codex_pretool(payload, settings_path=settings_path, root=root)
    elif event in TOOL_EVENTS:
        decision = gates.evaluate_codex_tool(event, payload, settings_path=settings_path,
                                             root=root, spawn_async=True)
    else:
        decision = gates.evaluate(event, payload, settings_path=settings_path, root=root,
                                  spawn_async=True)
    return respond(event, decision)
