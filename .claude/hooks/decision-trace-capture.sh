#!/usr/bin/env bash
set -uo pipefail
# decision-trace-capture.sh — SPEC-188 F3 — PostToolUse hook
# Detects architectural decision patterns in agent output and writes
# a decision trace via decision-trace-writer.py.
#
# Master switch: SAVIA_DECISION_TRACE=on|off (default off)
# Always exits 0 — never blocks the tool call.
#
# Trigger: PostToolUse Task (agent output contains decision keywords)
# Keywords detected: decidí, elegí, recomiendo, descarto, decided, chose,
#                    recommend, discard, selected, rejected, I propose
#
# Ref: SPEC-188 F3 — docs/propuestas/SPEC-188-root-cause-investigation-architecture.md

# ── Master switch ─────────────────────────────────────────────────────────
SAVIA_DECISION_TRACE="${SAVIA_DECISION_TRACE:-off}"
if [[ "$SAVIA_DECISION_TRACE" != "on" ]]; then
  exit 0
fi

# ── Dependencies check ────────────────────────────────────────────────────
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WRITER="${REPO_ROOT}/scripts/decision-trace-writer.py"
OUTPUT_DIR="${DECISION_TRACE_OUTPUT_DIR:-${REPO_ROOT}/output/decision-traces}"

if [[ ! -f "$WRITER" ]]; then
  exit 0  # writer not installed, degrade silently
fi

command -v python3 >/dev/null 2>&1 || exit 0

# ── Read hook input (stdin JSON from OpenCode/Claude Code) ────────────────
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

# ── Extract relevant fields ───────────────────────────────────────────────
# Expected input schema: {"tool_name": "Task", "tool_input": {...}, "tool_response": "..."}
TOOL_NAME=""
TOOL_RESPONSE=""
AGENT_NAME=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(jq -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null || true)
  TOOL_RESPONSE=$(jq -r '.tool_response // .output // ""' <<< "$INPUT" 2>/dev/null || true)
  AGENT_NAME=$(jq -r '.tool_input.agent // .agent // ""' <<< "$INPUT" 2>/dev/null || true)
fi

# Only act on Task tool outputs (agent completions)
if [[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "task" && "$TOOL_NAME" != "Agent" ]]; then
  exit 0
fi

[[ -z "$TOOL_RESPONSE" ]] && exit 0

# ── Decision keyword detection (case-insensitive) ─────────────────────────
DECISION_KEYWORDS=(
  "decidí" "elegí" "recomiendo" "descarto"
  "decided" "chose" "recommend" "discard"
  "selected" "rejected" "I propose"
  "I chose" "I decided" "I recommend"
  "we chose" "we decided"
)

FOUND_KEYWORD=""
for kw in "${DECISION_KEYWORDS[@]}"; do
  if echo "$TOOL_RESPONSE" | grep -qi "$kw"; then
    FOUND_KEYWORD="$kw"
    break
  fi
done

[[ -z "$FOUND_KEYWORD" ]] && exit 0

# ── Extract decision text (first sentence containing keyword) ─────────────
DECISION_LINE=$(echo "$TOOL_RESPONSE" \
  | grep -im 1 "$FOUND_KEYWORD" \
  | head -c 200 \
  | tr -d '\n\r' \
  | sed 's/["`'\'']/\"/g' \
  | sed 's/  */ /g')

[[ -z "$DECISION_LINE" ]] && DECISION_LINE="Architectural decision (keyword: $FOUND_KEYWORD)"

# ── Extract rationale (next non-empty line after decision line) ───────────
RATIONALE=$(echo "$TOOL_RESPONSE" \
  | grep -A 3 -im 1 "$FOUND_KEYWORD" \
  | tail -n +2 \
  | grep -m 1 '[a-zA-Z]' \
  | head -c 300 \
  | tr -d '\n\r')

[[ -z "$RATIONALE" ]] && RATIONALE="Extracted from agent output"

# ── Fallback agent name ───────────────────────────────────────────────────
[[ -z "$AGENT_NAME" ]] && AGENT_NAME="${SAVIA_ACTIVE_AGENT:-unknown-agent}"

# ── Write trace ───────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

SAVIA_DECISION_TRACE=on python3 "$WRITER" \
  --agent "$AGENT_NAME" \
  --decision "$DECISION_LINE" \
  --rationale "$RATIONALE" \
  --confidence 0.5 \
  --output "$OUTPUT_DIR" \
  >/dev/null 2>&1 || true

# Always exit 0 — never block
exit 0
