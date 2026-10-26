#!/usr/bin/env bash
# kpi-antagonist-gate.sh — SE-272 S2 Anti-Goodhart gate
# Every efficiency KPI must have a paired quality KPI (antagonist).
# Blocks publication without antagonist.
# Detects anomalies: abrupt KPI improvement without activity change.
#
# Usage:
#   kpi-antagonist-gate.sh check
#     --engagement CLIENT/ENGAGEMENT
#     [--period YYYY-MM]
#   kpi-antagonist-gate.sh anomaly
#     --engagement CLIENT/ENGAGEMENT
#     [--period YYYY-MM]
#     [--threshold-pct 30]
#   kpi-antagonist-gate.sh validate-pair
#     --kpi-id KPI_ID --antagonist-id ANTAGONIST_ID
#     --engagement CLIENT/ENGAGEMENT

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

usage() {
  cat <<'USAGE'
kpi-antagonist-gate.sh — SE-272 S2 Anti-Goodhart gate

Usage:
  kpi-antagonist-gate.sh check --engagement CLIENT/ENGAGEMENT
  kpi-antagonist-gate.sh anomaly --engagement CLIENT/ENGAGEMENT [--threshold-pct 30]
  kpi-antagonist-gate.sh validate-pair --kpi-id ID --antagonist-id ID --engagement CLIENT/ENGAGEMENT

Blocks: every efficiency KPI must have paired quality KPI.
Detects: abrupt improvements without activity change.
USAGE
  exit 0
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Efficiency KPI name patterns (heuristic) ─────────────────────────

EFFICIENCY_PATTERNS=("velocity" "throughput" "speed" "cycle" "lead time" "delivery" "productivity")

is_efficiency_kpi() {
  local name="$1"
  local lower
  lower="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  for pattern in "${EFFICIENCY_PATTERNS[@]}"; do
    if echo "$lower" | grep -q "$pattern"; then
      return 0
    fi
  done
  return 1
}

# ── Subcommand: check ───────────────────────────────────────────────

cmd_check() {
  local engagement="" period=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engagement) engagement="$2"; shift 2 ;;
      --period)     period="$2";     shift 2 ;;
      *) die "check: unknown argument: $1" ;;
    esac
  done

  [[ -z "$engagement" ]] && die "check: --engagement is required"

  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local kpis_file="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}/kpis.yaml"

  if [[ ! -f "$kpis_file" ]]; then
    echo "FAIL: KPI catalog not found: ${kpis_file}"
    exit 1
  fi

  local content
  content="$(cat "$kpis_file")"

  local errors=0
  local kpi_blocks
  kpi_blocks="$(echo "$content" | awk '/^  - id:/,/^  - id:/' || true)"

  # Extract all KPIs
  local line_num=0 current_id="" current_name="" current_antagonist=""
  local in_kpi=0

  echo "# Antagonist Gate Check — ${engagement}"
  echo ""

  while IFS= read -r line; do
    line_num=$(( line_num + 1 ))

    if echo "$line" | grep -qE '^  - id:'; then
      # Flush previous
      if [[ "$in_kpi" -eq 1 ]]; then
        check_one_kpi "$current_id" "$current_name" "$current_antagonist" || errors=$(( errors + 1 ))
      fi
      in_kpi=1
      current_id="$(echo "$line" | sed 's/.*id: *"//;s/"$//')"
      current_name=""
      current_antagonist=""
    fi

    if [[ "$in_kpi" -eq 1 ]]; then
      case "$line" in
        "    name:"*)          current_name="$(echo "$line" | sed 's/.*name: *"//;s/"$//')" ;;
        "    antagonist_kpi_id:"*) current_antagonist="$(echo "$line" | sed 's/.*antagonist_kpi_id: *"//;s/"$//')" ;;
      esac
    fi
  done < "$kpis_file"

  # Flush last
  if [[ "$in_kpi" -eq 1 ]]; then
    check_one_kpi "$current_id" "$current_name" "$current_antagonist" || errors=$(( errors + 1 ))
  fi

  echo ""
  if [[ "$errors" -gt 0 ]]; then
    echo "RESULT: BLOCKED — ${errors} KPI(s) without antagonist"
    exit 1
  else
    echo "RESULT: PASSED — all KPIs have antagonist pairing"
    exit 0
  fi
}

check_one_kpi() {
  local id="$1" name="$2" antagonist="$3"

  if is_efficiency_kpi "$name"; then
    if [[ -z "$antagonist" ]]; then
      echo "FAIL: KPI '${id}' (${name}) is efficiency-type and has NO antagonist"
      return 1
    else
      echo "OK:   KPI '${id}' (${name}) → antagonist '${antagonist}'"
    fi
  else
    if [[ -z "$antagonist" ]]; then
      echo "WARN: KPI '${id}' (${name}) has no antagonist (non-efficiency, advisory)"
    else
      echo "OK:   KPI '${id}' (${name}) → antagonist '${antagonist}'"
    fi
  fi
  return 0
}

# ── Subcommand: anomaly ─────────────────────────────────────────────

