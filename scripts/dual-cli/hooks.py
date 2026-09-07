"""Execute already-trusted hook rules through one bounded policy interface.

This module deliberately does not discover hook configuration or establish trust.
Callers must validate the source before passing rules to :class:`HookEngine`.
"""
from __future__ import annotations

import json
import re


class HookConfigurationError(ValueError):
    """A hook rule cannot be interpreted safely."""


def _pattern(matcher: str) -> re.Pattern[str]:
    if matcher == "*":
        matcher = ".*"
    elif re.fullmatch(r"[^()]+\([^()]*\*[^()]*\)", matcher):
        tool, command = matcher.split("(", 1)
        command = command[:-1]
        matcher = re.escape(tool) + r"\(" + re.escape(command[:-1]) + r".*\)"
    else:
        # Existing policy mixes regular expressions (`.*`, `A|B`) and simple
        # glob stars (`Bash(command*)`). Preserve regex stars and expand globs.
        matcher = re.sub(r"(?<!\.)\*", ".*", matcher)
    try:
        return re.compile(matcher, re.IGNORECASE)
    except re.error as error:
        raise HookConfigurationError("INVALID_MATCHER") from error


def _matcher_applies(matcher, payload):
    if matcher in (None, ""):
        return True
    if not isinstance(matcher, str):
        raise HookConfigurationError("INVALID_MATCHER")
    if not isinstance(payload, dict):
        raise HookConfigurationError("INVALID_PAYLOAD")
    tool = payload.get("tool_name") or payload.get("tool")
    tool_input = payload.get("tool_input", {})
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    candidates = []
    if isinstance(tool, str):
        candidates.append(tool)
        if isinstance(command, str):
            candidates.extend((f"{tool}({command})", f"{tool}:{command}", f"{tool} {command}"))
    if not candidates:
        candidates.append(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    expression = _pattern(matcher)
    return any(expression.search(candidate) is not None for candidate in candidates)


class HookEngine:
    """Evaluate trusted rules; external transports remain explicit dependencies."""

    def __init__(self, *, http_transport=None, prompt_transport=None, cwd=None,
                 max_input_bytes=1024 * 1024, max_output_bytes=1024 * 1024,
                 default_timeout=5.0, max_timeout=30.0):
        self.http_transport = http_transport
        self.prompt_transport = prompt_transport
        self.cwd = cwd
        self.max_input_bytes = max_input_bytes
        self.max_output_bytes = max_output_bytes
        self.default_timeout = default_timeout
        self.max_timeout = max_timeout

    def evaluate(self, event_name, payload, rules):
        del event_name  # Event selection belongs to the trusted caller/catalogue.
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":"),
                         allow_nan=False).encode("utf-8")
        if len(raw) > self.max_input_bytes:
            return _deny("HOOK_INPUT_TOO_LARGE")
        for rule in rules:
            try:
                if not _matcher_applies(rule.get("matcher"), payload):
                    continue
            except (AttributeError, HookConfigurationError):
                return _deny("INVALID_MATCHER")
            for handler in rule.get("hooks", ()):
                if handler.get("type") != "prompt" or self.prompt_transport is None:
                    return _deny("UNSUPPORTED_HOOK_TYPE")
                try:
                    timeout = _timeout(handler, self.default_timeout, self.max_timeout)
                    output = self.prompt_transport(handler, raw, timeout)
                except Exception:
                    return _deny("HOOK_FAILURE")
                if not isinstance(output, dict) or type(output.get("ok")) is not bool:
                    return _deny("INVALID_HOOK_OUTPUT")
                if not output["ok"]:
                    return _deny(str(output.get("reason") or "HOOK_BLOCK"))
        return _allow()


def _timeout(handler, default, maximum):
    value = handler.get("timeout", default)
    if type(value) not in (int, float) or isinstance(value, bool) or value <= 0:
        raise HookConfigurationError("INVALID_TIMEOUT")
    return min(float(value), float(maximum))


def _allow():
    return {"action": "allow", "reason": "HOOK_OK", "context": None,
            "updated_input": None}


def _deny(reason):
    return {"action": "deny", "reason": reason, "context": None,
            "updated_input": None}
