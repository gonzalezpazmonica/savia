#!/usr/bin/env bash
set -uo pipefail
# prompt-security-scan.sh — Static analyzer for prompt injection/leakage
# Scans agent and skill prompts for dangerous patterns without LLM.
# Usage: bash scripts/prompt-security-scan.sh [--path DIR] [--fix] [--quiet]
# Exit: 0 = clean, 1 = findings, 2 = error
# SE-453: la última línea de stdout es `gate-result: {...}` (clean|findings|unknown). Códigos sin
# renumerar: una comprobación que no corre (python3 ausente, fichero ilegible) o un path sin ficheros
# .md deja el resultado en unknown con exit 0, y se registra en output/unmeasured-gates.jsonl.
# SAVIA_GATE_UNKNOWN=block ⇒ unknown sale 2. Un path inexistente sale 2 siempre (error de uso).
# --quiet suprime toda la salida, también esa línea (el exit code y el registro se mantienen).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()
add_gap() { [[ " ${GAPS[*]} " == *" $1 "* ]] || GAPS+=("$1"); }

SCAN_PATH="${1:-.claude/agents}"
FIX_MODE=false
QUIET=false
FINDINGS_FILE=$(mktemp)
WARNINGS_FILE=$(mktemp)
echo "0" > "$FINDINGS_FILE"
echo "0" > "$WARNINGS_FILE"
trap 'rm -f "$FINDINGS_FILE" "$WARNINGS_FILE"' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) SCAN_PATH="$2"; shift 2 ;;
    --fix) FIX_MODE=true; shift ;;
    --quiet) QUIET=true; shift ;;
    --help|-h) echo "Usage: $0 [--path DIR] [--fix] [--quiet]"; exit 0 ;;
    *) SCAN_PATH="$1"; shift ;;
  esac
done

log_finding() {
  local sev="$1" file="$2" line="$3" rule="$4" desc="$5"
  local c; c=$(cat "$FINDINGS_FILE"); echo $((c + 1)) > "$FINDINGS_FILE"
  $QUIET || printf "  %s  %s:%s — [%s] %s\n" "$sev" "$(basename "$file")" "$line" "$rule" "$desc"
}

log_warn() {
  local c; c=$(cat "$WARNINGS_FILE"); echo $((c + 1)) > "$WARNINGS_FILE"
  $QUIET || printf "  WARN  %s:%s — %s\n" "$(basename "$1")" "$2" "$3"
}

