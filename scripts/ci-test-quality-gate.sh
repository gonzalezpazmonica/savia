#!/usr/bin/env bash
# ci-test-quality-gate.sh — CI gate: test quality + coverage
# SPEC-055: Blocks CI if any test scores < threshold
# SPEC-200 (wired): when SAVIA_QUALITY_GATE_ADAPTIVE=on, uses adaptive
# threshold proportional to score distribution instead of fixed 80.
#
# Modes:
#   SAVIA_QUALITY_GATE_ADAPTIVE=off (default) — fixed threshold 80 (SPEC-055).
#   SAVIA_QUALITY_GATE_ADAPTIVE=warn          — compute adaptive but still
#       gate on fixed 80; emit advisory diff to stderr.
#   SAVIA_QUALITY_GATE_ADAPTIVE=on            — use adaptive threshold.
#
# Tunables:
#   SAVIA_QUALITY_GATE_FIXED_MIN=80
#   SAVIA_QUALITY_GATE_FLOOR=60
#   SAVIA_QUALITY_GATE_CEIL=90
#
#
# SE-456: ratchet de vacuidad (tests que no pueden fallar). Bloqueante: más
# hallazgos que .ci-baseline/test-vacuity.count hace salir con 1. La parte de
# puntuación sigue siendo solo aviso (SPEC-200).
#   SAVIA_VACUITY_ROOT      raíz a escanear (por defecto, el repo)
#   SAVIA_VACUITY_BASELINE  fichero de línea base (por defecto, .ci-baseline/test-vacuity.count)
#
# Usage: bash scripts/ci-test-quality-gate.sh [--vacuity-only]
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=true

# SE-456: devuelve 0 si los hallazgos no superan la línea base; 1 si la superan
# o si no se puede medir (fallo cerrado).
vacuity_ratchet() {
  local root="${SAVIA_VACUITY_ROOT:-$DIR/..}"
  local baseline="${SAVIA_VACUITY_BASELINE:-$DIR/../.ci-baseline/test-vacuity.count}"
  local ids="${SAVIA_VACUITY_IDS:-${baseline%.count}.findings}"
  local scan count base new
  if [[ ! -f "$baseline" ]]; then
    echo "  Vacuidad: sin línea base en $baseline (fallo cerrado)"
    return 1
  fi
  base=$(tr -dc '0-9' < "$baseline")
  if ! scan=$(python3 "$DIR/test-auditor-engine.py" --vacuity-scan "$root"); then
    echo "  Vacuidad: el detector no pudo medir (fallo cerrado)"
    return 1
  fi
  count=$(printf '%s' "$scan" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])") || return 1
  if [[ -z "$base" || -z "$count" ]]; then
    echo "  Vacuidad: línea base o recuento ilegibles (fallo cerrado)"
    return 1
  fi
  # Identidad: hallazgos (fichero, test, tipo) que no estaban en la línea base. Arreglar uno y añadir otro
  # deja el recuento igual pero no pasa. Sin fichero de identidades solo vale el recuento.
  new=$(printf '%s' "$scan" | python3 -c "
import collections, json, sys
ids = sys.argv[1]
cur = collections.Counter((f['file'], f['test'], f['kind']) for f in json.load(sys.stdin)['findings'])
try:
    base = collections.Counter(tuple(l.rstrip('\n').split('\t')) for l in open(ids) if l.strip())
except OSError:
    sys.exit(0)
for (file, test, kind), n in sorted((cur - base).items()):
    print(f'    {kind} {file}  @test \"{test}\"' + (f' (+{n})' if n > 1 else ''))
" "$ids") || { echo "  Vacuidad: no se pudo comparar identidades (fallo cerrado)"; return 1; }
  if [[ -n "$new" ]]; then
    echo "  Vacuidad: hallazgos que no estaban en la línea base (tests que no pueden fallar):"
    printf '%s\n' "$new"
    echo "  Regla: docs/rules/domain/test-evidence-criteria.md"
    return 1
  fi
  if (( count > base )); then
    echo "  Vacuidad: $count > línea base $base sin hallazgos nuevos identificables (fallo cerrado)"
    return 1
  fi
  if (( count < base )); then
    echo "  Vacuidad: $count < línea base $base — mejora; bajar la línea base: bash scripts/ci-test-quality-gate.sh --update-vacuity-baseline"
  else
    echo "  Vacuidad: $count = línea base $base"
  fi
  return 0
}

if [[ "${1:-}" == "--update-vacuity-baseline" ]]; then
  root="${SAVIA_VACUITY_ROOT:-$DIR/..}"
  baseline="${SAVIA_VACUITY_BASELINE:-$DIR/../.ci-baseline/test-vacuity.count}"
  scan=$(python3 "$DIR/test-auditor-engine.py" --vacuity-scan "$root") || { echo "detector caído"; exit 2; }
  printf '%s' "$scan" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])" > "$baseline"
  printf '%s' "$scan" | python3 -c "
import json, sys
for f in json.load(sys.stdin)['findings']:
    print('\t'.join((f['file'], f['test'], f['kind'])))" | sort > "${baseline%.count}.findings"
  echo "Línea base actualizada: $(cat "$baseline") hallazgos"
  exit 0
fi

if [[ "${1:-}" == "--vacuity-only" ]]; then
  vacuity_ratchet
  exit $?
fi

