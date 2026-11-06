#!/usr/bin/env bash
# terminal-state-emit.sh — Emits structured termination reason for a loop/agent
# Spec: SPEC-TERMINAL-STATE-HANDOFF
# Ref:  docs/rules/domain/terminal-state-protocol.md
#
# Usage:
#   bash scripts/terminal-state-emit.sh <reason> [--message "detail"] [--loop <name>]
#
# Arguments:
#   <reason>           One of: completed user_abort token_budget stop_hook
#                               max_turns unrecoverable_error handback
#   --message <text>   Optional human-readable detail string
#   --loop    <name>   Loop/agent name (default: "default")
#
# Output:
#   JSON to stdout
#   Appended to output/loop-state/<loop>/terminal-state.jsonl
#
# Exit codes:
#   0  completed | user_abort
#   1  unknown reason or script/usage error (bad --loop, write failure)
#   2  token_budget
#   3  stop_hook
#   4  max_turns
#   5  unrecoverable_error
#   6  handback (SE-332)

set -uo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ── Exit code table ───────────────────────────────────────────────────────────

reason_to_exit_code() {
  case "$1" in
    completed)           echo 0 ;;
    user_abort)          echo 0 ;;
    token_budget)        echo 2 ;;
    stop_hook)           echo 3 ;;
    max_turns)           echo 4 ;;
    unrecoverable_error) echo 5 ;;
    handback)            echo 6 ;;
    *)                   echo 1 ;;
  esac
}

valid_reason() {
  case "$1" in
    completed|user_abort|token_budget|stop_hook|max_turns|unrecoverable_error|handback)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# ── Argument parsing ──────────────────────────────────────────────────────────

REASON=""
MESSAGE=""
LOOP="default"

if [[ $# -eq 0 ]]; then
  usage
fi

REASON="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      [[ $# -ge 2 ]] || die "--message requires a value"
      MESSAGE="$2"
      shift 2
      ;;
    --loop)
      [[ $# -ge 2 ]] || die "--loop requires a value"
      LOOP="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

# ── Validate reason ───────────────────────────────────────────────────────────

# Guard against path traversal in --loop value. Usage errors exit 1: exit 2 is
# token_budget, and an orchestrator would read it as "retry with a bigger model".
if [[ "$LOOP" == *"/"* || "$LOOP" == *".."* ]]; then
  echo "ERROR: --loop value must not contain '/' or '..': '$LOOP'" >&2
  exit 1
fi
# The name is a directory and a JSON field: plain [A-Za-z0-9._-] only, not "."
if [[ ! "$LOOP" =~ ^[A-Za-z0-9._-]+$ || "$LOOP" == "." ]]; then
  echo "ERROR: --loop value must match [A-Za-z0-9._-]+: '$LOOP'" >&2
  exit 1
fi

if ! valid_reason "$REASON"; then
  echo "ERROR: unknown termination reason: '$REASON'" >&2
  echo "Valid reasons: completed user_abort token_budget stop_hook max_turns unrecoverable_error handback" >&2
  exit 1
fi

# ── Build JSON ────────────────────────────────────────────────────────────────

EXIT_CODE=$(reason_to_exit_code "$REASON")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# Escape message for JSON. Backslash FIRST: escaping it after \n turned a real
# newline into a literal "\\n". Then quote, \n, \r, \t; other control chars
# (invalid raw inside a JSON string) are dropped.
MSG_ESCAPED="${MESSAGE//\\/\\\\}"
MSG_ESCAPED="${MSG_ESCAPED//\"/\\\"}"
MSG_ESCAPED="${MSG_ESCAPED//$'\n'/\\n}"
MSG_ESCAPED="${MSG_ESCAPED//$'\r'/\\r}"
MSG_ESCAPED="${MSG_ESCAPED//$'\t'/\\t}"
MESSAGE_ESCAPED=$(printf '%s' "$MSG_ESCAPED" | tr -d '\000-\010\013\014\016-\037')

JSON="{\"ts\":\"${TIMESTAMP}\",\"loop\":\"${LOOP}\",\"reason\":\"${REASON}\",\"message\":\"${MESSAGE_ESCAPED}\",\"exit_code\":${EXIT_CODE}}"

# ── Output to stdout ──────────────────────────────────────────────────────────

echo "$JSON"

# ── Persist to jsonl ──────────────────────────────────────────────────────────

# Resolve repo root: script lives in scripts/, repo root is one level up.
# Allow override via SAVIA_REPO_ROOT for tests.
REPO_ROOT="${SAVIA_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

STATE_DIR="${REPO_ROOT}/output/loop-state/${LOOP}"
STATE_FILE="${STATE_DIR}/terminal-state.jsonl"
# Fail-closed: a state that was not persisted cannot be read by the orchestrator,
# so it must not exit with the reason's code (0 for completed) as if it had been.
if ! mkdir -p "$STATE_DIR" 2>/dev/null || ! echo "$JSON" >> "$STATE_FILE" 2>/dev/null; then
  echo "ERROR: could not persist terminal state to $STATE_FILE" >&2
  exit 1
fi

# ── Exit with mapped code ─────────────────────────────────────────────────────

exit "$EXIT_CODE"
