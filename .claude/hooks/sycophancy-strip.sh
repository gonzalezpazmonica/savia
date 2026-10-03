#!/usr/bin/env bash
set -uo pipefail
# sycophancy-strip.sh — SPEC-192 Layer 1: deterministic adulation hook.
#
# Inspects LLM output (PostToolUse Task envelope or piped text) and applies
# the configured action when adulation patterns match. Layer 1 is regex-only,
# fast (<50ms), no LLM judge involved. Layer 2 (sycophancy-judge) handles
# semantic detection.
#
# Modes (SAVIA_ANTIADULATION_LAYER1):
#   off     — hook disabled completely.
#   shadow  — telemetry only, no stderr, no exit code change. (DEFAULT)
#   warn    — telemetry + stderr advisory.
#   strip   — replace matched span with empty in stdout (for downstream).
#   block   — exit 2 if score >= 85 AND position < 50.
#
# Master switch: SAVIA_ANTIADULATION=off disables everything.
#
# Telemetry: output/anti-adulation-telemetry.jsonl (one JSON per invocation).
# Decisions: PASS, SHADOW_DETECTED, WARN, STRIPPED, BLOCKED,
# BELOW_BLOCK_THRESHOLD, NO_TEXT (envelope without agent text), FAIL_OPEN.
#
# Ref: SPEC-192 docs/propuestas/SPEC-192-anti-adulation-illusory-truth.md

SAVIA_ENV="$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
if [[ -f "$SAVIA_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$SAVIA_ENV"
fi
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$(pwd)}}"

MASTER="${SAVIA_ANTIADULATION:-on}"
[[ "$MASTER" == "off" ]] && exit 0

MODE="${SAVIA_ANTIADULATION_LAYER1:-shadow}"
case "$MODE" in
  off|shadow|warn|strip|block) ;;
  *) MODE="shadow" ;;
esac
[[ "$MODE" == "off" ]] && exit 0

LOG_FILE="${CLAUDE_PROJECT_DIR}/output/anti-adulation-telemetry.jsonl"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log_telemetry() {
  # Args: layer decision score category pattern position draft_len
  local layer="$1" decision="$2" score="$3" category="$4" pattern="$5" position="$6" draft_len="$7"
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg ts "$(date -Iseconds 2>/dev/null || date)" \
      --arg mode "$MODE" \
      --arg layer "$layer" \
      --arg decision "$decision" \
      --arg score "$score" \
      --arg category "$category" \
      --arg pattern "$pattern" \
      --arg position "$position" \
      --arg draft_len "$draft_len" \
      '{ts:$ts, mode:$mode, layer:($layer|tonumber? // 1), decision:$decision, score:($score|tonumber? // 0), category:$category, pattern:$pattern, position:($position|tonumber? // -1), draft_len:($draft_len|tonumber? // 0)}' \
      >> "$LOG_FILE" 2>/dev/null || true
  fi
}

command -v jq >/dev/null 2>&1 || exit 0

# Read input. If stdin has a JSON envelope (hook context), extract draft.
# Otherwise, treat stdin as raw draft text.
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && exit 0

