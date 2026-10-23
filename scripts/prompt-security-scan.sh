#!/usr/bin/env bash
set -uo pipefail
# prompt-security-scan.sh — Static analyzer for prompt injection/leakage
# Scans agent and skill prompts for dangerous patterns without LLM.
# Usage: bash scripts/prompt-security-scan.sh [--path DIR] [--fix] [--quiet]
# Exit: 0 = clean, 1 = findings, 2 = error (ruta) o unknown (algún fichero no se pudo leer)
# Contrato SE-453 (docs/rules/domain/gate-result-contract.md): la última línea de stdout es
#   gate-result: {"result":"clean|findings|unknown","gaps":[...]} (también con --quiet).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh" || { echo "ERROR: falta .claude/hooks/lib/gate-result.sh" >&2; exit 2; }

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

GAPS=()

scan_file() {
  local file="$1"

  # Un fichero que no se puede leer no es un fichero limpio: grep callaría el error (2>/dev/null).
  if [[ ! -r "$file" ]]; then
    GAPS+=("${file//:/_}:unreadable")  # gate_result_emit separa check y motivo por el primer «:»
    $QUIET || printf "  GAP   %s — no se puede leer\n" "$(basename "$file")"
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
  # SE-453: se buscan sus bytes UTF-8 con grep en locale C, sin python3. Antes, sin python3 la
  # comprobación se omitía en silencio y el fichero salía limpio.
  while IFS=: read -r num _; do
    [[ -n "$num" ]] && log_finding "HIGH" "$file" "$num" "PS-11" "Zero-width character (possible hidden directive)"
  done < <(LC_ALL=C grep -nE $'\xe2\x80[\x8b-\x8d]|\xef\xbb\xbf' "$file" 2>/dev/null || true)

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
  exit 2
fi

FILE_COUNT=0
if [[ -d "$SCAN_PATH" ]]; then
  while IFS= read -r -d '' file; do
    ((FILE_COUNT++)) || true
    scan_file "$file"
  done < <(find "$SCAN_PATH" -name '*.md' -type f -print0)
  # Un subdirectorio que find no puede recorrer deja ficheros sin escanear.
  find "$SCAN_PATH" -name '*.md' -type f >/dev/null 2>&1 || GAPS+=("${SCAN_PATH//:/_}:unreadable")
else
  FILE_COUNT=1
  scan_file "$SCAN_PATH"
fi

TOTAL_F=$(cat "$FINDINGS_FILE")
TOTAL_W=$(cat "$WARNINGS_FILE")
$QUIET || printf "\n  Scanned: %d files | Findings: %d | Warnings: %d\n\n" "$FILE_COUNT" "$TOTAL_F" "$TOTAL_W"

if [[ "$TOTAL_F" -gt 0 ]]; then
  gate_result_emit findings "${GAPS[@]}"
  exit 1
fi
if [[ ${#GAPS[@]} -gt 0 ]]; then
  gate_result_emit unknown "${GAPS[@]}"
  exit 2
fi
gate_result_emit clean
exit 0
