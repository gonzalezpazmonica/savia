#!/usr/bin/env bash
# speculative-skill-preload.sh — PreToolUse hook for SE-220 Slice 3: skill pre-loading.
set -uo pipefail
#
# When the tool being called is "Task" (sub-agent dispatch), this hook inspects
# the intent and adds a [SPECULATIVE_SKILL_HINT: skill-name] annotation to
# the task input so the sub-agent can pre-load the relevant skill without an
# extra resolver round-trip.
#
# In SAVIA_SPECULATIVE_EXECUTION=shadow mode: only telemetry, no mutation.
# In SAVIA_SPECULATIVE_EXECUTION=on (or =on):  adds the hint to the context.
# Default (off): no-op.
#
# Activation: SAVIA_SPECULATIVE_EXECUTION=on|shadow (default: off)
# Fail-soft:  always exits 0; never blocks the main flow.
#
# Input (stdin, JSON from OpenCode PreToolUse event):
#   {
#     "tool_name": "Task",
#     "tool_input": {"prompt": "...", ...},
#     "session_id": "abc123"
#   }
#
# Output (stdout, JSON — only when tool=Task and hint resolved):
#   {"hookSpecificOutput": {"additionalContext": "[SPECULATIVE_SKILL_HINT: ...]"}}
#
# When no hint is emitted, the hook prints nothing and exits 0.
#
# Skill hint patterns (intent keyword → skill):
#   sandbox              → sandbox-os-policy
#   triage               → spec-driven-development
#   sprint               → sprint-management
#   security|audit       → adversarial-security
#   performance          → performance-audit
#   architecture         → architecture-intelligence
#   onboard              → onboarding-dev
#   test|tdd             → tdd-vertical-slices
#   weekly.report        → weekly-report
#   executive|report     → executive-reporting
#   diagram              → diagram-generation
#   memory               → savia-memory
#   overnight            → overnight-sprint
#
# Ref: SE-220 — Speculative Tool Execution, Slice 3

set -uo pipefail

# ── Guard: requires on or shadow ─────────────────────────────────────────────
SAVIA_SPECULATIVE_EXECUTION="${SAVIA_SPECULATIVE_EXECUTION:-off}"
if [[ "$SAVIA_SPECULATIVE_EXECUTION" != "on" && "$SAVIA_SPECULATIVE_EXECUTION" != "shadow" ]]; then
  exit 0
fi

# ── Resolve paths ─────────────────────────────────────────────────────────────
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"
TELEMETRY_FILE="$ROOT_DIR/output/speculative-execution-telemetry.jsonl"
PYTHON="${PYTHON:-python3}"

# ── Read PreToolUse input (with timeout) ──────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(timeout 2 cat 2>/dev/null) || true
fi

[[ -z "$INPUT" ]] && exit 0

# ── Validate JSON ─────────────────────────────────────────────────────────────
if ! echo "$INPUT" | "$PYTHON" -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  exit 0
fi

# ── Only act on Task tool ─────────────────────────────────────────────────────
TOOL_NAME=$(echo "$INPUT" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_name', ''))
" 2>/dev/null) || exit 0

if [[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "Agent" ]]; then
  exit 0
fi

# ── Extract prompt / intent ───────────────────────────────────────────────────
INTENT=$(echo "$INPUT" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
inp = d.get('tool_input', {})
# try common keys
for key in ('prompt', 'description', 'task', 'input'):
    val = inp.get(key, '')
    if val:
        print(str(val)[:500])
        break
" 2>/dev/null) || INTENT=""

SESSION_ID=$(echo "$INPUT" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('session_id', 'unknown'))
" 2>/dev/null) || SESSION_ID="unknown"

[[ -z "$INTENT" ]] && exit 0

# ── Pattern matching: intent → skill hint ────────────────────────────────────
# Uses bash pattern matching (case + grep -iE) for speed without Python deps.
INTENT_LOWER="${INTENT,,}"  # bash lowercase

HINT=""

if echo "$INTENT_LOWER" | grep -qiE '\bsandbox\b'; then
  HINT="sandbox-os-policy"
elif echo "$INTENT_LOWER" | grep -qiE '\btriage\b'; then
  HINT="spec-driven-development"
elif echo "$INTENT_LOWER" | grep -qiE '\bovernight\b'; then
  HINT="overnight-sprint"
elif echo "$INTENT_LOWER" | grep -qiE '\bsprint\b|\bbacklog\b|\bvelocity\b|\bcapacity\b'; then
  HINT="sprint-management"
elif echo "$INTENT_LOWER" | grep -qiE '\bsecurity\b|\baudit\b|\bpentest\b|\bvulnerabil'; then
  HINT="adversarial-security"
elif echo "$INTENT_LOWER" | grep -qiE '\bperformance\b|\bhotspot\b|\blatency\b'; then
  HINT="performance-audit"
elif echo "$INTENT_LOWER" | grep -qiE '\barchitecture\b|\bdesign\b|\bdiagram\b'; then
  HINT="architecture-intelligence"
elif echo "$INTENT_LOWER" | grep -qiE '\bdiagram\b|\bflow\b|\bmermaid\b'; then
  HINT="diagram-generation"
elif echo "$INTENT_LOWER" | grep -qiE '\bonboard\b|\bincorpor\b'; then
  HINT="onboarding-dev"
elif echo "$INTENT_LOWER" | grep -qiE '\btdd\b|\btest.first\b|\bred.green\b|\bvertical.slice\b'; then
  HINT="tdd-vertical-slices"
elif echo "$INTENT_LOWER" | grep -qiE '\bweekly.report\b|\binforme.semanal\b'; then
  HINT="weekly-report"
elif echo "$INTENT_LOWER" | grep -qiE '\bexecutive\b|\binforme.ejecutivo\b|\bboard\b'; then
  HINT="executive-reporting"
elif echo "$INTENT_LOWER" | grep -qiE '\bmemoria\b|\bmemory\b|\brecall\b'; then
  HINT="savia-memory"
fi

# ── Telemetry (always, even in shadow mode) ───────────────────────────────────
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
if [[ -n "$HINT" ]]; then
  TELEM_ENTRY=$(
    "$PYTHON" -c "
import json, sys
print(json.dumps({
    'ts': sys.argv[1],
    'session_id': sys.argv[2],
    'event': 'skill_preload_hint',
    'intent_snippet': sys.argv[3][:100],
    'hint': sys.argv[4],
    'shadow': sys.argv[5] == 'shadow',
}))" "$TS" "$SESSION_ID" "$INTENT" "$HINT" "$SAVIA_SPECULATIVE_EXECUTION" 2>/dev/null
  ) || TELEM_ENTRY=""
  if [[ -n "$TELEM_ENTRY" ]]; then
    mkdir -p "$(dirname "$TELEMETRY_FILE")"
    echo "$TELEM_ENTRY" >> "$TELEMETRY_FILE" 2>/dev/null || true
  fi
fi

# ── Shadow mode: telemetry only, no output mutation ──────────────────────────
if [[ "$SAVIA_SPECULATIVE_EXECUTION" == "shadow" ]]; then
  exit 0
fi

# ── Emit hint as additional context for the sub-agent ────────────────────────
if [[ -n "$HINT" ]]; then
  "$PYTHON" -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'additionalContext': '[SPECULATIVE_SKILL_HINT: ' + sys.argv[1] + ']'
    }
}))" "$HINT" 2>/dev/null || true
fi

exit 0
