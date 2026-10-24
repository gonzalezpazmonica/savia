#!/usr/bin/env python3
"""Codex hook adapter: stdin hook JSON -> shared gates -> the output of that Codex event.

The event comes from `hook_event_name` (lib in codex_events.py). Block = exit 2 with
the reason on stderr, the path Codex PreToolUse and UserPromptSubmit support;
`ask` and `continue:false` are never emitted because Codex may fail open on them.
Every failure of this adapter itself, including import errors, ends in exit 2.
The project root comes from this file's location, never from the environment.
Trust in this hook is a native Codex decision.
"""
from pathlib import Path
import os
import sys


def main():
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    import gates
    import codex_events
    root = here.parents[1]
    try:
        raw = sys.stdin.buffer.read(gates.MAX_OUTPUT + 1)
        if len(raw) > gates.MAX_OUTPUT:
            raise ValueError
        payload = gates.decode_json(raw)
        code, out, err = codex_events.handle(payload, settings_path=root / ".claude/settings.json", root=root)
    except Exception:
        code, out, err = 2, "", "SAVIA_GATE_BLOCK INVALID_EVENT\n"
    sys.stdout.write(out)
    sys.stderr.write(err)
    return code


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
