#!/usr/bin/env python3
"""Codex PreToolUse adapter: stdin hook JSON -> shared gates -> Codex output.

Block = exit 2 with the reason on stderr (supported by Codex PreToolUse);
`ask` and `continue:false` are never emitted because Codex may fail open on them.
Only exit 2 blocks in Codex, so every failure of this adapter itself, including
import errors, ends in exit 2. The project root comes from this file's location,
never from the environment. Trust in this hook is a native Codex decision.
"""
import json
import os
from pathlib import Path
import sys


def main():
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    import gates
    root = here.parents[1]
    try:
        raw = sys.stdin.buffer.read(gates.MAX_OUTPUT + 1)
        if len(raw) > gates.MAX_OUTPUT:
            raise ValueError
        payload = gates.decode_json(raw)
        decision = gates.evaluate_codex_pretool(
            payload, settings_path=root / ".claude/settings.json", root=root)
    except Exception:
        decision = gates._deny("INVALID_EVENT")
    if decision["updated_input"] is not None:
        # Codex PreToolUse input rewriting is unverified: a handler that believes it
        # sanitized the call must not let the original run.
        decision = gates._deny("UPDATED_INPUT_UNSUPPORTED")
    if decision["action"] != "allow":
        sys.stderr.write(f"SAVIA_GATE_BLOCK {decision['reason']}\n")
        return 2
    if decision["context"]:
        sys.stdout.write(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "additionalContext": decision["context"]}}) + "\n")
    return 0


if __name__ == "__main__":
    try:
        code = main()
        sys.stdout.flush()
    except BaseException:
        try:
            sys.stderr.write("SAVIA_GATE_BLOCK ADAPTER_FAILURE\n")
        except BaseException:
            pass
        code = 2
    os._exit(code)
