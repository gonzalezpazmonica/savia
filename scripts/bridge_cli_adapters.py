#!/usr/bin/env python3
"""CLI-managed bridge adapters; provider semantics stop at this boundary."""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import shutil
from typing import Callable


class AdapterContractError(ValueError):
    """Stable fail-closed adapter error."""


@dataclass(frozen=True)
class BridgeRequest:
    message: str
    system_prompt: str | None
    bridge_session_id: str | None
    workdir: str
    authority_ceiling: str
    request_id: str
    persistent: bool = False

    def __post_init__(self):
        if (not isinstance(self.message, str) or not self.message
                or not isinstance(self.system_prompt, (str, type(None)))
                or not isinstance(self.bridge_session_id, (str, type(None)))
                or not isinstance(self.authority_ceiling, str)
                or self.authority_ceiling not in {"L0", "L1", "L2"}
                or not isinstance(self.request_id, str) or not self.request_id
                or not isinstance(self.workdir, str)
                or not Path(self.workdir).is_absolute()
                or type(self.persistent) is not bool):
            raise AdapterContractError("INVALID_REQUEST")


@dataclass(frozen=True)
class TranslationBatch:
    events: tuple[dict, ...] = ()
    native_session_ref: str | None = None


class _CliAdapter:
    adapter_id = ""
    command = ""
    version = "1"

    def __init__(self, *, binary: str | None = None,
                 which: Callable[[str], str | None] = shutil.which):
        self.binary = binary or which(self.command)

    def describe(self):
        return {"id": self.adapter_id, "version": self.version,
                "mode": "cli_managed"}

    def preflight(self):
        return {"status": "AVAILABLE" if self.binary else "UNAVAILABLE",
                "adapter_id": self.adapter_id}

    def _require_binary(self):
        if not self.binary:
            raise AdapterContractError("UNAVAILABLE")
        return self.binary

    @staticmethod
    def _prompt(request: BridgeRequest):
        if request.system_prompt:
            return f"{request.system_prompt}\n\n{request.message}"
        return request.message


class CodexCliAdapter(_CliAdapter):
    adapter_id = "codex"
    command = "codex"

    def start_command(self, request: BridgeRequest):
        sandbox = "read-only" if request.authority_ceiling in {"L0", "L1"} else "workspace-write"
        cmd = [self._require_binary(), "exec", "--json", "--sandbox", sandbox,
               "-C", request.workdir]
        if not request.persistent:
            cmd.append("--ephemeral")
        return [*cmd, self._prompt(request)]

    def resume_command(self, request: BridgeRequest, native_session_ref: str):
        if not request.persistent:
            raise AdapterContractError("UNSUPPORTED_RESUME")
        if not native_session_ref:
            raise AdapterContractError("MISSING_NATIVE_SESSION")
        return [self._require_binary(), "exec", "resume", "--json",
                native_session_ref, self._prompt(request)]

    def translate(self, line: str):
        try:
            event = json.loads(line)
        except (TypeError, json.JSONDecodeError) as error:
            raise AdapterContractError("MALFORMED_EVENT") from error
        if not isinstance(event, dict) or not isinstance(event.get("type"), str):
            raise AdapterContractError("MALFORMED_EVENT")
        kind = event["type"]
        if kind == "thread.started" and isinstance(event.get("thread_id"), str):
            return TranslationBatch(native_session_ref=event["thread_id"])
        if kind == "turn.started":
            return TranslationBatch()
        if kind == "item.completed" and isinstance(event.get("item"), dict):
            item = event["item"]
            if item.get("type") == "agent_message" and isinstance(item.get("text"), str):
                return TranslationBatch(({"type": "text", "text": item["text"]},))
            if item.get("type") == "command_execution":
                return TranslationBatch(({"type": "tool_use", "tool": "command_execution"},))
        if kind == "turn.completed" and isinstance(event.get("usage"), dict):
            return TranslationBatch(({"type": "done", "usage": event["usage"]},))
        if kind == "error":
            return TranslationBatch(({"type": "error", "text": str(event.get("message", "error"))},))
        raise AdapterContractError("UNKNOWN_EVENT")


class OpenCodeCliAdapter(_CliAdapter):
    adapter_id = "opencode"
    command = "opencode"

    def preflight(self):
        status = "NOT_VERIFIED" if self.binary else "UNAVAILABLE"
        return {"status": status, "adapter_id": self.adapter_id}

    def start_command(self, request: BridgeRequest):
        return [self._require_binary(), "run", "--pure", "--format", "json",
                "--dir", request.workdir, self._prompt(request)]

    def resume_command(self, request: BridgeRequest, native_session_ref: str):
        if not native_session_ref:
            raise AdapterContractError("MISSING_NATIVE_SESSION")
        return [self._require_binary(), "run", "--pure", "--format", "json",
                "--dir", request.workdir, "--session", native_session_ref,
                self._prompt(request)]

    def translate(self, _line: str):
        raise AdapterContractError("NOT_VERIFIED")


def adapter_by_id(adapter_id: str, **kwargs):
    adapters = {"codex": CodexCliAdapter, "opencode": OpenCodeCliAdapter}
    if not isinstance(adapter_id, str):
        raise AdapterContractError("UNKNOWN_ADAPTER")
    try:
        return adapters[adapter_id](**kwargs)
    except KeyError as error:
        raise AdapterContractError("UNKNOWN_ADAPTER") from error
