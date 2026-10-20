#!/usr/bin/env python3
"""Codex PreToolUse adapter: stdin hook JSON -> shared gates -> Codex output.

Block = exit 2 with the reason on stderr (supported by Codex PreToolUse);
`ask` and `continue:false` are never emitted because Codex may fail open on them.
Any adapter failure also blocks. Trust in this hook is a native Codex decision.
"""
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gates


def main():
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
    try:
        raw = sys.stdin.buffer.read(gates.MAX_OUTPUT + 1)
        if len(raw) > gates.MAX_OUTPUT:
            raise ValueError
        payload = gates.decode_json(raw)
        decision = gates.evaluate_codex_pretool(
            payload, settings_path=root / ".claude/settings.json", root=root)
    except Exception:
        decision = gates._deny("INVALID_EVENT")
    if decision["action"] != "allow":
        print(f"SAVIA_GATE_BLOCK {decision['reason']}", file=sys.stderr)
        return 2
    out = {}
    if decision["context"]:
        out.setdefault("hookSpecificOutput", {})["additionalContext"] = decision["context"]
    if decision["updated_input"] is not None:
        out.setdefault("hookSpecificOutput", {})["updatedInput"] = decision["updated_input"]
    if out:
        out["hookSpecificOutput"]["hookEventName"] = "PreToolUse"
        print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
