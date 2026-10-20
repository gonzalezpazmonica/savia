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
from policy import hook_decision
from protocol import ProtocolError, decode_json

MAX_OUTPUT = 1024 * 1024
DEFAULT_TIMEOUT = 5.0
MAX_TIMEOUT = 30.0
AUTHORITY_EVENTS = ("PreToolUse", "PermissionRequest")


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


def _run_command(command, payload, root, timeout):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root), CLAUDE_JSON_INPUT=payload)
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


def apply_patch_operations(patch, cwd):
    """Split an apply_patch body into per-file (tool, path, op) operations."""
    if not isinstance(patch, str) or "*** Begin Patch" not in patch:
        raise ProtocolError("INVALID_EVENT")
    ops, current = [], None
    for line in patch.splitlines():
        for prefix, op in (("*** Add File: ", "add"), ("*** Update File: ", "update"),
                           ("*** Delete File: ", "delete")):
            if line.startswith(prefix):
                current = {"op": op, "path": line[len(prefix):].strip()}
                ops.append(current)
                break
        else:
            if line.startswith("*** Move to: ") and current and current["op"] == "update":
                current["move_to"] = line[len("*** Move to: "):].strip()
    if not ops or any(not o["path"] for o in ops):
        raise ProtocolError("INVALID_EVENT")
    result = []
    for o in ops:
        path = str(Path(cwd, o["path"]))
        tool = "Edit" if o["op"] == "update" else "Write"
        result.append((tool, path, o["op"]))
        if "move_to" in o:
            result.append(("Write", str(Path(cwd, o["move_to"])), "move"))
    return result


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
    for name, path, op in apply_patch_operations(tool_input.get("command"), cwd):
        events.append(dict(base, tool_name=name,
                           tool_input={"file_path": path, "operation": op}))
    return events


def evaluate_codex_pretool(payload, *, settings_path, root):
    try:
        events = normalize_codex_pretool(payload)
    except ProtocolError:
        return _deny("INVALID_EVENT")
    final = None
    for event in events:
        decision = evaluate("PreToolUse", event, settings_path=settings_path, root=root)
        if decision["action"] != "allow":
            return decision
        final = decision if final is None else final
    return final
