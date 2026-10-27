#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# ────────────────────────────────────────────────────────────────────────────
# PreToolUse Hook: spec156-token-budget-projection.sh (SPEC-156 Slice 2)
# Projects per-invocation token usage for Task tool dispatches against the
# subagent's per_invocation budget. Logs telemetry; enforces in block mode.
# Env: SAVIA_BUDGET_ENFORCEMENT = warn (default) | block | off
# ────────────────────────────────────────────────────────────────────────────

ENFORCE="${SAVIA_BUDGET_ENFORCEMENT:-warn}"
[ "$ENFORCE" = "off" ] && exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" = "Task" ] || [ "$TOOL_NAME" = "Agent" ] || exit 0

AGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
[ -z "$AGENT" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
AGENT_FILE="$PROJECT_DIR/.opencode/agents/$AGENT.md"
[ -f "$AGENT_FILE" ] || AGENT_FILE="$PROJECT_DIR/.claude/agents/$AGENT.md"
[ -f "$AGENT_FILE" ] || exit 0  # unknown agent — let other hooks handle

# Extract token_budget fields — supports BOTH block and flow YAML syntax
# Block:  token_budget:\n  per_invocation: 100000\n  ...
# Flow:   token_budget: {per_invocation: 100000, context_window_target: 20000, escalation_policy: block}
extract_tb_field() {
  local file="$1" field="$2" val=""
  local flow_line
  flow_line=$(grep -E '^token_budget:[[:space:]]*\{' "$file" | head -1 || true)
  if [ -n "$flow_line" ]; then
    val=$(echo "$flow_line" | grep -oE "${field}:[[:space:]]*[^,}]+" | head -1 \
          | sed -E "s/^${field}:[[:space:]]*//;s/[[:space:]\"]+\$//")
    echo "$val"
    return
  fi
  awk -v f="$field" '
    /^token_budget:[[:space:]]*$/ { in_tb=1; next }
    in_tb && /^[a-zA-Z_]/ && !/^[[:space:]]/ { in_tb=0 }
    in_tb && $0 ~ "^[[:space:]]+" f ":" {
      sub(".*" f ":[[:space:]]*", "")
      gsub(/[[:space:]"]/, "")
      print
      exit
    }
  ' "$file"
}

PER_INV=$(extract_tb_field "$AGENT_FILE" "per_invocation" | tr -dc '0-9')
POLICY=$(extract_tb_field "$AGENT_FILE" "escalation_policy")
CTX_TARGET=$(extract_tb_field "$AGENT_FILE" "context_window_target" | tr -dc '0-9')

[ -z "$PER_INV" ] && exit 0  # no budget declared — skip silently
CTX_TARGET="${CTX_TARGET:-0}"

PROMPT_CHARS=${#PROMPT}
PROMPT_TOKENS=$(( PROMPT_CHARS / 4 ))
PROJECTED=$(( PROMPT_TOKENS + CTX_TARGET ))

# Telemetry sink
LOG_DIR="$PROJECT_DIR/output/agent-runs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/budget-projections.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION="${CLAUDE_SESSION_ID:-${SAVIA_SESSION_ID:-unknown}}"

# Determine verdict
VERDICT="ok"
if [ "$PROJECTED" -gt "$PER_INV" ]; then
  VERDICT="exceeded"
elif [ "$PROJECTED" -gt $((PER_INV * 80 / 100)) ]; then
  VERDICT="warn"
fi

# Append JSONL line (single line, no embedded newlines)
printf '{"ts":"%s","session":"%s","agent":"%s","per_invocation":%d,"projected":%d,"prompt_tokens":%d,"context_target":%d,"policy":"%s","verdict":"%s","enforcement":"%s"}\n' \
  "$TS" "$SESSION" "$AGENT" "$PER_INV" "$PROJECTED" "$PROMPT_TOKENS" "$CTX_TARGET" "$POLICY" "$VERDICT" "$ENFORCE" \
  >> "$LOG_FILE"

# Emit warning to stderr on warn/exceeded
if [ "$VERDICT" != "ok" ]; then
  echo "" >&2
  echo "═══ SPEC-156 Token Budget Projection ═══" >&2
  echo "Agent: $AGENT (policy=$POLICY)" >&2
  echo "Projected: $PROJECTED tokens (cap: $PER_INV) — verdict: $VERDICT" >&2
  echo "═════════════════════════════════════════" >&2
fi

# Enforcement: block only when ENFORCE=block AND verdict=exceeded AND policy=block
if [ "$ENFORCE" = "block" ] && [ "$VERDICT" = "exceeded" ] && [ "$POLICY" = "block" ]; then
  echo "BLOCKED: token budget exceeded for $AGENT" >&2
  exit 2
fi

exit 0
