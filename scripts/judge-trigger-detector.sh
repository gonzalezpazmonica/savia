#!/usr/bin/env bash
set -uo pipefail
# judge-trigger-detector.sh — SE-273 S1: Deterministic trigger detection
#
# Evaluates tool output against known judge trigger conditions.
# Fast (deterministic regex + file checks, no LLM). Writes structured
# trigger events to output/judge-triggers.jsonl for downstream processing.
#
# Usage: bash scripts/judge-trigger-detector.sh <tool_name> [input_file]
#   tool_name:   name of the tool that produced output (WebFetch, Bash, Task, Edit, Write, Read)
#   input_file:  optional file containing output content to scan (default: stdin)

TOOL="${1:-}"
INPUT="${2:-/dev/stdin}"
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TRIGGER_LOG="${ROOT}/output/judge-triggers.jsonl"
ANTI_FATIGUE_LOG="${ROOT}/output/anti-fatigue-ledger.jsonl"
ROUTING="${ROOT}/config/judge-routing.yaml"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID="${SAVIA_SESSION_ID:-unknown}"

mkdir -p "$(dirname "$TRIGGER_LOG")"

# ── Trigger detection functions ─────────────────────────────────────────

# Authority claim patterns: "según X", "el estándar dice", "the docs say", etc.
detect_authority_claim() {
  local content
  content=$(cat "$INPUT" 2>/dev/null)
  if echo "$content" | grep -qiE \
    '(según\s+(la\s+)?documentaci[oó]n|el\s+est[aá]ndar\s+(exige|dice|establece)|'\
'according\s+to\s+(the\s+)?(docs|documentation|spec|standard)|'\
'the\s+(docs|spec|standard)\s+(says|states|requires)|'\
'per\s+(spec|standard|RFC|ISO)|'\
'como\s+(establece|indica|se[aññ]ala)\s+(la|el)\s+(ley|norma|reglamento)|'\
'best\s+practice(s)?\s+(is|are|dictate|require)|'\
'la\s+documentaci[oó]n\s+(oficial\s+)?(dice|indica|muestra))' 2>/dev/null; then
    return 0
  fi
  return 1
}

# Source traceability: WebFetch or Bash with network tools
detect_source_ingestion() {
  [[ "$TOOL" == "WebFetch" ]] && return 0
  if [[ "$TOOL" == "Bash" ]]; then
    local cmd
    cmd=$(cat "$INPUT" 2>/dev/null | head -5)
    if echo "$cmd" | grep -qE '(curl|wget|fetch|httpie|python3.*requests|python3.*urllib|node.*fetch)' 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Hallucination-fast: output contains factual assertions (verifiable entities)
detect_factual_assertion() {
  local content
  content=$(cat "$INPUT" 2>/dev/null)
  # Detects: numbers with units, dates, version numbers, file paths, URLs, API names
  local factual_count
  factual_count=$(echo "$content" | grep -cPi \
    '(\b(v|version)\s*\d+\.\d+|'\
'\b\d{4}-\d{2}-\d{2}\b|'\
'\b\d+\s*(ms|seconds?|minutes?|hours?|KB|MB|GB|%)\b|'\
'\bhttps?://[^\s]+|'\
'\b[\w/.-]+\.(md|ts|sh|yaml|json|py|cs|go|rs|java)\b|'\
'\bAPI\s+(endpoint|call|version)|'\
'\b(config|env|settings)\.[a-z]+\b)' 2>/dev/null || true)
  [[ "${factual_count:-0}" -ge 3 ]] && return 0
  return 1
}

# Rule violation: action touches governed paths
detect_rule_violation() {
  if [[ "$TOOL" == "Edit" || "$TOOL" == "Write" || "$TOOL" == "Bash" ]]; then
    local content
    content=$(cat "$INPUT" 2>/dev/null)
    if echo "$content" | grep -qE \
      '(CLAUDE\.md|CONSTITUCION\.md|CRITERIO\.md|\.claude/settings\.json|'\
'\.opencode/settings\.json|\.confidentiality-signature)' 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# ── Emit trigger event ──────────────────────────────────────────────────
emit_trigger() {
  local judge="$1"
  local reason="$2"
  local mode="$3"
  local blocking="$4"
  local escalation="$5"
  
  # Build JSON line
  local json
  json=$(cat <<JSON
{"ts":"$TS","session":"$SESSION_ID","tool":"$TOOL","judge":"$judge","reason":"$reason","mode":"$mode","blocking":$blocking,"escalation":"$escalation"}
JSON
)
  echo "$json" >> "$TRIGGER_LOG"
  
  # Non-blocking trigger: just log
  if [[ "$blocking" == "false" ]]; then
    echo "[JUDGE-TRIGGER] $judge ($mode) — $reason" >&2
  else
    echo "[JUDGE-BLOCK] $judge ($mode) — $reason" >&2
  fi
}

# ── Anti-fatiga check ───────────────────────────────────────────────────
check_anti_fatigue() {
  local judge="$1"
  local max_ignored="${2:-3}"
  local window_hours="${3:-24}"
  
  [[ ! -f "$ANTI_FATIGUE_LOG" ]] && return 0
  
  local cutoff
  cutoff=$(date -u -d "${window_hours} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")
  
  local ignored_count
  ignored_count=$(grep "$judge" "$ANTI_FATIGUE_LOG" 2>/dev/null | awk -F'"' -v cutoff="$cutoff" '$4 >= cutoff' | wc -l)
  
  if [[ "$ignored_count" -ge "$max_ignored" ]]; then
    echo "[ANTI-FATIGA] $judge: $ignored_count ignored verdicts in ${window_hours}h window — escalating to blocking" >&2
    return 1
  fi
  return 0
}

# ── Main detection loop ─────────────────────────────────────────────────
[[ -z "$TOOL" ]] && echo "Usage: $0 <tool_name> [input_file]" >&2 && exit 2

triggers=0

# 1. hallucination-fast-judge: factual assertions in output
if detect_factual_assertion; then
  if check_anti_fatigue "hallucination-fast-judge"; then
    emit_trigger "hallucination-fast-judge" \
      "factual assertions detected in $TOOL output" \
      "auto" "false" "hallucination-judge"
    triggers=$((triggers + 1))
  fi
fi

# 2. source-traceability-judge: web/external ingestion
if detect_source_ingestion; then
  if check_anti_fatigue "source-traceability-judge"; then
    emit_trigger "source-traceability-judge" \
      "external source ingestion via $TOOL" \
      "auto" "false" "factuality-judge"
    triggers=$((triggers + 1))
  fi
fi

# 3. authority-claim-judge: output invokes authority
if detect_authority_claim; then
  if check_anti_fatigue "authority-claim-judge"; then
    emit_trigger "authority-claim-judge" \
      "authority invocation patterns detected in $TOOL output" \
      "auto" "false" "factuality-judge"
    triggers=$((triggers + 1))
  fi
fi

# 4. rule-violation-judge: action touches governed paths
if detect_rule_violation; then
  emit_trigger "rule-violation-judge" \
    "action touches governed paths via $TOOL" \
    "auto" "true" ""
  triggers=$((triggers + 1))
fi

exit $triggers
