#!/usr/bin/env bash
# gate-result.sh — contrato de resultado de los gates (SE-453).
# Doc: docs/rules/domain/gate-result-contract.md
#
# Uso (source):
#   gate_result_emit <clean|findings|unknown> [check:reason ...]
# Imprime una línea final en stdout: gate-result: {"result":"...","gaps":[{"check":"...","reason":"..."}]}
# reason ∈ missing_tool | limit | timeout | unreadable.
# gate_unmeasured_record <gate> <reason> añade una línea a output/unmeasured-gates.jsonl (una por gate y día).

_GATE_REASONS="missing_tool limit timeout unreadable"

gate_result_emit() {
  local result="$1"; shift
  case "$result" in clean|findings|unknown) ;; *) echo "gate_result_emit: estado inválido '$result'" >&2; return 2 ;; esac
  local gaps="" g check reason
  for g in "$@"; do
    check="${g%%:*}"; reason="${g#*:}"
    [[ " $_GATE_REASONS " == *" $reason "* ]] || { echo "gate_result_emit: motivo inválido '$reason'" >&2; return 2; }
    check="${check//\\/\\\\}"; check="${check//\"/\\\"}"
    gaps+="${gaps:+,}{\"check\":\"$check\",\"reason\":\"$reason\"}"
  done
  if [[ "$result" == "unknown" && -z "$gaps" ]]; then
    echo "gate_result_emit: 'unknown' exige al menos un hueco" >&2; return 2
  fi
  printf 'gate-result: {"result":"%s","gaps":[%s]}\n' "$result" "$gaps"
}

gate_unmeasured_record() {
  local gate="$1" reason="${2:-missing_tool}" root file day
  root="${GATE_UNMEASURED_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
  file="$root/output/unmeasured-gates.jsonl"
  day="$(date +%Y-%m-%d)"
  mkdir -p "$root/output" 2>/dev/null || return 0
  if [[ -f "$file" ]] && grep -qF "\"hook\":\"$gate\",\"reason\":\"$reason\",\"day\":\"$day\"" "$file" 2>/dev/null; then
    return 0
  fi
  printf '{"ts":"%s","hook":"%s","reason":"%s","day":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$gate" "$reason" "$day" >> "$file" 2>/dev/null || true
}
