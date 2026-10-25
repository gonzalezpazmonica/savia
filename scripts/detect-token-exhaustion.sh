#!/usr/bin/env bash
# detect-token-exhaustion.sh — SE-250: classify agent failure cause
#
# Input:  --log <path>  (required)
# Output: CAUSE=token_exhaustion|logic_error|unknown  (stdout)
# Exit:   0 = token_exhaustion or logic_error determined
#         1 = log file not found or empty
#         2 = cause is unknown
#
# Design: pure bash regex heuristics, no LLM call.
# Conservative: only escalates on explicit token-exhaustion signals.
# Reference: SE-250 docs/propuestas/SE-250-agent-rotation-overnight-sprint.md

set -uo pipefail

# ── Usage ─────────────────────────────────────────────────────────────────────

show_usage() {
  cat <<USG
Usage: detect-token-exhaustion.sh --log <path> [--verbose]

Classify the cause of an overnight-sprint agent iteration failure.

Options:
  --log <path>   Path to the agent iteration log file (required)
  --verbose      Print matched signal to stderr
  --help, -h     Show this help

Exit codes:
  0   Cause determined: CAUSE=token_exhaustion (escalation recommended)
      or CAUSE=logic_error (do not escalate)
  1   Log file not found or empty
  2   Cause unknown (conservative: do not escalate)

Output:
  CAUSE=token_exhaustion|logic_error|unknown  (printed to stdout)

Examples:
  detect-token-exhaustion.sh --log /tmp/iteration-5.log
  if detect-token-exhaustion.sh --log "/tmp/iteration.log" && grep -q token_exhaustion; then ...
USG
}

# ── Arg parsing ───────────────────────────────────────────────────────────────

LOG_PATH=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)     [[ $# -ge 2 ]] || { echo "ERROR: --log requires a value" >&2; exit 1; }
               LOG_PATH="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    --help|-h) show_usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; show_usage >&2; exit 1 ;;
  esac
done

if [[ -z "$LOG_PATH" ]]; then
  echo "ERROR: --log is required" >&2
  show_usage >&2
  exit 1
fi

# ── Gate: log exists and is non-empty ────────────────────────────────────────

if [[ ! -f "$LOG_PATH" ]]; then
  echo "ERROR: log not found: $LOG_PATH" >&2
  echo "CAUSE=unknown"
  exit 1
fi

if [[ ! -s "$LOG_PATH" ]]; then
  echo "ERROR: log is empty: $LOG_PATH" >&2
  echo "CAUSE=unknown"
  exit 1
fi

# ── Token exhaustion signals ─────────────────────────────────────────────────
# Regex patterns derived from observed Claude API error messages (2024-2026).
# Conservative: only patterns with very low false-positive rate.

TOKEN_EXHAUSTION_PATTERNS=(
  "context_length_exceeded"
  "max_tokens.*exceeded"
  "prompt.*too long"
  "input.*too long"
  "input length.*exceeds"
  "prompt.*exceeds.*maximum"
  "tokens.*limit"
  "context.*window.*full"
  "OutputBlockedError"
  "ContextWindowExceeded"
  "[Mm]aximum context length"
  "[Tt]oo many tokens"
  "prompt.*is.*too.*long"
)

# ── Logic error signals ───────────────────────────────────────────────────────
# Patterns that clearly indicate non-token failures.

LOGIC_ERROR_PATTERNS=(
  "SyntaxError"
  "NameError"
  "TypeError"
  "ImportError"
  "ModuleNotFoundError"
  "FileNotFoundError"
  "PermissionError"
  "ConnectionError"
  "TimeoutError"
  "subprocess.*failed"
  "command not found"
  "exit code [1-9]"
  "assertion.*failed"
  "test.*failed"
  "BATS.*not ok"
  "Error:.*line [0-9]"
  "bash.*syntax error"
  "unexpected.*token"
)

# ── Detection ─────────────────────────────────────────────────────────────────

check_patterns() {
  local log="$1"
  shift
  local patterns=("$@")
  for pat in "${patterns[@]}"; do
    if grep -qiE "$pat" "$log" 2>/dev/null; then
      if [[ "$VERBOSE" == "true" ]]; then
        echo "SIGNAL: matched '$pat'" >&2
      fi
      return 0  # match found
    fi
  done
  return 1  # no match
}

# Check token exhaustion first (more actionable)
if check_patterns "$LOG_PATH" "${TOKEN_EXHAUSTION_PATTERNS[@]}"; then
  echo "CAUSE=token_exhaustion"
  exit 0
fi

# Check logic errors
if check_patterns "$LOG_PATH" "${LOGIC_ERROR_PATTERNS[@]}"; then
  echo "CAUSE=logic_error"
  exit 0
fi

# Unknown — conservative: do NOT escalate
echo "CAUSE=unknown"
exit 2