scan_file() {
  local file="$1"
  if [[ ! -r "$file" ]]; then
    add_gap "read:unreadable"
    return 0
  fi

  # PS-01: Injection bait
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-01" "Injection bait: instruction override"
  done < <(grep -nEi '(ignore|forget|disregard|override).*(previous|above|system|prior).*(instructions|prompt|rules|context)' "$file" 2>/dev/null || true)

  # PS-02: Prompt exfiltration
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-02" "Prompt exfiltration: system prompt leak"
  done < <(grep -nEi '(print|show|reveal|output|display|repeat|echo).*(system prompt|all instructions|CLAUDE\.md)' "$file" 2>/dev/null | \
    grep -vi 'check.*rules\|verify.*rules\|business rules\|output.*for' || true)

  # PS-03: Role hijack
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-03" "Role hijack: identity redefinition"
  done < <(grep -nEi '(you are now|from now on you).*(different|new|another|not)' "$file" 2>/dev/null || true)

  # PS-04: Data exfiltration via URL
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-04" "Data exfiltration: suspicious external URL"
  done < <(grep -nEi '(curl|wget|fetch)\s+https?://[^ ]*(api|webhook|endpoint)' "$file" 2>/dev/null | \
    grep -vi 'example\.com\|localhost\|127\.0\.0\.1\|ollama\|anthropic\|github\|azure\|google\|microsoft' || true)

  # PS-05: Credentials in prompt
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-05" "Hardcoded credential in prompt"
  done < <(grep -nEi "(password|secret|token|api.key)\s*[=:]\s*[\"'][^\"']{8,}" "$file" 2>/dev/null | \
    grep -vi 'PLACEHOLDER\|example\|TU_\|YOUR_\|<.*>\|vault\|keyvault\|secretsmanager' || true)

  # PS-06: Eval/exec patterns
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-06" "Code execution pattern in prompt"
  done < <(grep -nEi '(eval|exec|os\.system|child_process)\s*\(' "$file" 2>/dev/null || true)

  # PS-07: Base64 blobs (warning only)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_warn "$file" "$num" "Base64-like content (verify manually)"
  done < <(grep -nE '[A-Za-z0-9+/]{40,}={0,2}' "$file" 2>/dev/null | grep -v 'sha256\|hash\|commit' || true)

  # PS-08: PII in prompts (warning only)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_warn "$file" "$num" "Email in prompt (verify not real PII)"
  done < <(grep -nE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$file" 2>/dev/null | \
    grep -vi '@example\|@test\|@localhost\|noreply\|@anthropic' || true)

  # PS-09: Missing model (agents)
  if [[ "$file" == *agents* ]] && ! grep -qi 'model:' "$file" 2>/dev/null; then
    log_warn "$file" "1" "Agent without model specification"
  fi

  # PS-10: Wildcard tools (agents)
  if [[ "$file" == *agents* ]] && grep -qi 'tools:.*\*' "$file" 2>/dev/null; then
    log_warn "$file" "1" "Agent with wildcard tool access"
  fi

  # PS-11: Zero-width chars (SE-060) — hidden directives via U+200B/C/D/FEFF
  # Python-assisted detection: file encoding errors are expected on binary/non-utf8 — surface nothing
  # rather than corrupt the grep pipeline. See SE-060 for rule definition.
  if command -v python3 >/dev/null 2>&1; then
    local zw_lines zw_rc=0
    zw_lines=$(python3 -c "
import sys
with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
    for i, line in enumerate(f, 1):
        if any(c in line for c in ['\u200B', '\u200C', '\u200D', '\uFEFF']):
            print(i)
" "$file" 2>/dev/null) || zw_rc=$?
    [[ $zw_rc -ne 0 ]] && add_gap "PS-11:unreadable"
    for num in $zw_lines; do
      [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-11" "Zero-width character (possible hidden directive)"
    done
  else
    add_gap "PS-11:missing_tool"
  fi

  # PS-12: Long base64 strings (>80 chars, not in code blocks with hash/commit context)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-12" "Long base64-like string (possible encoded directive)"
  done < <(grep -nE '[A-Za-z0-9+/]{80,}={0,2}' "$file" 2>/dev/null | grep -vi 'sha\|hash\|commit\|signature\|certificate\|-----BEGIN' || true)

  # PS-13: URL-pipe-shell execution
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-13" "URL-pipe-shell execution pattern"
  done < <(grep -nE '(curl|wget)[^|]*https?[^|]*\|[[:space:]]*(bash|sh|zsh)' "$file" 2>/dev/null || true)

  # PS-14: Time-based conditional (time bomb) — epoch comparison in agent/skill prompts
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-14" "Time-based conditional (possible time bomb)"
  done < <(grep -nE 'date[[:space:]]+\+%s.*[><]=?[[:space:]]*[0-9]{10,}' "$file" 2>/dev/null || true)
}

# ── Main ──

$QUIET || printf "\n  Prompt Security Scan\n  %s\n\n" "$(printf '%.0s─' {1..40})"

if [[ ! -d "$SCAN_PATH" ]] && [[ ! -f "$SCAN_PATH" ]]; then
  echo "Error: path not found: $SCAN_PATH" >&2
  GATE_UNMEASURED_ROOT="$ROOT" gate_unmeasured_record "prompt-security-scan" unreadable
  $QUIET || gate_result_emit unknown "path:unreadable"
  exit 2
fi

FILE_COUNT=0
if [[ -d "$SCAN_PATH" ]]; then
  while IFS= read -r -d '' file; do
    ((FILE_COUNT++)) || true
    scan_file "$file"
  done < <(find "$SCAN_PATH" -name '*.md' -type f -print0)
else
  FILE_COUNT=1
  scan_file "$SCAN_PATH"
fi

TOTAL_F=$(cat "$FINDINGS_FILE")
TOTAL_W=$(cat "$WARNINGS_FILE")
$QUIET || printf "\n  Scanned: %d files | Findings: %d | Warnings: %d\n\n" "$FILE_COUNT" "$TOTAL_F" "$TOTAL_W"

[[ "$FILE_COUNT" -eq 0 ]] && add_gap "files:unreadable"
RESULT="clean"
if [[ "$TOTAL_F" -gt 0 ]]; then RESULT="findings"; elif [[ ${#GAPS[@]} -gt 0 ]]; then RESULT="unknown"; fi
[[ "$RESULT" == "unknown" ]] && GATE_UNMEASURED_ROOT="$ROOT" gate_unmeasured_record "prompt-security-scan" "${GAPS[0]#*:}"
$QUIET || gate_result_emit "$RESULT" "${GAPS[@]}"
[[ "$TOTAL_F" -gt 0 ]] && exit 1
[[ "$RESULT" == "unknown" && "${SAVIA_GATE_UNKNOWN:-warn}" == "block" ]] && exit 2
exit 0
