#!/usr/bin/env bash
set -uo pipefail
# judge-auto-router.sh — SE-273 S1: PostToolUse hook
#
# Invokes judge-trigger-detector.sh after tool execution. Non-blocking
# by default (triggers are logged, not enforced). Only rule-violation
# judge can block.
#
# Registered in settings.json as PostToolUse hook.
# Master switch: SAVIA_JUDGE_AUTO_ROUTER=off disables entirely.

[[ "${SAVIA_JUDGE_AUTO_ROUTER:-on}" == "off" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
SCRIPT="$ROOT/scripts/judge-trigger-detector.sh"
# Claude Code sends the hook payload on stdin; $1 kept for legacy callers.
INPUT="${1:-}"
if [[ -z "$INPUT" && ! -t 0 ]]; then
  INPUT=$(timeout 3 cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

# Extract tool name and tool output (tool_response; legacy key: output)
read -r TOOL OUTPUT_FILE < <(HOOK_INPUT="$INPUT" python3 - <<'PY' 2>/dev/null
import json, os, sys, tempfile
try:
    d = json.loads(os.environ["HOOK_INPUT"])
except ValueError:
    sys.exit(0)
out = d.get("tool_response", d.get("output", ""))
if not isinstance(out, str):
    out = json.dumps(out, ensure_ascii=False)
fd, path = tempfile.mkstemp()
with os.fdopen(fd, "w") as fh:
    fh.write(out)
print(d.get("tool_name") or os.environ.get("SAVIA_LAST_TOOL", "unknown"), path)
PY
)
[[ -z "${OUTPUT_FILE:-}" || ! -f "$OUTPUT_FILE" ]] && exit 0
trap 'rm -f "$OUTPUT_FILE"' EXIT

# Skip if no content to scan
[[ -s "$OUTPUT_FILE" ]] || exit 0

# Run detection
bash "$SCRIPT" "$TOOL" "$OUTPUT_FILE" 2>&1
DETECTOR_EXIT=$?

# If rule-violation was detected (blocking), the detector exits with
# non-zero. Forward the block signal.
if [[ $DETECTOR_EXIT -gt 0 ]]; then
  # Check if any blocking trigger fired
  if grep -q '"blocking":true' "$ROOT/output/judge-triggers.jsonl" 2>/dev/null; then
    echo "[JUDGE-AUTO-ROUTER] blocking trigger fired — forwarding signal" >&2
  fi
fi

exit 0  # Never block the tool itself; blocking is advisory via the trigger log
