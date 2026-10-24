#!/usr/bin/env bash
# pipeline-engine.sh — Orchestrate pipeline execution from YAML definition
# Usage: ./scripts/pipeline-engine.sh <pipeline.yaml> [--dry-run]
# ─────────────────────────────────────────────────────────────────
set -uo pipefail
cat /dev/stdin > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE_RUNNER="$SCRIPT_DIR/pipeline-stage-runner.sh"

PIPELINE_FILE="${1:-}"
DRY_RUN=false
shift 2>/dev/null || true
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

[ -z "$PIPELINE_FILE" ] && { echo "Usage: $0 <pipeline.yaml> [--dry-run]" >&2; exit 1; }
[ ! -f "$PIPELINE_FILE" ] && { echo "Error: Pipeline not found: $PIPELINE_FILE" >&2; exit 1; }

# ── Parse pipeline name ──
PIPELINE_NAME=$(grep '^name:' "$PIPELINE_FILE" | head -1 | sed 's/name: *"//;s/"$/;s/^ *//')
RUN_ID=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="output/pipeline-runs/${RUN_ID}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pipeline: ${PIPELINE_NAME:-$(basename "$PIPELINE_FILE")}"
echo "Run ID:   $RUN_ID"
echo "Output:   $OUTPUT_DIR/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Extract stages (simple YAML parser) ──
STAGES=()
STAGE_COMMANDS=()
STAGE_AGENTS=()
STAGE_INPUTS=()
STAGE_TIMEOUTS=()
STAGE_DEPS=()

current_stage=""
while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
    current_stage="${BASH_REMATCH[1]}"
    STAGES+=("$current_stage")
    STAGE_COMMANDS+=("")
    STAGE_AGENTS+=("")
    STAGE_INPUTS+=("")
    STAGE_TIMEOUTS+=("300")
    STAGE_DEPS+=("")
  elif [ -n "$current_stage" ]; then
    local_val=$(echo "$line" | sed 's/^[[:space:]]*//')
    idx=$((${#STAGES[@]} - 1))
    case "$local_val" in
      command:*) STAGE_COMMANDS[$idx]=$(echo "$local_val" | sed 's/command: *"//;s/"$//') ;;
      agent:*) STAGE_AGENTS[$idx]=$(echo "$local_val" | sed 's/agent: *//') ;;
      input:*) STAGE_INPUTS[$idx]=$(echo "$local_val" | sed 's/input: *"//;s/"$//') ;;
      timeout:*) STAGE_TIMEOUTS[$idx]=$(echo "$local_val" | sed 's/timeout: *//') ;;
      depends_on:*) STAGE_DEPS[$idx]=$(echo "$local_val" | sed 's/depends_on: *\[//;s/\]//') ;;
    esac
  fi
done < "$PIPELINE_FILE"

if [ "${#STAGES[@]}" -eq 0 ]; then
  echo "ERROR: no stages found in $PIPELINE_FILE" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

# ── Execute stages ──
declare -A STAGE_STATUS
FAILED=0

for i in "${!STAGES[@]}"; do
  stage="${STAGES[$i]}"
  cmd="${STAGE_COMMANDS[$i]}"
  agent="${STAGE_AGENTS[$i]}"
  input="${STAGE_INPUTS[$i]}"
  timeout="${STAGE_TIMEOUTS[$i]}"

  # Check dependencies
  deps="${STAGE_DEPS[$i]}"
  if [ -n "$deps" ]; then
    IFS=',' read -ra DEP_LIST <<< "$deps"
    skip=false
    for dep in "${DEP_LIST[@]}"; do
      dep=$(echo "$dep" | tr -d ' ')
      if [ "${STAGE_STATUS[$dep]:-}" = "failed" ]; then
        echo "  ⏭️  $stage — skipped (dependency $dep failed)"
        STAGE_STATUS["$stage"]="skipped"
        skip=true
        break
      fi
    done
    $skip && continue
  fi

  if $DRY_RUN; then
    echo "  🔍 $stage — dry-run (would execute: ${cmd:-agent:$agent})"
    STAGE_STATUS["$stage"]="dry-run"
    continue
  fi

  echo -n "  ▶️  $stage ... "
  args=(--name "$stage" --output-dir "$OUTPUT_DIR" --timeout "$timeout")
  [ -n "$cmd" ] && args+=(--command "$cmd")
  [ -n "$agent" ] && args+=(--agent "$agent")
  [ -n "$input" ] && args+=(--input "$input")

  result=$(echo '' | bash "$STAGE_RUNNER" "${args[@]}" 2>&1 | tail -1)
  STAGE_STATUS["$stage"]="$result"

  if [ "$result" = "success" ]; then
    echo "✅"
  else
    echo "❌ ($result)"
    FAILED=$((FAILED + 1))
  fi
done

# ── Summary ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=${#STAGES[@]}
PASSED=$((TOTAL - FAILED))
if [ "$FAILED" -eq 0 ]; then
  echo "Result: ✅ All $TOTAL stages passed"
else
  echo "Result: ❌ $FAILED/$TOTAL stages failed"
fi
echo "Output: $OUTPUT_DIR/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Write run summary ──
cat > "$OUTPUT_DIR/run-summary.json" <<EOJSON
{
  "pipeline": "$(basename "$PIPELINE_FILE")",
  "run_id": "$RUN_ID",
  "total_stages": $TOTAL,
  "passed": $PASSED,
  "failed": $FAILED,
  "result": "$([ "$FAILED" -eq 0 ] && echo success || echo failed)"
}
EOJSON

exit $FAILED
