#!/usr/bin/env bash
set -uo pipefail
# prompt-suggestion-engine.sh — SPEC-044 Phase 2: trace-driven prompt optimization
# Reads trace analysis, classifies failure patterns, generates optimization plan.
# Usage: prompt-suggestion-engine.sh [--agent NAME] [--traces-file PATH] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${TRACE_ANALYSIS_DIR:-$ROOT/output/trace-analysis}"
AGENT_FILTER=""
TRACES_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT_FILTER="$2"; shift 2 ;;
    --traces-file) TRACES_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) echo "Usage: $0 [--agent NAME] [--traces-file PATH] [--dry-run]"; exit 0 ;;
    *) shift ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

# Step 1: Run extractor if no candidates file exists
CANDIDATES="$OUTPUT_DIR/agent-candidates.json"
if [[ ! -f "$CANDIDATES" ]] || [[ -n "$TRACES_FILE" ]]; then
  EXTRA_ARGS=""
  [[ -n "$AGENT_FILTER" ]] && EXTRA_ARGS="--agent $AGENT_FILTER"
  [[ -n "$TRACES_FILE" ]] && EXTRA_ARGS="$EXTRA_ARGS --traces-file $TRACES_FILE"
  bash "$SCRIPT_DIR/trace-pattern-extractor.sh" $EXTRA_ARGS > "$CANDIDATES" 2>/dev/null || true
fi

if [[ ! -s "$CANDIDATES" ]]; then
  echo "No optimization candidates found. Traces may be insufficient."
  exit 0
fi

# Step 2: Classify patterns per agent
classify_patterns() {
  local agent="$1" failure_rate="$2" budget_rate="$3"
  local patterns=""

  if (( $(echo "$failure_rate > 20" | bc -l 2>/dev/null || echo 0) )); then
    patterns="${patterns}frequent_failures,"
  fi
  if (( $(echo "$budget_rate > 30" | bc -l 2>/dev/null || echo 0) )); then
    patterns="${patterns}budget_blowout,"
  fi
  [[ -z "$patterns" ]] && patterns="general_improvement,"
  echo "${patterns%,}"
}

# Step 3: Generate suggestion per pattern
suggest_fix() {
  local pattern="$1"
  case "$pattern" in
    frequent_failures) echo "Add explicit error handling instructions and verification step" ;;
    budget_blowout)    echo "Add output length constraint and budget awareness" ;;
    verbose_output)    echo "Add 'be concise' instruction and max output lines" ;;
    slow_execution)    echo "Reduce context loaded, add skip conditions" ;;
    inconsistent)      echo "Add self-verification step before returning" ;;
    *)                 echo "Review prompt for clarity and specificity" ;;
  esac
}

# Step 4: Output optimization plan
echo "Prompt Optimization Plan"
echo "========================"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Parse candidates (simplified — expects one JSON object per line or array)
python3 -c "
import json, sys
try:
    data = json.load(open('$CANDIDATES'))
    candidates = data if isinstance(data, list) else data.get('candidates', [])
    for c in candidates[:10]:
        name = c.get('agent', 'unknown')
        # El extractor emite tasas como fracción (0.5); el clasificador umbrales en %
        fr = round(c.get('failure_rate', 0) * 100, 1)
        br = round(c.get('budget_overage_rate', c.get('budget_exceeded_rate', 0)) * 100, 1)
        print(f'{name}|{fr}|{br}')
except Exception as e:
    print(f'ERROR|0|0', file=sys.stderr)
" 2>/dev/null | while IFS='|' read -r name fr br; do
  [[ -z "$name" || "$name" == "ERROR" ]] && continue
  [[ -n "$AGENT_FILTER" && "$name" != "$AGENT_FILTER" ]] && continue

  patterns=$(classify_patterns "$name" "$fr" "$br")
  echo "Agent: $name"
  echo "  Failure rate: ${fr}%"
  echo "  Budget overage: ${br}%"
  echo "  Patterns: $patterns"
  echo "  Suggestions:"
  IFS=',' read -ra PATS <<< "$patterns"
  for p in "${PATS[@]}"; do
    echo "    - $(suggest_fix "$p")"
  done

  if [[ "$DRY_RUN" == "false" ]]; then
    # Write per-agent plan
    cat > "$OUTPUT_DIR/${name}-plan.md" << EOF
# Optimization Plan: $name

Failure rate: ${fr}% | Budget overage: ${br}%
Patterns: $patterns

## Suggested changes:
$(for p in "${PATS[@]}"; do echo "- $(suggest_fix "$p")"; done)

## Next: run /skill-optimize $name --from-traces
EOF
    echo "  Plan saved: $OUTPUT_DIR/${name}-plan.md"
  else
    echo "  (dry-run — no files written)"
  fi
  echo ""
done

echo "Done. Review plans in $OUTPUT_DIR/"
