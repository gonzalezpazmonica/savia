#!/usr/bin/env bash
# gate-result.sh — contrato de resultado de los gates (SE-453). Librería compartida de scripts y hooks.
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
  root="${GATE_UNMEASURED_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}}"
  file="$root/output/unmeasured-gates.jsonl"
  day="$(date +%Y-%m-%d)"
  mkdir -p "$root/output" 2>/dev/null || return 0
  if [[ -f "$file" ]] && grep -qF "\"hook\":\"$gate\",\"reason\":\"$reason\",\"day\":\"$day\"" "$file" 2>/dev/null; then
    return 0
  fi
  printf '{"ts":"%s","hook":"%s","reason":"%s","day":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$gate" "$reason" "$day" >> "$file" 2>/dev/null || true
}

# gate_unknown_check — contador de gates en «unknown» frente al baseline (D3).
# Uso directo: bash .claude/hooks/lib/gate-result.sh check
# Cuenta los gates distintos con línea de hoy en output/unmeasured-gates.jsonl y los compara con
# config/gate-unknown-baseline.txt (solo puede bajar). Primer ciclo: aviso (WARN, exit 0).
# GATE_UNKNOWN_ENFORCE=1 lo convierte en fallo. Salida: una línea PASS/WARN/FAIL.
gate_unknown_check() {
  local root log baseline_file day baseline hooks count
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  log="${GATE_UNMEASURED_LOG:-$root/output/unmeasured-gates.jsonl}"
  baseline_file="${GATE_UNKNOWN_BASELINE:-$root/config/gate-unknown-baseline.txt}"
  day="$(date +%Y-%m-%d)"

  if [[ ! -f "$baseline_file" ]] || ! [[ "$(tr -d '[:space:]' < "$baseline_file")" =~ ^[0-9]+$ ]]; then
    echo "FAIL gate-unknown: baseline ausente o no numérico ($baseline_file)"
    return 1
  fi
  baseline="$(tr -d '[:space:]' < "$baseline_file")"

  hooks=""
  if [[ -f "$log" ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
      echo "WARN gate-unknown: python3 ausente, no se puede leer $log (no medido)"
      return 0
    fi
    hooks="$(python3 -c '
import json, sys
seen = set()
for n, line in enumerate(open(sys.argv[1]), 1):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        print("INVALID:%d" % n)
        sys.exit(0)
    if d.get("day") == sys.argv[2] and d.get("hook"):
        seen.add(d["hook"])
print(",".join(sorted(seen)))
' "$log" "$day")"
  fi
  if [[ "$hooks" == INVALID:* ]]; then
    echo "FAIL gate-unknown: línea ${hooks#INVALID:} de $log no es JSON"
    return 1
  fi

  count=0
  [[ -n "$hooks" ]] && count="$(printf '%s\n' "$hooks" | tr ',' '\n' | wc -l)"
  if [[ "$count" -le "$baseline" ]]; then
    echo "PASS gate-unknown: $count gates en unknown (baseline $baseline)"
    return 0
  fi
  if [[ "${GATE_UNKNOWN_ENFORCE:-0}" == "1" ]]; then
    echo "FAIL gate-unknown: $count gates en unknown (baseline $baseline): $hooks"
    return 1
  fi
  echo "WARN gate-unknown: $count gates en unknown (baseline $baseline): $hooks (ciclo de aviso, D3)"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "check" ]]; then
  set -uo pipefail
  gate_unknown_check
  exit $?
fi
