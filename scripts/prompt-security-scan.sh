#!/usr/bin/env bash
set -uo pipefail
# prompt-security-scan.sh — Static analyzer for prompt injection/leakage
# Scans agent and skill prompts for dangerous patterns without LLM.
# Usage: bash scripts/prompt-security-scan.sh [--path DIR] [--fix] [--quiet]
# Exit: 0 = clean, 1 = findings, 2 = error
# SE-453: la última línea de stdout es `gate-result: {...}` (clean|findings|unknown). Códigos sin
# renumerar: un fichero ilegible (también un error de lectura que -r no ve), un find que no recorre algún
# subdirectorio o un path sin ficheros .md deja el resultado en unknown con exit 0, y se registra en
# output/unmeasured-gates.jsonl. SAVIA_GATE_UNKNOWN=block ⇒ unknown sale 2. Un path inexistente sale 2
# siempre (error de uso). --quiet calla el informe, pero la línea gate-result se emite siempre (#1355).
# PS-11 no depende de python3 (bytes UTF-8 con grep en locale C; revisión #1355).

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
    $QUIET || printf "  GAP   %s — no se puede leer\n" "$(basename "$file")"
    return 0
  fi

  # Un error de lectura que -r no ve (EIO…) lo daría limpio: grep sale con 2 y las reglas lo callan (#1355).
  local rc=0; grep -aq '' "$file" 2>/dev/null || rc=$?
  if (( rc > 1 )); then
    add_gap "read:unreadable"
    $QUIET || printf "  GAP   %s — error de lectura\n" "$(basename "$file")"
    return 0
  fi

  # PS-01: Injection bait
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-01" "Injection bait: instruction override"
  done < <(grep -anEi '(ignore|forget|disregard|override).*(previous|above|system|prior).*(instructions|prompt|rules|context)' "$file" 2>/dev/null || true)

  # PS-02: Prompt exfiltration
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-02" "Prompt exfiltration: system prompt leak"
  done < <(grep -anEi '(print|show|reveal|output|display|repeat|echo).*(system prompt|all instructions|CLAUDE\.md)' "$file" 2>/dev/null | \
    grep -avi 'check.*rules\|verify.*rules\|business rules\|output.*for' || true)

  # PS-03: Role hijack
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-03" "Role hijack: identity redefinition"
  done < <(grep -anEi '(you are now|from now on you).*(different|new|another|not)' "$file" 2>/dev/null || true)

  # PS-04: Data exfiltration via URL
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-04" "Data exfiltration: suspicious external URL"
  done < <(grep -anEi '(curl|wget|fetch)\s+https?://[^ ]*(api|webhook|endpoint)' "$file" 2>/dev/null | \
    grep -avi 'example\.com\|localhost\|127\.0\.0\.1\|ollama\|anthropic\|github\|azure\|google\|microsoft' || true)

  # PS-05: Credentials in prompt
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "CRIT" "$file" "$num" "PS-05" "Hardcoded credential in prompt"
  done < <(grep -anEi "(password|secret|token|api.key)\s*[=:]\s*[\"'][^\"']{8,}" "$file" 2>/dev/null | \
    grep -avi 'PLACEHOLDER\|example\|TU_\|YOUR_\|<.*>\|vault\|keyvault\|secretsmanager' || true)

  # PS-06: Eval/exec patterns
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-06" "Code execution pattern in prompt"
  done < <(grep -anEi '(eval|exec|os\.system|child_process)\s*\(' "$file" 2>/dev/null || true)

  # PS-07: Base64 blobs (warning only)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_warn "$file" "$num" "Base64-like content (verify manually)"
  done < <(grep -anE '[A-Za-z0-9+/]{40,}={0,2}' "$file" 2>/dev/null | grep -av 'sha256\|hash\|commit' || true)

  # PS-08: PII in prompts (warning only)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_warn "$file" "$num" "Email in prompt (verify not real PII)"
  done < <(grep -anE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$file" 2>/dev/null | \
    grep -avi '@example\|@test\|@localhost\|noreply\|@anthropic' || true)

  # PS-09: Missing model (agents)
  if [[ "$file" == *agents* ]] && ! grep -aqi 'model:' "$file" 2>/dev/null; then
    log_warn "$file" "1" "Agent without model specification"
  fi

  # PS-10: Wildcard tools (agents)
  if [[ "$file" == *agents* ]] && grep -aqi 'tools:.*\*' "$file" 2>/dev/null; then
    log_warn "$file" "1" "Agent with wildcard tool access"
  fi

  # PS-11: Zero-width chars (SE-060) — hidden directives via U+200B-D, U+2060, U+FEFF, U+00AD y controles bidi
  # U+202A-E / U+2066-9 (Trojan Source; revisión #1355)
  # SE-453: se buscan sus bytes UTF-8 con grep en locale C, sin python3. Antes, sin python3 la
  # comprobación no corría (primero en silencio, luego como hueco PS-11:missing_tool). Todas las búsquedas
  # usan grep -a: con un byte NUL, grep imprimía «Binary file … matches» sin número de línea.
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-11" "Zero-width character (possible hidden directive)"
  done < <(LC_ALL=C grep -anE $'\xe2\x80[\x8b-\x8d\xaa-\xae]|\xe2\x81[\xa0\xa6-\xa9]|\xef\xbb\xbf|\xc2\xad' "$file" 2>/dev/null || true)

  # PS-12: Long base64 strings (>80 chars, not in code blocks with hash/commit context)
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-12" "Long base64-like string (possible encoded directive)"
  done < <(grep -anE '[A-Za-z0-9+/]{80,}={0,2}' "$file" 2>/dev/null | grep -avi 'sha\|hash\|commit\|signature\|certificate\|-----BEGIN' || true)

  # PS-13: URL-pipe-shell execution
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-13" "URL-pipe-shell execution pattern"
  done < <(grep -anE '(curl|wget)[^|]*https?[^|]*\|[[:space:]]*(bash|sh|zsh)' "$file" 2>/dev/null || true)

  # PS-14: Time-based conditional (time bomb) — epoch comparison in agent/skill prompts
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-14" "Time-based conditional (possible time bomb)"
  done < <(grep -anE 'date[[:space:]]+\+%s.*[><]=?[[:space:]]*[0-9]{10,}' "$file" 2>/dev/null || true)
}

