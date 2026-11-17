#!/usr/bin/env bash
# test-auditor-sweep.sh — SE-039 Slice 1 global BATS test audit sweep.
#
# Ejecuta scripts/test-auditor.sh sobre TODOS los ficheros .bats en tests/
# y produce:
#   - Ranking ordenado por score (low → high)
#   - Bottom-N tests identificados (candidatos a remediación)
#   - Métricas agregadas: score medio, % ≥80, % certificados
#   - JSON export para tracking histórico
#
# NO remedia tests — solo audita. Remediación es Slice 2.
#
# Usage:
#   test-auditor-sweep.sh
#   test-auditor-sweep.sh --bottom 10 --json
#   test-auditor-sweep.sh --filter "test-slm-*"
#
# Exit codes:
#   0 — ≥95% de tests con score ≥80 (objetivo SE-039)
#   1 — <95% de tests con score ≥80 (remediación necesaria)
#   2 — usage error
#
# Ref: SE-039, SPEC-055 test-auditor
# Safety: read-only on repo. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BOTTOM=10
FILTER="test-*.bats"
JSON=0
THRESHOLD=80
TARGET_COMPLIANCE_PCT=95

usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --bottom N      Show bottom N tests (default 10)
  --filter GLOB   Filter tests (default "test-*.bats")
  --threshold N   Certification threshold (default 80)
  --compliance N  Target compliance % (default 95)
  --json          JSON output

Audit SWEEP over all tests/*.bats — produces ranking + bottom-N + metrics.
Ref: SE-039 §Objective — ≥95% tests with score ≥threshold.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bottom) BOTTOM="$2"; shift 2 ;;
    --filter) FILTER="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --compliance) TARGET_COMPLIANCE_PCT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if ! [[ "$BOTTOM" =~ ^[0-9]+$ ]] || [[ "$BOTTOM" -lt 1 ]]; then
  echo "ERROR: --bottom must be positive integer" >&2; exit 2
fi

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [[ "$THRESHOLD" -gt 100 ]]; then
  echo "ERROR: --threshold must be 0-100" >&2; exit 2
fi

AUDITOR="$PROJECT_ROOT/scripts/test-auditor.sh"
[[ ! -x "$AUDITOR" ]] && { echo "ERROR: test-auditor.sh not executable at $AUDITOR" >&2; exit 2; }

# Collect matching tests
TEST_FILES=()
while IFS= read -r f; do
  [[ -f "$f" ]] && TEST_FILES+=("$f")
done < <(find "$PROJECT_ROOT/tests" -name "$FILTER" -type f 2>/dev/null | sort)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  if [[ "$JSON" -eq 1 ]]; then
    echo '{"verdict":"EMPTY","files":0,"compliance_pct":0,"message":"no matching test files"}'
  else
    echo "No matching test files (filter: $FILTER)"
  fi
  exit 1
fi

# Audit each file
declare -a RESULTS=()
total=0
compliant=0

for f in "${TEST_FILES[@]}"; do
  total=$((total + 1))
  rel=${f#$PROJECT_ROOT/}
  # Run auditor, extract score (robust to missing jq)
  # Auditor JSON uses "total" field, not "score".
  # El auditor sale con 1 bajo su umbral pero imprime su JSON igualmente: el respaldo solo
  # entra si no imprimió nada (con `|| echo` se concatenaban dos documentos y el score salía "68\n0").
  output=$(bash "$AUDITOR" "$f" 2>/dev/null)
  [[ -z "$output" ]] && output='{"total":0}'
  if command -v jq >/dev/null 2>&1; then
    score=$(echo "$output" | jq -r '.total // 0' 2>/dev/null | head -1)
  else
    score=$(echo "$output" | grep -oE '"total"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)
  fi
  [[ "$score" =~ ^[0-9]+$ ]] || score=0
  [[ "$score" -ge "$THRESHOLD" ]] && compliant=$((compliant + 1))
  RESULTS+=("$score|$rel")
done

# Sort ascending by score (low to high)
IFS=$'\n' sorted=($(printf '%s\n' "${RESULTS[@]}" | sort -t'|' -k1n))
unset IFS

# Compliance percent
if [[ "$total" -eq 0 ]]; then
  compliance=0
else
  compliance=$(( (compliant * 100) / total ))
fi

VERDICT="PASS"
EXIT_CODE=0
if [[ "$compliance" -lt "$TARGET_COMPLIANCE_PCT" ]]; then
  VERDICT="FAIL"
  EXIT_CODE=1
fi

if [[ "$JSON" -eq 1 ]]; then
  bottom_json=""
  n=0
  for r in "${sorted[@]}"; do
    [[ $n -ge $BOTTOM ]] && break
    score="${r%%|*}"
    path="${r#*|}"
    bottom_json+="{\"score\":$score,\"file\":\"$path\"},"
    n=$((n + 1))
  done
  bottom_json="[${bottom_json%,}]"
  cat <<JSON
{"verdict":"$VERDICT","files":$total,"compliant":$compliant,"compliance_pct":$compliance,"target_pct":$TARGET_COMPLIANCE_PCT,"threshold":$THRESHOLD,"bottom":$bottom_json}
JSON
else
  echo "=== SE-039 Test Auditor Sweep ==="
  echo ""
  echo "Files scanned:     $total"
  echo "Compliant (≥$THRESHOLD): $compliant"
  echo "Compliance:        ${compliance}% (target ≥${TARGET_COMPLIANCE_PCT}%)"
  echo ""
  echo "Bottom $BOTTOM (lowest scores — remediation candidates):"
  n=0
  for r in "${sorted[@]}"; do
    [[ $n -ge $BOTTOM ]] && break
    score="${r%%|*}"
    path="${r#*|}"
    printf "  %3d  %s\n" "$score" "$path"
    n=$((n + 1))
  done
  echo ""
  echo "VERDICT: $VERDICT"
  if [[ "$VERDICT" == "FAIL" ]]; then
    echo ""
    echo "Remediation plan (SE-039 Slice 2):"
    echo "  1. Target bottom-$BOTTOM files above"
    echo "  2. Apply feedback_test_excellence_patterns.md (memory)"
    echo "  3. Re-audit + track progress in ranking"
  fi
fi

exit $EXIT_CODE
