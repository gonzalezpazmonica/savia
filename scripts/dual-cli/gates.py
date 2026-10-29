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
import tempfile
import time

from hooks import HookConfigurationError, _matcher_applies
from policy import AUTHORITY_EVENTS, hook_decision, plain_output_mode, prompt_decision
from protocol import ProtocolError, decode_json
from shell_targets import protected_target

MAX_OUTPUT = 1024 * 1024
DEFAULT_TIMEOUT = 5.0
MAX_TIMEOUT = 30.0
ENV_ARG_LIMIT = 64 * 1024  # a single env string must stay far below the kernel limit
# Switches that turn security hooks off must not be steerable from the gated session.
STRIPPED_ENV = ("SAVIA_PAT_BLOCK", "SAVIA_SHIELD_ENABLED", "SAVIA_HOOK_PROFILE")
# Never inherited by a prompt evaluator (mirrored by PROMPT_ONLY_ENV in savia-gates shell-bridge.ts).
PROMPT_ONLY_ENV = ("CLAUDE_JSON_INPUT", "SAVIA_PROMPT_HOOK_MODEL")
# The agent being gated must not rewrite the gate: deny by default (relative to root).
# Same list as PROTECTED_GATE_PATHS in savia-gates lib/hook-vocabulary.ts (parity test in test_prompt_transport.py).
# OpenCode loads config from opencode.json(c) and .opencode/opencode.json(c), plugins from .opencode/plugin(s).
PROTECTED_PATHS = (".claude/settings.json", ".claude/settings.local.json", ".claude/hooks",
                   ".opencode/hooks", ".opencode/plugins", ".opencode/plugin", "scripts/dual-cli",
                   "scripts/opencode-plugin", ".codex", "opencode.json", "opencode.jsonc",
                   ".opencode/opencode.json", ".opencode/opencode.jsonc", ".opencode/package.json")


def _deny(reason, handler=None):
    return {"action": "deny", "reason": reason, "context": None, "contexts": [],
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


def _handler_env(payload, root, extra_env=None):
    env = {k: v for k, v in os.environ.items() if k not in STRIPPED_ENV}
    env["CLAUDE_PROJECT_DIR"] = str(root)
    if extra_env is not None:  # a prompt evaluator: no stale model or event from the parent
        for key in PROMPT_ONLY_ENV:
            env.pop(key, None)
        env.update(extra_env)
    elif len(payload) <= ENV_ARG_LIMIT:  # larger events reach handlers by stdin only
        env["CLAUDE_JSON_INPUT"] = payload
    return env


_DETACHED = []  # never awaited; held so the interpreter does not warn about them


def _spawn_detached(command, payload, root):
    """Fire-and-forget an `async` handler, as Claude Code and savia-gates do: never awaited.

    stdin is an unlinked temp file, so a handler that never reads cannot block the caller.
    """
    with tempfile.TemporaryFile() as stdin:
        stdin.write(payload.encode())
        stdin.seek(0)
        _DETACHED.append(subprocess.Popen(
            ["bash", "-c", command], cwd=str(root), env=_handler_env(payload, root), stdin=stdin,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True))


def _run_command(command, payload, root, timeout, extra_env=None):
    env = _handler_env(payload, root, extra_env)
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


def evaluate(event, payload, *, settings_path, root, spawn_async=False):
    """Evaluate every matching handler in order; the first block wins.

    `async` handlers of non-authority events are telemetry: skipped, or launched
    detached when `spawn_async` (the adapters of a live CLI), never awaited.
    `contexts` keeps each context with the level its hook declared.
    """
    rules, error = load_rules(settings_path, event)
    if error:
        return _deny(error)
    try:
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError):
        return _deny("INVALID_EVENT")
    if len(raw.encode()) > MAX_OUTPUT:
        return _deny("HOOK_INPUT_TOO_LARGE")
    decision = {"action": "allow", "reason": "HOOK_OK", "context": None, "contexts": [],
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
                    if spawn_async:
                        _spawn_detached(handler["command"], raw, root)
                    continue
                code, out, err, timed_out = _run_command(
                    handler["command"], raw, root, _timeout(handler))
                name = handler["command"][-80:]
                if timed_out:
                    return _deny("HOOK_TIMEOUT", name)
                result = hook_decision(code, out, plain=plain_output_mode(event))
                if result["action"] != "allow":
                    if code is not None and code != 0 and err.strip():
                        result["reason"] = err.strip().splitlines()[0][:500]
                    result["handler"] = name
                    result["contexts"] = []
                    return result
                if result["context"]:
                    contexts.append(result["context"])
                    decision["contexts"].append({"text": result["context"], "level": result.get("level")})
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


def shell_writes_gate(payload, root):
    """A Bash call whose text writes gate code (shell_targets.py). Text the tokenizer cannot close is
    denied too: bash may still run it, and its raw text hides what the tokenizer would have decoded
    (`.cl''aude`, `$'\\x2e'codex`, a `cd` before a relative path), so no substring of it can clear it."""
    command = payload.get("tool_input", {}).get("command")
    if payload.get("tool_name") != "Bash" or not isinstance(command, str):
        return False
    cwd = payload.get("cwd") or str(root)
    try:
        return protected_target(command, cwd, str(root), PROTECTED_PATHS) is not None
    except ProtocolError:
        return True


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
    return evaluate_codex_tool("PreToolUse", payload, settings_path=settings_path, root=root)


def evaluate_codex_tool(event, payload, *, settings_path, root, spawn_async=False):
    """A Codex tool event (Pre/PostToolUse, PermissionRequest), one evaluation per effect.

    Protected gate paths are refused only before the effect: PostToolUse cannot undo it.
    """
    try:
        events = normalize_codex_pretool(payload)
    except ProtocolError:
        return _deny("INVALID_EVENT")
    if event in AUTHORITY_EVENTS and any(
            item is not payload and is_protected(item["tool_input"]["file_path"], root) for item in events):
        return _deny("PROTECTED_GATE_PATH")
    if event in AUTHORITY_EVENTS and shell_writes_gate(payload, root):
        return _deny("PROTECTED_GATE_PATH")
    final = None
    for item in events:
        decision = evaluate(event, item, settings_path=settings_path, root=root, spawn_async=spawn_async)
        if decision["action"] != "allow":
            return decision
        if final is None:
            final = decision
            continue
        final["contexts"] += decision["contexts"]
        if decision["context"]:
            final["context"] = "\n".join(filter(None, (final["context"], decision["context"])))
        if decision["updated_input"] is not None:
            final["updated_input"] = decision["updated_input"]
    return final
