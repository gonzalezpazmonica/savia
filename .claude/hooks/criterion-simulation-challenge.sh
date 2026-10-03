#!/usr/bin/env bash
set -uo pipefail
# criterion-simulation-challenge.sh — SPEC-194 Criterion Simulation Layer
#
# Pre-task / pre-spec-implement hook. Evaluates whether the task's framing
# should be challenged before execution.
#
# Master switch: SAVIA_CRITERION_SIMULATION=off (default) -> exit 0 silently.
# This is OPT-IN. Set SAVIA_CRITERION_SIMULATION=on to activate.
#
# Modes (SAVIA_CS_MODE):
#   shadow    — telemetry only, no stderr output.
#   advise    — emit banner to stderr if FRAME_DOUBT|FRAME_REJECT, exit 0 always.
#   interrupt — emit banner + log reaffirmation_required=true, exit 0 always.
#
# CRITICAL: This hook NEVER exits with code != 0. It never blocks execution.
# The only action it takes is: emit a banner (advise/interrupt) and log.
#
# Telemetry: output/criterion-simulation/events.jsonl
#   Each event carries signals_degraded (sources that failed and counted as 0)
#   and priors_source, because the trigger's stderr is discarded below.
#
# Ref: SPEC-194 docs/propuestas/SPEC-194-criterion-simulation-layer.md


# ── Master switch — default OFF (opt-in) ──────────────────────────────────────
MASTER="${SAVIA_CRITERION_SIMULATION:-off}"
if [[ "$MASTER" == "off" ]]; then
  exit 0
fi

# ── Mode ──────────────────────────────────────────────────────────────────────
MODE="${SAVIA_CS_MODE:-advise}"
case "$MODE" in
  shadow|advise|interrupt) ;;
  *) MODE="advise" ;;
esac

