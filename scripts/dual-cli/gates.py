"""Frontend-neutral synchronous gate evaluation shared by the CLI adapters.

Reads the same `.claude/settings.json` that Claude Code and savia-gates use,
runs matching command handlers in their own process group and fails closed on
timeout, crash, invalid output or any handler type it cannot execute.
It does not establish trust and never turns a decision into human approval.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from hooks import HookConfigurationError, _matcher_applies
from policy import hook_decision, prompt_decision
from protocol import ProtocolError, decode_json

MAX_OUTPUT = 1024 * 1024
DEFAULT_TIMEOUT = 5.0
MAX_TIMEOUT = 30.0
AUTHORITY_EVENTS = ("PreToolUse", "PermissionRequest")
ENV_ARG_LIMIT = 64 * 1024  # a single env string must stay far below the kernel limit
# Switches that turn security hooks off must not be steerable from the gated session.
STRIPPED_ENV = ("SAVIA_PAT_BLOCK", "SAVIA_SHIELD_ENABLED", "SAVIA_HOOK_PROFILE")
# Never inherited by a prompt evaluator (mirrored by PROMPT_ONLY_ENV in savia-gates shell-bridge.ts).
PROMPT_ONLY_ENV = ("CLAUDE_JSON_INPUT", "SAVIA_PROMPT_HOOK_MODEL")
# The agent being gated must not rewrite the gate: deny by default (relative to root).
# Same list as PROTECTED_GATE_PATHS in savia-gates lib/hook-vocabulary.ts (parity test in test_edit_replay.py).
PROTECTED_PATHS = (".claude/settings.json", ".claude/settings.local.json", ".claude/hooks",
                   ".opencode/hooks", ".opencode/plugins", "scripts/dual-cli",
                   "scripts/opencode-plugin", ".codex", "opencode.json", ".opencode/package.json")


def _deny(reason, handler=None):
    return {"action": "deny", "reason": reason, "context": None,
            "updated_input": None, "handler": handler}


def load_rules(settings_path, event):
    """Return (rules, error). A missing or malformed file is an error, not 'no hooks'."""
    try:
        data = decode_json(Path(settings_path).read_bytes())
        entries = data.get("hooks", {}).get(event, [])
        if not isinstance(entries, list):
            raise ProtocolError("INVALID_EVENT")
    except (OSError, ProtocolError, AttributeError):
        return [], "INVALID_HOOK_CONFIGURATION"
    return entries, None


def _timeout(handler):
    value = handler.get("timeout", DEFAULT_TIMEOUT)
    if type(value) not in (int, float) or isinstance(value, bool) or value <= 0:
        raise HookConfigurationError("INVALID_TIMEOUT")
    seconds = value / 1000 if value >= 1000 else value  # settings mix s and ms
    return min(float(seconds), MAX_TIMEOUT)


def _run_command(command, payload, root, timeout, extra_env=None):
    env = {k: v for k, v in os.environ.items() if k not in STRIPPED_ENV}
    env["CLAUDE_PROJECT_DIR"] = str(root)
    if extra_env is not None:  # a prompt evaluator: no stale model or event from the parent
        for key in PROMPT_ONLY_ENV:
            env.pop(key, None)
        env.update(extra_env)
    elif len(payload) <= ENV_ARG_LIMIT:  # larger events reach handlers by stdin only
        env["CLAUDE_JSON_INPUT"] = payload
    proc = subprocess.Popen(["bash", "-c", command], cwd=str(root), env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = proc.communicate(payload.encode(), timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.communicate()
        return None, "", "", True
    except BrokenPipeError:
        # Handler exited without reading stdin: its exit code still decides.
        out, err = proc.stdout.read(), proc.stderr.read()
        proc.wait()
    finally:
        try:  # reap stragglers left behind by a handler that exited early
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    return proc.returncode, out[:MAX_OUTPUT].decode("utf-8", "replace"), \
        err[:MAX_OUTPUT].decode("utf-8", "replace"), False


def render_prompt(prompt, raw):
    """Claude Code semantics: `$ARGUMENTS` becomes the hook input JSON; without it, the JSON is appended."""
    return prompt.replace("$ARGUMENTS", raw) if "$ARGUMENTS" in prompt else f"{prompt}\n\n{raw}"


def _run_prompt(handler, raw, root):
    """Run a `prompt` handler through the evaluator the operator declared at launch.

    SAVIA_PROMPT_HOOK_CMD is a shell command that reads the rendered prompt on stdin and prints the
    model verdict. Which model answers is local configuration, never this repo. No evaluator, crash,
    timeout or a verdict that is not exactly {"ok": bool} denies: the gate is critical (SE-392 AC6).
    """
    evaluator = os.environ.get("SAVIA_PROMPT_HOOK_CMD", "").strip()
    if not evaluator:
        return _deny("PROMPT_HOOK_UNAVAILABLE")
    model = handler.get("model")
    extra = {"SAVIA_PROMPT_HOOK_MODEL": model} if isinstance(model, str) else {}
    code, out, _err, timed_out = _run_command(
        evaluator, render_prompt(handler["prompt"], raw), root, _timeout(handler), extra)
    if timed_out:
        return _deny("HOOK_TIMEOUT")
    return prompt_decision(code, out)


def evaluate(event, payload, *, settings_path, root):
    """Evaluate every matching handler in order; the first block wins."""
    rules, error = load_rules(settings_path, event)
    if error:
        return _deny(error)
    try:
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError):
        return _deny("INVALID_EVENT")
    if len(raw.encode()) > MAX_OUTPUT:
        return _deny("HOOK_INPUT_TOO_LARGE")
    decision = {"action": "allow", "reason": "HOOK_OK", "context": None,
                "updated_input": None, "handler": None}
    contexts = []
    for rule in rules:
        try:
            if not _matcher_applies(rule.get("matcher"), payload):
                continue
            handlers = rule.get("hooks", [])
            for handler in handlers:
                kind = handler.get("type")
                if kind == "prompt" and isinstance(handler.get("prompt"), str):
                    if handler.get("async") is True and event not in AUTHORITY_EVENTS:
                        continue
                    result = _run_prompt(handler, raw, root)
                    if result["action"] != "allow":
                        result["handler"] = "prompt"
                        return result
                    continue
                if kind != "command" or not isinstance(handler.get("command"), str):
                    if handler.get("async") is True and event not in AUTHORITY_EVENTS:
                        continue  # telemetry by contract
                    return _deny("UNSUPPORTED_CRITICAL_HOOK", kind)
                if handler.get("async") is True and event not in AUTHORITY_EVENTS:
                    continue
                code, out, err, timed_out = _run_command(
                    handler["command"], raw, root, _timeout(handler))
                name = handler["command"][-80:]
                if timed_out:
                    return _deny("HOOK_TIMEOUT", name)
                result = hook_decision(code, out)
                if result["action"] != "allow":
                    if code is not None and code != 0 and err.strip():
                        result["reason"] = err.strip().splitlines()[0][:500]
                    result["handler"] = name
                    return result
                if result["context"]:
                    contexts.append(result["context"])
                if result["updated_input"] is not None:
                    decision["updated_input"] = result["updated_input"]
        except (HookConfigurationError, AttributeError, OSError):
            return _deny("INVALID_HOOK_CONFIGURATION")
    if contexts:
        decision["context"] = "\n".join(contexts)
    return decision


_HEADERS = (("*** Add File: ", "add"), ("*** Update File: ", "update"), ("*** Delete File: ", "delete"))
_OTHER_HEADERS = ("*** Begin Patch", "*** End Patch", "*** End of File")


def apply_patch_operations(patch, cwd):
    """Split an apply_patch body into per-file operations.

    Returns (tool, path, op, content, old) tuples. Codex trims header lines, so
    headers are matched on the stripped line; an unknown `*** ` line fails closed.
    """
    if not isinstance(patch, str) or "*** Begin Patch" not in patch:
        raise ProtocolError("INVALID_EVENT")
    ops, current = [], None
    for line in patch.splitlines():
        head = line.strip()
        if head[:1] in ("+", "-") or not head.startswith("***"):
            if current is not None:
                if line[:1] == "+":
                    current["new"].append(line[1:])
                elif line[:1] == "-":
                    current["old"].append(line[1:])
            continue
        for prefix, op in _HEADERS:
            if head.startswith(prefix):
                current = {"op": op, "path": head[len(prefix):].strip(), "new": [], "old": []}
                ops.append(current)
                break
        else:
            if head.startswith("*** Move to: ") and current and current["op"] == "update":
                current["move_to"] = head[len("*** Move to: "):].strip()
            elif head not in _OTHER_HEADERS and not head.startswith("*** Move to: "):
                raise ProtocolError("INVALID_EVENT")
    if not ops or any(not o["path"] for o in ops):
        raise ProtocolError("INVALID_EVENT")
    result = []
    for o in ops:
        path = os.path.normpath(os.path.join(cwd, o["path"]))
        tool = "Edit" if o["op"] == "update" else "Write"
        result.append((tool, path, o["op"], "\n".join(o["new"]), "\n".join(o["old"])))
        if "move_to" in o:
            result.append(("Write", os.path.normpath(os.path.join(cwd, o["move_to"])), "move",
                           "\n".join(o["new"]), ""))
    return result


def is_protected(path, root):
    """True when path (lexically and through symlinks) is gate configuration or code."""
    for candidate in (os.path.normpath(path), os.path.realpath(path)):
        for rel in PROTECTED_PATHS:
            for base in (os.path.normpath(os.path.join(root, rel)),
                         os.path.realpath(os.path.join(root, rel))):
                if candidate == base or candidate.startswith(base + os.sep):
                    return True
    return False


def normalize_codex_pretool(payload):
    """Codex PreToolUse payload -> list of Claude-shaped payloads, one per effect."""
    if not isinstance(payload, dict):
        raise ProtocolError("INVALID_EVENT")
    tool, tool_input = payload.get("tool_name"), payload.get("tool_input")
    if not isinstance(tool, str) or not isinstance(tool_input, dict):
        raise ProtocolError("INVALID_EVENT")
    cwd = payload.get("cwd") or os.getcwd()
    if tool != "apply_patch":
        return [payload]
    base = {k: v for k, v in payload.items() if k not in ("tool_name", "tool_input")}
    events = []
    for name, path, op, new, old in apply_patch_operations(tool_input.get("command"), cwd):
        data = {"file_path": path, "operation": op}
        if name == "Write":
            data["content"] = new
        else:
            data["new_string"], data["old_string"] = new, old
        events.append(dict(base, tool_name=name, tool_input=data))
    return events


def evaluate_codex_pretool(payload, *, settings_path, root):
    try:
        events = normalize_codex_pretool(payload)
    except ProtocolError:
        return _deny("INVALID_EVENT")
    if any(event is not payload and is_protected(event["tool_input"]["file_path"], root)
           for event in events):
        return _deny("PROTECTED_GATE_PATH")
    final = None
    for event in events:
        decision = evaluate("PreToolUse", event, settings_path=settings_path, root=root)
        if decision["action"] != "allow":
            return decision
        if final is None:
            final = decision
            continue
        if decision["context"]:
            final["context"] = "\n".join(filter(None, (final["context"], decision["context"])))
        if decision["updated_input"] is not None:
            final["updated_input"] = decision["updated_input"]
    return final