# ── Main ──

$QUIET || printf "\n  Prompt Security Scan\n  %s\n\n" "$(printf '%.0s─' {1..40})"

if [[ ! -d "$SCAN_PATH" ]] && [[ ! -f "$SCAN_PATH" ]]; then
  echo "Error: path not found: $SCAN_PATH" >&2
  GATE_UNMEASURED_ROOT="$ROOT" gate_unmeasured_record "prompt-security-scan" unreadable
  gate_result_emit unknown "path:unreadable"
  exit 2
fi

FILE_COUNT=0
if [[ -d "$SCAN_PATH" ]]; then
  # Una sola pasada de find, con su estado: un subdirectorio que no puede recorrer deja ficheros sin escanear.
  FILE_LIST="$(mktemp)"
  trap 'rm -f "$FINDINGS_FILE" "$WARNINGS_FILE" "$FILE_LIST"' EXIT
  find "$SCAN_PATH" -name '*.md' -type f -print0 > "$FILE_LIST" 2>/dev/null || add_gap "find:unreadable"
  while IFS= read -r -d '' file; do
    ((FILE_COUNT++)) || true
    scan_file "$file"
  done < "$FILE_LIST"
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
# ${GAPS[@]+…}: con set -u, bash < 4.4 trata un array vacío como variable sin definir.
gate_result_emit "$RESULT" ${GAPS[@]+"${GAPS[@]}"}
[[ "$TOTAL_F" -gt 0 ]] && exit 1
[[ "$RESULT" == "unknown" && "${SAVIA_GATE_UNKNOWN:-warn}" == "block" ]] && exit 2
exit 0
