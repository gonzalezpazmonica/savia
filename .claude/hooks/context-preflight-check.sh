#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# ─────────────────────────────────────────────────────────────────────────────
# PreToolUse Hook: context-preflight-check.sh (SPEC-157)
#
# Multi-source token preflight for Task tool dispatches.
# Calls scripts/context-preflight-check.sh (estimator) and:
#   - Emits warn to stderr when projected > 80% of agent budget
#   - Emits skill suggestions: context-rot-strategy, context-task-classifier
#   - Blocks (exit 2) when SAVIA_BUDGET_ENFORCEMENT=block + policy=block + exceeded
#
# Env:
#   SAVIA_PREFLIGHT           = on (default) | off
#   SAVIA_BUDGET_ENFORCEMENT  = warn (default) | block | off
#
# This hook runs AFTER spec156-token-budget-projection.sh in the PreToolUse
# Task chain. It adds multi-source estimation (file refs, skill refs, caching)
# on top of SPEC-156's basic projection.
#
# SPEC-157 Slice 2.
# ─────────────────────────────────────────────────────────────────────────────

PREFLIGHT="${SAVIA_PREFLIGHT:-on}"
[ "$PREFLIGHT" = "off" ] && exit 0

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ "$TOOL_NAME" = "Task" ] || [ "$TOOL_NAME" = "Agent" ] || exit 0

AGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)
[ -z "$AGENT" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Locate estimator relative to this hook's own location (robust to PROJECT_DIR changes)
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESTIMATOR="$_HOOK_DIR/../../scripts/context-preflight-check.sh"
# Fallback: also check PROJECT_DIR/scripts/
[ -f "$ESTIMATOR" ] || ESTIMATOR="$PROJECT_DIR/scripts/context-preflight-check.sh"

# Degrade gracefully if estimator is missing
[ -f "$ESTIMATOR" ] || exit 0

export PROJECT_DIR
RESULT=$(printf '%s' "$PROMPT" | bash "$ESTIMATOR" "$AGENT" 2>/dev/null) || exit 0

VERDICT=$(printf '%s' "$RESULT" | jq -r '.verdict // "ok"' 2>/dev/null || echo "ok")
[ "$VERDICT" = "ok" ] && exit 0

PROJECTED=$(printf '%s' "$RESULT" | jq -r '.projected // 0' 2>/dev/null || echo 0)
BUDGET=$(printf '%s' "$RESULT"   | jq -r '.budget // 0'    2>/dev/null || echo 0)
POLICY=$(printf '%s' "$RESULT"   | jq -r '.policy // "warn"' 2>/dev/null || echo "warn")

# Emit warning + suggestions
{
  echo ""
  echo "═══ SPEC-157 Context Pre-Flight Check ═══"
  echo "Agent : $AGENT"
  echo "Load  : $PROJECTED / $BUDGET tokens ($VERDICT)"
  echo "Action: compact context before dispatching this task"
  echo "Skills: context-rot-strategy · context-task-classifier"
  echo "═════════════════════════════════════════"
} >&2

# Block only on explicit enforcement + exceeded + agent policy=block
ENFORCE="${SAVIA_BUDGET_ENFORCEMENT:-warn}"
if [ "$ENFORCE" = "block" ] && [ "$VERDICT" = "exceeded" ] && [ "$POLICY" = "block" ]; then
  echo "BLOCKED: context budget exceeded for $AGENT. Split the task or compact context first." >&2
  exit 2
fi

exit 0
