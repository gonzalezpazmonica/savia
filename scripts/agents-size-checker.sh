#!/usr/bin/env bash
# agents-size-checker.sh — SE-098: List agents by size, emit WARN/FAIL per Rule #22
set -uo pipefail
#
# Rule #22 hard limits:
#   WARN  > 200 lines  (approaching problematic territory)
#   FAIL  > 400 lines  (hard limit — must be split)
#   SLA   > 4096 bytes (soft SLA from agent-size-audit.sh)
#
# Usage:
#   bash scripts/agents-size-checker.sh [--json] [--quiet]
#
# Exit codes:
#   0 — no FAIL violations
#   1 — one or more FAIL violations (>400 lines)
#   2 — usage error, or agents directory missing (fail-closed: no PASS without data)
#
# Ref: SE-098, Rule #22, docs/propuestas/SE-098-agents-oversized-top5.md

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AGENTS_DIR="$REPO_ROOT/.opencode/agents"
SLA_BYTES=4096
WARN_LINES=200
FAIL_LINES=400

JSON_MODE=0
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)   JSON_MODE=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--json] [--quiet]"
      echo "  --json   Output JSON instead of table"
      echo "  --quiet  Suppress table, only exit code"
      exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$AGENTS_DIR" ]]; then
  echo "ERROR: agents directory not found: $AGENTS_DIR" >&2
  exit 2
fi

json_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }

# ── Collect agent data ──────────────────────────────────────────────────────

declare -a AGENTS=()
declare -a LINES_ARR=()
declare -a BYTES_ARR=()
declare -a STATUS_ARR=()

fail_count=0
warn_count=0
total=0

while IFS= read -r agent_file; do
  [[ -f "$agent_file" ]] || continue
  name=$(basename "$agent_file" .md)
  lines=$(wc -l < "$agent_file")
  bytes=$(wc -c < "$agent_file")

  status="OK"
  if [[ "$lines" -gt "$FAIL_LINES" ]]; then
    status="FAIL"
    fail_count=$((fail_count + 1))
  elif [[ "$lines" -gt "$WARN_LINES" ]]; then
    status="WARN"
    warn_count=$((warn_count + 1))
  elif [[ "$bytes" -gt "$SLA_BYTES" ]]; then
    status="SLA_WARN"
    warn_count=$((warn_count + 1))
  fi

  AGENTS+=("$name")
  LINES_ARR+=("$lines")
  BYTES_ARR+=("$bytes")
  STATUS_ARR+=("$status")
  total=$((total + 1))
done < <(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' | sort)

# ── Sort by lines descending (insertion sort on parallel arrays) ─────────────

n=${#AGENTS[@]}
for (( i=1; i<n; i++ )); do
  key_lines=${LINES_ARR[$i]}
  key_bytes=${BYTES_ARR[$i]}
  key_name=${AGENTS[$i]}
  key_status=${STATUS_ARR[$i]}
  j=$((i - 1))
  while [[ $j -ge 0 ]] && [[ ${LINES_ARR[$j]} -lt $key_lines ]]; do
    LINES_ARR[$((j+1))]=${LINES_ARR[$j]}
    BYTES_ARR[$((j+1))]=${BYTES_ARR[$j]}
    AGENTS[$((j+1))]=${AGENTS[$j]}
    STATUS_ARR[$((j+1))]=${STATUS_ARR[$j]}
    j=$((j - 1))
  done
  LINES_ARR[$((j+1))]=$key_lines
  BYTES_ARR[$((j+1))]=$key_bytes
  AGENTS[$((j+1))]=$key_name
  STATUS_ARR[$((j+1))]=$key_status
done

# ── Output ──────────────────────────────────────────────────────────────────

if [[ "$JSON_MODE" -eq 1 ]]; then
  printf '{\n'
  printf '  "summary": {"total": %d, "fail": %d, "warn": %d, "sla_bytes": %d, "warn_lines": %d, "fail_lines": %d},\n' \
    "$total" "$fail_count" "$warn_count" "$SLA_BYTES" "$WARN_LINES" "$FAIL_LINES"
  printf '  "agents": [\n'
  for (( i=0; i<n; i++ )); do
    comma=","
    [[ $((i+1)) -eq $n ]] && comma=""
    printf '    {"name": "%s", "lines": %d, "bytes": %d, "status": "%s"}%s\n' \
      "$(json_escape "${AGENTS[$i]}")" "${LINES_ARR[$i]}" "${BYTES_ARR[$i]}" "${STATUS_ARR[$i]}" "$comma"
  done
  printf '  ]\n}\n'
elif [[ "$QUIET" -eq 0 ]]; then
  printf '%-42s %6s %7s  %s\n' "AGENT" "LINES" "BYTES" "STATUS"
  printf '%s\n' "$(printf '%.0s-' {1..65})"
  for (( i=0; i<n; i++ )); do
    status="${STATUS_ARR[$i]}"
    flag=""
    case "$status" in
      FAIL)     flag=" !! FAIL (>$FAIL_LINES lines — must split)" ;;
      WARN)     flag=" !  WARN (>$WARN_LINES lines)" ;;
      SLA_WARN) flag=" ~  SLA_WARN (>${SLA_BYTES}B)" ;;
    esac
    printf '%-42s %6d %7d  %s%s\n' \
      "${AGENTS[$i]}" "${LINES_ARR[$i]}" "${BYTES_ARR[$i]}" "$status" "$flag"
  done
  printf '%s\n' "$(printf '%.0s-' {1..65})"
  printf 'Total: %d agents | FAIL: %d | WARN: %d\n' "$total" "$fail_count" "$warn_count"
  printf 'Thresholds: WARN >%d lines, FAIL >%d lines, SLA_WARN >%dB\n' "$WARN_LINES" "$FAIL_LINES" "$SLA_BYTES"
fi

# ── Exit code ────────────────────────────────────────────────────────────────
if [[ "$fail_count" -gt 0 ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "" && echo "FAIL: $fail_count agent(s) exceed $FAIL_LINES lines (Rule #22 hard limit)" >&2
  exit 1
fi
exit 0