ADAPTIVE_MODE="${SAVIA_QUALITY_GATE_ADAPTIVE:-off}"
FIXED_MIN="${SAVIA_QUALITY_GATE_FIXED_MIN:-80}"
FLOOR="${SAVIA_QUALITY_GATE_FLOOR:-60}"
CEIL="${SAVIA_QUALITY_GATE_CEIL:-90}"

echo "=== CI Test Quality Gate (SPEC-055 + SPEC-200 adaptive) ==="
echo "  Mode: $ADAPTIVE_MODE  Fixed-min: $FIXED_MIN  Floor: $FLOOR  Ceil: $CEIL"
echo ""

# Step 1: Audit test quality
echo "Step 1/2: Auditing test quality..."
AUDIT=$(bash "$DIR/test-auditor.sh" --all --json 2>&1) || true
TOTAL=$(echo "$AUDIT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_files',0))" 2>/dev/null || echo "0")

# Compute the threshold to use this run
THRESHOLD="$FIXED_MIN"
ADAPTIVE_RESULT=""
if [[ "$ADAPTIVE_MODE" != "off" ]]; then
  # Extract all scores from the audit results
  SCORES=$(echo "$AUDIT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
scores = [str(r.get('total', 0)) for r in data.get('results', [])]
print(' '.join(scores))
" 2>/dev/null)

  if [[ -n "$SCORES" ]]; then
    ADAPTIVE_RESULT=$(python3 "$DIR/quality-gate-adaptive.py" \
        --scores $SCORES \
        --fixed-min "$FIXED_MIN" --floor "$FLOOR" --ceil "$CEIL" --json 2>/dev/null || echo "{}")
    NEW_THRESHOLD=$(echo "$ADAPTIVE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('threshold', $FIXED_MIN))" 2>/dev/null || echo "$FIXED_MIN")
    STRATEGY=$(echo "$ADAPTIVE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('strategy', 'unknown'))" 2>/dev/null || echo "unknown")
    MEAN=$(echo "$ADAPTIVE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('metrics', {}).get('mean', 0))" 2>/dev/null || echo "0")
    STDDEV=$(echo "$ADAPTIVE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('metrics', {}).get('stddev', 0))" 2>/dev/null || echo "0")

    echo "  Adaptive threshold: $NEW_THRESHOLD (strategy=$STRATEGY mean=$MEAN stddev=$STDDEV)"

    if [[ "$ADAPTIVE_MODE" == "on" ]]; then
      THRESHOLD="$NEW_THRESHOLD"
    elif [[ "$ADAPTIVE_MODE" == "warn" ]]; then
      # Show advisory but still gate on fixed
      if [[ "$NEW_THRESHOLD" != "$FIXED_MIN" ]]; then
        echo "  [WARN] Adaptive would use $NEW_THRESHOLD; gating on fixed $FIXED_MIN (SAVIA_QUALITY_GATE_ADAPTIVE=warn)" >&2
      fi
    fi

    # Telemetry
    LOG_FILE="output/quality-gate-history.jsonl"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    if command -v jq >/dev/null 2>&1; then
      jq -nc \
        --arg ts "$(date -Iseconds 2>/dev/null || date)" \
        --arg mode "$ADAPTIVE_MODE" \
        --arg threshold "$THRESHOLD" \
        --arg strategy "$STRATEGY" \
        --arg mean "$MEAN" \
        --arg stddev "$STDDEV" \
        --arg total "$TOTAL" \
        '{ts:$ts, mode:$mode, threshold:($threshold|tonumber? // 0), strategy:$strategy, mean:($mean|tonumber? // 0), stddev:($stddev|tonumber? // 0), total_tests:($total|tonumber? // 0)}' \
        >> "$LOG_FILE" 2>/dev/null || true
    fi
  fi
fi

# Filter failed tests against the threshold
FAILED=$(echo "$AUDIT" | python3 -c "
import json, sys
threshold = $THRESHOLD
data = json.load(sys.stdin)
failed = [r for r in data.get('results', []) if r.get('total', 0) < threshold]
print(len(failed))
" 2>/dev/null || echo "0")

echo "  Audited: $TOTAL files, $FAILED below threshold ($THRESHOLD)"

if [[ "$FAILED" -gt 0 ]]; then
  echo "$AUDIT" | python3 -c "
import json, sys
threshold = $THRESHOLD
data = json.load(sys.stdin)
for r in data.get('results', []):
    if r.get('total', 0) < threshold:
        print(f'    {r["file"]}: {r["total"]}/100 (threshold {threshold})')
" 2>/dev/null
  PASS=false
fi

# Step 2: Coverage
echo "Step 2/2: Checking coverage..."
COV=$(bash "$DIR/test-coverage-checker.sh" --json 2>&1)
COV_PCT=$(echo "$COV" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coverage_percent', 0))" 2>/dev/null || echo "0")
echo "  Coverage: $COV_PCT%"

# Step 3: Vacuity ratchet (SE-456) — bloqueante
echo "Step 3: Vacuity ratchet (SE-456)..."
VACUITY_OK=true
vacuity_ratchet || VACUITY_OK=false

echo ""
if $PASS; then
  echo "RESULT: PASS"
else
  echo "RESULT: WARN — tests below quality threshold ($THRESHOLD) [advisory only]"
fi
if ! $VACUITY_OK; then
  echo "RESULT: FAIL — tests que no pueden fallar por encima de la línea base (SE-456)"
  exit 1
fi
exit 0
