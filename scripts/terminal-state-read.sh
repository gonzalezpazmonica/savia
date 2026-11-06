#!/usr/bin/env bash
# terminal-state-read.sh — Reads the last terminal state for a loop/agent
# Spec: SPEC-TERMINAL-STATE-HANDOFF
# Ref:  docs/rules/domain/terminal-state-protocol.md
#
# Usage:
#   bash scripts/terminal-state-read.sh --loop <name>
#
# Output:
#   Last JSON line of output/loop-state/<loop>/terminal-state.jsonl to stdout
#
# Exit codes: reflect the 'reason' of the last recorded state
#   0  completed | user_abort
#   1  unknown reason, no state file found, or usage error (bad --loop)
#   2  token_budget
#   3  stop_hook
#   4  max_turns
#   5  unrecoverable_error
#   6  handback (SE-332)
#
# Orchestrator decision table:
#   completed           → no reintentar, marcar done
#   user_abort          → no reintentar, preservar estado parcial
#   token_budget        → escalar modelo, reintentar con checkpoint
#   max_turns           → si retry_count < 3: reintentar con contexto comprimido
#                         si retry_count >= 3: escalar a humano
#   unrecoverable_error → escalar a humano inmediatamente (no reintentar)
#   stop_hook           → revisar qué hook bloqueó, escalar a humano (no reintentar)
#   handback            → resolver el padre (handback-resolve.sh), no reintentar

set -uo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ── Exit code table (must match terminal-state-emit.sh) ──────────────────────

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

# ── Argument parsing ──────────────────────────────────────────────────────────

LOOP=""

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
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

[[ -n "$LOOP" ]] || die "--loop is required"

# Path traversal guard (same rule as emit). Exit 1, never 2: 2 means token_budget.
if [[ "$LOOP" == *"/"* || "$LOOP" == *".."* || ! "$LOOP" =~ ^[A-Za-z0-9._-]+$ || "$LOOP" == "." ]]; then
  echo "ERROR: --loop value must not contain '/' or '..' and must match [A-Za-z0-9._-]+: '$LOOP'" >&2
  exit 1
fi

# ── Locate state file ─────────────────────────────────────────────────────────

REPO_ROOT="${SAVIA_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_FILE="${REPO_ROOT}/output/loop-state/${LOOP}/terminal-state.jsonl"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: no terminal state file found for loop '${LOOP}' at ${STATE_FILE}" >&2
  exit 1
fi

if [[ ! -s "$STATE_FILE" ]]; then
  echo "ERROR: terminal state file is empty for loop '${LOOP}'" >&2
  exit 1
fi

# ── Read last entry ───────────────────────────────────────────────────────────

LAST_LINE=$(tail -n 1 "$STATE_FILE")

echo "$LAST_LINE"

# ── Extract reason and map to exit code ──────────────────────────────────────
# Parse "reason" field from the JSON line without requiring jq.
# JSON format is deterministic (produced by terminal-state-emit.sh):
#   {"ts":"...","loop":"...","reason":"<value>","message":"...","exit_code":<n>}

REASON=$(grep -o '"reason":"[^"]*"' <<< "$LAST_LINE" | cut -d'"' -f4)

# Exactly one reason field: two (a forged line) is ambiguous, so it is an error.
if [[ -z "$REASON" || "$REASON" == "$LAST_LINE" || "$REASON" == *$'\n'* ]]; then
  echo "ERROR: could not parse 'reason' from last state line" >&2
  exit 1
fi

EXIT_CODE=$(reason_to_exit_code "$REASON")
exit "$EXIT_CODE"