DRAFT=""
# PostToolUse JSON envelope. Claude Code sends the Task/Agent result as
# .tool_response.content[] text blocks (or a plain string); .output and
# .tool_input.text are kept for other emitters. A JSON object must never be
# scanned raw: the ^-anchored patterns would see "{" and pass silently.
# shellcheck disable=SC2016
EXTRACT='def blocks: if type == "string" then .
    elif type == "array" then (map(if type == "string" then . elif type == "object" then (.text // empty) else empty end)
      | map(select(type == "string")) | join("\n"))
    else empty end;
  [ (.tool_response | if type == "object" then (.output, .content, .text) else . end | blocks),
    (.tool_input.text | blocks) ] | map(select(length > 0)) | (.[0] // "")'
# One jq pass: exits non-zero when the input is not a JSON object (raw text).
if DRAFT=$(printf "%s" "$INPUT" | jq -r "if type == \"object\" then ($EXTRACT) else error(\"raw\") end" 2>/dev/null); then
  if [[ -z "$DRAFT" ]]; then
    # Envelope without agent text (e.g. async launch): nothing to inspect.
    log_telemetry "1" "NO_TEXT" "0" "none" "" "-1" "0"
    exit 0
  fi
else
  # Raw draft piped by tests or by other scripts
  DRAFT="$INPUT"
fi

DRAFT_LEN=${#DRAFT}

# Locate detector
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR="$HOOK_DIR/../../scripts/anti-adulation/lexical-strip.py"
PATTERNS="${SAVIA_ANTIADULATION_PATTERNS:-$HOOK_DIR/../../scripts/anti-adulation/regex-patterns.json}"

# Fail-open (never block on our own failure) but leave a FAIL_OPEN trace, so
# a broken Layer 1 shows up in telemetry instead of looking like PASS.
if [[ ! -f "$DETECTOR" || ! -f "$PATTERNS" ]]; then
  log_telemetry "1" "FAIL_OPEN" "0" "detector_or_patterns_missing" "" "-1" "$DRAFT_LEN"
  exit 0
fi

# Run detector. The draft goes through stdin: as an argument, drafts over
# ~128 KB hit ARG_MAX and the detector never ran.
RESULT=$(printf "%s" "$DRAFT" | python3 "$DETECTOR" --draft - --patterns "$PATTERNS" --json 2>/dev/null)
# One jq pass validates the result and extracts the fields (US-separated, so
# an empty pattern does not shift the columns).
FIELDS=""
if [[ -n "$RESULT" ]]; then
  FIELDS=$(printf "%s" "$RESULT" | jq -r '[(.score // 0), (.category // "none"), (.pattern // ""), (.position // -1)] | map(tostring) | join("\u001f")' 2>/dev/null)
fi
if [[ -z "$FIELDS" ]]; then
  log_telemetry "1" "FAIL_OPEN" "0" "detector_error" "" "-1" "$DRAFT_LEN"
  exit 0
fi
IFS=$'\x1f' read -r SCORE CATEGORY PATTERN POSITION <<< "$FIELDS"

if [[ "$SCORE" -eq 0 ]]; then
  log_telemetry "1" "PASS" "0" "none" "" "-1" "$DRAFT_LEN"
  exit 0
fi

case "$MODE" in
  shadow)
    log_telemetry "1" "SHADOW_DETECTED" "$SCORE" "$CATEGORY" "$PATTERN" "$POSITION" "$DRAFT_LEN"
    exit 0
    ;;
  warn)
    log_telemetry "1" "WARN" "$SCORE" "$CATEGORY" "$PATTERN" "$POSITION" "$DRAFT_LEN"
    printf "[anti-adulation L1] WARN: pattern matched (score=%s pos=%s category=%s)\n" \
      "$SCORE" "$POSITION" "$CATEGORY" >&2
    exit 0
    ;;
  strip)
    log_telemetry "1" "STRIPPED" "$SCORE" "$CATEGORY" "$PATTERN" "$POSITION" "$DRAFT_LEN"
    printf "%s" "$RESULT" | jq -r ".stripped"
    exit 0
    ;;
  block)
    if [[ "$SCORE" -ge 85 && "$POSITION" -ge 0 && "$POSITION" -lt 50 ]]; then
      log_telemetry "1" "BLOCKED" "$SCORE" "$CATEGORY" "$PATTERN" "$POSITION" "$DRAFT_LEN"
      cat >&2 <<EOF

[anti-adulation SPEC-192 Layer 1]
Adulation pattern detected at position $POSITION (score=$SCORE):
  pattern : $PATTERN
  category: $CATEGORY

ACTION: regenerate the response without the opening adulation phrase.
The substance of the answer is fine; only the social validation needs to go.

Bypass for this turn: SAVIA_ANTIADULATION_LAYER1=warn (advisory only)
Disable globally  : SAVIA_ANTIADULATION=off
EOF
      exit 2
    fi
    log_telemetry "1" "BELOW_BLOCK_THRESHOLD" "$SCORE" "$CATEGORY" "$PATTERN" "$POSITION" "$DRAFT_LEN"
    exit 0
    ;;
esac