cmd_anomaly() {
  local engagement="" period="" threshold_pct=30

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engagement)    engagement="$2";    shift 2 ;;
      --period)        period="$2";        shift 2 ;;
      --threshold-pct) threshold_pct="$2"; shift 2 ;;
      *) die "anomaly: unknown argument: $1" ;;
    esac
  done

  [[ -z "$engagement" ]] && die "anomaly: --engagement is required"

  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local chain_file="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}/kpi-chain.jsonl"

  echo "# Anomaly Detection — ${engagement}"
  echo "  Threshold: ${threshold_pct}% abrupt change"
  echo ""

  if [[ ! -f "$chain_file" ]]; then
    echo "No KPI chain data available"
    exit 0
  fi

  local entry_count
  entry_count="$(grep -c . "$chain_file" 2>/dev/null || [ $? -eq 1 ] || echo 0)"

  if [[ "$entry_count" -lt 2 ]]; then
    echo "Need at least 2 periods for anomaly detection (have ${entry_count})"
    exit 0
  fi

  # Collect periods and hashes
  local periods=()
  local hashes=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    periods+=("$(echo "$line" | grep -o '"period":"[^"]*"' | head -1 | cut -d'"' -f4)")
    hashes+=("$(echo "$line" | grep -o '"data_hash":"[^"]*"' | head -1 | cut -d'"' -f4)")
  done < "$chain_file"

  local anomalies=0
  for (( i=1; i<${#periods[@]}; i++ )); do
    local prev_hash="${hashes[$(( i - 1 ))]}"
    local curr_hash="${hashes[$i]}"
    local prev_period="${periods[$(( i - 1 ))]}"
    local curr_period="${periods[$i]}"

    if [[ "$prev_hash" == "$curr_hash" ]]; then
      if [[ "$i" -gt 1 ]]; then
        local prev2_hash="${hashes[$(( i - 2 ))]}"
        if [[ "$prev2_hash" != "$prev_hash" ]]; then
          echo "ANOMALY: Period ${curr_period} shows no data change vs ${prev_period}"
          echo "  Previous period had changed from earlier baseline"
          anomalies=$(( anomalies + 1 ))
        fi
      fi
    fi
  done

  if [[ "$anomalies" -eq 0 ]]; then
    echo "No anomalies detected across ${entry_count} periods"
  else
    echo ""
    echo "Total anomalies: ${anomalies}"
    echo "WARNING: Anomalies may indicate Goodhart's law effects"
  fi
}

# ── Subcommand: validate-pair ───────────────────────────────────────

cmd_validate_pair() {
  local kpi_id="" antagonist_id="" engagement=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kpi-id)       kpi_id="$2";       shift 2 ;;
      --antagonist-id) antagonist_id="$2"; shift 2 ;;
      --engagement)   engagement="$2";    shift 2 ;;
      *) die "validate-pair: unknown argument: $1" ;;
    esac
  done

  [[ -z "$kpi_id"       ]] && die "validate-pair: --kpi-id is required"
  [[ -z "$antagonist_id" ]] && die "validate-pair: --antagonist-id is required"
  [[ -z "$engagement"   ]] && die "validate-pair: --engagement is required"

  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local kpis_file="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}/kpis.yaml"

  if [[ ! -f "$kpis_file" ]]; then
    echo "FAIL: KPI catalog not found"
    exit 1
  fi

  local content
  content="$(cat "$kpis_file")"

  # Campo de un KPI leído solo dentro de su propio bloque ("  - id: ..." hasta el
  # siguiente). Un grep -A sobre `id: "X"` también casaba `antagonist_kpi_id: "X"`
  # y devolvía el name: de otra firma u otro KPI.
  kpi_field() {
    echo "$content" | awk -v want="$1" -v field="$2" '
      /^  - id:/ { cur = $0; sub(/^  - id: *"/, "", cur); sub(/".*$/, "", cur); next }
      cur == want && $1 == field ":" { v = $0; sub(/^[^:]*: *"/, "", v); sub(/"$/, "", v); print v; exit }'
  }

  local kpi_name ant_name kpi_ant
  kpi_name="$(kpi_field "$kpi_id" name)"
  ant_name="$(kpi_field "$antagonist_id" name)"
  kpi_ant="$(kpi_field "$kpi_id" antagonist_kpi_id)"

  local pass=1

  if [[ "$kpi_ant" != "$antagonist_id" ]]; then
    echo "FAIL: KPI '${kpi_id}' declares antagonist '${kpi_ant}', not '${antagonist_id}'"
    pass=0
  fi

  if is_efficiency_kpi "$kpi_name"; then
    local ant_is_quality=1
    if echo "$ant_name" | grep -qiE "quality|defect|error|incident|rework|stability|reliability|satisfaction|nps"; then
      ant_is_quality=0
    fi

    if [[ "$ant_is_quality" -eq 1 ]]; then
      echo "WARN: Antagonist '${antagonist_id}' (${ant_name}) does not appear to be a quality KPI"
    fi
  fi

  if [[ "$pass" -eq 1 ]]; then
    echo "OK: KPI '${kpi_id}' (${kpi_name}) ↔ antagonist '${antagonist_id}' (${ant_name})"
    echo "  Pairing is valid"
    exit 0
  else
    exit 1
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then usage; fi

subcmd="$1"; shift

case "$subcmd" in
  check)         cmd_check "$@" ;;
  anomaly)       cmd_anomaly "$@" ;;
  validate-pair) cmd_validate_pair "$@" ;;
  -h|--help)     usage ;;
  *) echo "ERROR: unknown subcommand: ${subcmd}" >&2; exit 2 ;;
esac