# ── Paths ─────────────────────────────────────────────────────────────────────
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# LOG_FILE: honour absolute SAVIA_CS_LOG; otherwise build from PROJECT_DIR
_CS_LOG_RAW="${SAVIA_CS_LOG:-output/criterion-simulation/events.jsonl}"
if [[ "$_CS_LOG_RAW" == /* ]]; then
  LOG_FILE="$_CS_LOG_RAW"
else
  LOG_FILE="${PROJECT_DIR}/${_CS_LOG_RAW}"
fi
LOG_DIR="$(dirname "$LOG_FILE")"
TRIGGER_SCRIPT="${PROJECT_DIR}/scripts/criterion-simulation/trigger-evaluator.py"

mkdir -p "$LOG_DIR" 2>/dev/null || true

# ── Telemetry helper ──────────────────────────────────────────────────────────
SIGNALS_DEGRADED="[]"
PRIORS_SOURCE="none"
log_event() {
  local verdict="${1:-BYPASS}" score="${2:-0}" reasons="${3:-[]}" banner_emitted="${4:-false}"
  local ts
  ts="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg ts        "$ts" \
      --arg verdict   "$verdict" \
      --arg score     "$score" \
      --arg mode      "$MODE" \
      --argjson reasons    "$reasons" \
      --argjson banner_emitted "$banner_emitted" \
      --argjson signals_degraded "$SIGNALS_DEGRADED" \
      --arg priors_source "$PRIORS_SOURCE" \
      '{ts:$ts, verdict:$verdict, score:($score|tonumber? // 0), reasons:$reasons, mode:$mode, banner_emitted:$banner_emitted, signals_degraded:$signals_degraded, priors_source:$priors_source}' \
      >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# ── Read input ────────────────────────────────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT="$(cat 2>/dev/null || true)"
fi

# ── Build task context ────────────────────────────────────────────────────────
# Try to extract from JSON envelope; otherwise use empty context
TASK_CTX="{}"
if [[ -n "$INPUT" ]] && command -v jq >/dev/null 2>&1; then
  if printf "%s" "$INPUT" | jq -e . >/dev/null 2>&1; then
    # Attempt to extract task_context sub-object or use full input as context
    EXTRACTED=$(printf "%s" "$INPUT" | jq -r '.task_context // . // {}' 2>/dev/null)
    if [[ -n "$EXTRACTED" ]]; then
      TASK_CTX="$EXTRACTED"
    fi
  fi
fi

# ── Run trigger evaluator ────────────────────────────────────────────────────
if [[ ! -f "$TRIGGER_SCRIPT" ]]; then
  # Fail-open: no script = no activation
  log_event "BYPASS_NO_SCRIPT" "0" "[]" "false"
  exit 0
fi

TRIGGER_OUTPUT=""
if ! TRIGGER_OUTPUT=$(echo "$TASK_CTX" | python3 "$TRIGGER_SCRIPT" 2>/dev/null); then
  log_event "BYPASS_TRIGGER_ERROR" "0" "[]" "false"
  exit 0
fi

if [[ -z "$TRIGGER_OUTPUT" ]] || ! printf "%s" "$TRIGGER_OUTPUT" | jq -e . >/dev/null 2>&1; then
  log_event "BYPASS_INVALID_TRIGGER" "0" "[]" "false"
  exit 0
fi

ACTIVATE=$(printf "%s" "$TRIGGER_OUTPUT" | jq -r '.activate // false')
SCORE=$(printf "%s" "$TRIGGER_OUTPUT" | jq -r '.score // 0')
REASONS=$(printf "%s" "$TRIGGER_OUTPUT" | jq -c '.reasons // []')
SIGNALS_DEGRADED=$(printf "%s" "$TRIGGER_OUTPUT" | jq -c '.signals_degraded // []')
PRIORS_SOURCE=$(printf "%s" "$TRIGGER_OUTPUT" | jq -r '.priors.source // "unknown"')

if [[ "$ACTIVATE" != "true" ]]; then
  log_event "BYPASS_LOW_SCORE" "$SCORE" "$REASONS" "false"
  exit 0
fi

# ── Build mock verdict for shadow mode / when no judge available ──────────────
# In a full deployment, this would invoke the criterion-simulation-judge agent.
# For testability and offline mode: check for SAVIA_CS_MOCK_VERDICT env var.
VERDICT_JSON="${SAVIA_CS_MOCK_VERDICT:-}"

if [[ -z "$VERDICT_JSON" ]]; then
  # No mock and no live judge: log activation but skip banner
  log_event "ACTIVATED_NO_JUDGE" "$SCORE" "$REASONS" "false"
  exit 0
fi

# Parse verdict
if ! printf "%s" "$VERDICT_JSON" | jq -e . >/dev/null 2>&1; then
  log_event "BYPASS_INVALID_VERDICT" "$SCORE" "$REASONS" "false"
  exit 0
fi

DECISION=$(printf "%s" "$VERDICT_JSON" | jq -r '.verdict // "FRAME_OK"')
BANNER_TEXT=$(printf "%s" "$VERDICT_JSON" | jq -r '.banner_text // ""')
TOKENS_USED=$(printf "%s" "$VERDICT_JSON" | jq -r '.tokens_used // 0')

# ── Shadow mode: telemetry only ───────────────────────────────────────────────
if [[ "$MODE" == "shadow" ]]; then
  log_event "$DECISION" "$SCORE" "$REASONS" "false"
  exit 0
fi

# ── advise + interrupt: emit banner for FRAME_DOUBT / FRAME_REJECT ────────────
case "$DECISION" in
  FRAME_OK)
    log_event "FRAME_OK" "$SCORE" "$REASONS" "false"
    exit 0
    ;;
  FRAME_DOUBT|FRAME_REJECT)
    # ── Emit challenge banner to stderr ──────────────────────────────────────
    cat >&2 <<BANNER

[criterion-simulation SPEC-194] verdict: ${DECISION}
DISCLAIMER: simulacion de meta-reflexion, no tu criterio. Tu decides.
This is a heuristic interruption when operator-state signals are elevated.

${BANNER_TEXT}

ACTION: reaffirm the frame consciously OR redefine the task.
  python3 scripts/criterion-simulation/reaffirmation-log.py reaffirm \\
       --task <id> --reason "<reason of at least 20 chars>"
  python3 scripts/criterion-simulation/reaffirmation-log.py reframe \\
       --task <id> --new-statement "<new problem statement>"

Bypass: SAVIA_CRITERION_SIMULATION=off
BANNER

    BANNER_EMITTED="true"
    log_event "$DECISION" "$SCORE" "$REASONS" "$BANNER_EMITTED"

    # ── interrupt mode: log reaffirmation_required ────────────────────────────
    if [[ "$MODE" == "interrupt" ]]; then
      local_ts="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
      if command -v jq >/dev/null 2>&1; then
        jq -nc \
          --arg ts     "$local_ts" \
          --arg verdict "$DECISION" \
          --arg score   "$SCORE" \
          '{ts:$ts, verdict:$verdict, score:($score|tonumber? // 0), reaffirmation_required:true, mode:"interrupt"}' \
          >> "$LOG_FILE" 2>/dev/null || true
      fi
    fi

    # NEVER exit non-zero. The hook challenges; it does not block.
    exit 0
    ;;
  *)
    log_event "UNKNOWN_VERDICT" "$SCORE" "$REASONS" "false"
    exit 0
    ;;
esac
