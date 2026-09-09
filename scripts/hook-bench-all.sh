#!/usr/bin/env bash
# hook-bench-all.sh — SE-037 Slice 1 probe: measure latency of all hooks.
#
# Runs each `.opencode/hooks/*.sh` N times (default 5) with a neutral stdin
# payload and reports p50/p95/p99 in milliseconds. Output is a markdown
# table sorted by p95 descending, plus a summary of violations against
# the SLA 20ms p50 for critical hooks.
#
# Hooks matching the established critical-name convention must also be
# registered for SessionStart or a per-turn event. Unregistered and
# lifecycle-only scripts are analysis/cold path.
#
# Ref: SE-037, ROADMAP.md §Tier 1.1
# Safety: `set -uo pipefail`. No network. No destructive ops.

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
HOOKS_DIR="$REPO_ROOT/.opencode/hooks"
OUTPUT_DIR="$REPO_ROOT/output"
DATE_STR="$(date +%Y%m%d)"
REPORT="$OUTPUT_DIR/hook-bench-report-$DATE_STR.md"

RUNS="${RUNS:-5}"
SLA_CRITICAL_MS=20
SLA_ANALYSIS_MS=100

usage() {
  cat <<EOF
Usage: $0 [--runs N] [--quiet]

  --runs N   Number of runs per hook (default 5, max 20)
  --quiet    Suppress stdout, only write report

Output: $REPORT
EOF
}

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; usage; exit 2 ;;
  esac
done

if [[ "$RUNS" -lt 1 || "$RUNS" -gt 20 ]]; then
  echo "ERROR: --runs must be in [1,20]" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

# Resolve hot-path membership from the runtime registry instead of filenames.
declare -A CRITICAL_HOOKS=()
SETTINGS_FILE="$REPO_ROOT/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r command; do
    hook_name=$(printf '%s\n' "$command" | sed -E 's#.*[/]([^/" ]+)\.sh.*#\1#')
    [[ -n "$hook_name" ]] && CRITICAL_HOOKS["$hook_name"]=1
  done < <(jq -r '
    .hooks | to_entries[]
    | select(.key | test("^(SessionStart|UserPromptSubmit|PreToolUse|PostToolUse|Stop)$"))
    | .value[]?.hooks[]?.command // empty
  ' "$SETTINGS_FILE" 2>/dev/null)
fi

# Classify hook as critical or analysis.
classify_hook() {
  local name
  name=$(basename "$1" .sh)
  case "$name" in
    session-*|memory-*|claude-*|pre-*|post-*|user-prompt-*|tool-*)
      if [[ -n "${CRITICAL_HOOKS[$name]+x}" ]]; then
        echo "critical"
        return
      fi
      ;;
  esac
  echo "analysis"
}

# Median from sorted numbers in stdin.
median() {
  sort -n | awk 'BEGIN{c=0} {a[c++]=$1} END{if(c==0){print 0}else if(c%2){print a[int(c/2)]}else{print (a[c/2-1]+a[c/2])/2}}'
}

percentile() {
  local p=$1
  sort -n | awk -v p="$p" 'BEGIN{c=0} {a[c++]=$1} END{if(c==0){print 0}else{idx=int(c*p/100); if(idx>=c)idx=c-1; print a[idx]}}'
}

# Measure a single hook run in milliseconds.
measure_one() {
  local hook="$1"
  local start_ns end_ns
  start_ns=$(date +%s%N)
  # Bench with neutral empty stdin; redirect output to null; don't care about exit code.
  : | bash "$hook" >/dev/null 2>&1 || true
  end_ns=$(date +%s%N)
  echo $(( (end_ns - start_ns) / 1000000 ))
}

# Collect stats for one hook.
bench_hook() {
  local hook="$1"
  local i
  local samples=""
  for i in $(seq 1 "$RUNS"); do
    samples="$samples"$'\n'"$(measure_one "$hook")"
  done
  local p50 p95 p99
  p50=$(echo "$samples" | grep -v '^$' | percentile 50)
  p95=$(echo "$samples" | grep -v '^$' | percentile 95)
  p99=$(echo "$samples" | grep -v '^$' | percentile 99)
  echo "$p50|$p95|$p99"
}

total=0
critical_count=0
critical_violations=0
analysis_count=0
analysis_violations=0

declare -a RESULTS

if [[ "$QUIET" -eq 0 ]]; then
  echo "hook-bench-all: scanning $HOOKS_DIR (runs=$RUNS per hook)..."
fi

while IFS= read -r hook; do
  [[ -f "$hook" ]] || continue
  total=$((total+1))
  category=$(classify_hook "$hook")
  stats=$(bench_hook "$hook")
  p50="${stats%%|*}"
  rest="${stats#*|}"
  p95="${rest%%|*}"
  p99="${rest##*|}"
  name=$(basename "$hook" .sh)

  if [[ "$category" == "critical" ]]; then
    critical_count=$((critical_count+1))
    if [[ "$p50" -gt "$SLA_CRITICAL_MS" ]]; then
      critical_violations=$((critical_violations+1))
    fi
  else
    analysis_count=$((analysis_count+1))
    if [[ "$p50" -gt "$SLA_ANALYSIS_MS" ]]; then
      analysis_violations=$((analysis_violations+1))
    fi
  fi

  RESULTS+=("$p95|$p50|$p95|$p99|$category|$name")
done < <(find -L "$HOOKS_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

if [[ "$total" -eq 0 ]]; then
  echo "ERROR: no hook scripts found in $HOOKS_DIR" >&2
  exit 2
fi

# Sort results by p95 descending for the report.
SORTED=$(printf '%s\n' "${RESULTS[@]}" | sort -t'|' -k1 -n -r)

{
  echo "# Hook bench report — $DATE_STR"
  echo ""
  echo "- Hooks scanned: $total"
  echo "- Runs per hook: $RUNS"
  echo "- SLA critical: p50 ≤ ${SLA_CRITICAL_MS}ms"
  echo "- SLA analysis: p50 ≤ ${SLA_ANALYSIS_MS}ms"
  echo "- Critical hooks: $critical_count (violations: $critical_violations)"
  echo "- Analysis hooks: $analysis_count (violations: $analysis_violations)"
  echo ""
  echo "## Ranking (by p95, descending)"
  echo ""
  echo "| Hook | Category | p50 (ms) | p95 (ms) | p99 (ms) | SLA |"
  echo "|---|---|---|---|---|---|"
  echo "$SORTED" | while IFS='|' read -r _ p50 p95 p99 category name; do
    sla_limit=$SLA_ANALYSIS_MS
    [[ "$category" == "critical" ]] && sla_limit=$SLA_CRITICAL_MS
    status="PASS"
    if [[ "$p50" -gt "$sla_limit" ]]; then status="FAIL"; fi
    echo "| \`$name\` | $category | $p50 | $p95 | $p99 | $status |"
  done
  echo ""
  echo "## Interpretation"
  echo ""
  if [[ "$critical_violations" -eq 0 && "$analysis_violations" -eq 0 ]]; then
    echo "No SLA violations detected. Current state is within budget. Consider SE-037 Slice 2 (BATS coverage) as next work."
  else
    echo "SLA violations detected. Prioritize remediation in SE-037 Slice 2:"
    echo ""
    echo "$SORTED" | while IFS='|' read -r _ p50 p95 p99 category name; do
      sla_limit=$SLA_ANALYSIS_MS
      [[ "$category" == "critical" ]] && sla_limit=$SLA_CRITICAL_MS
      if [[ "$p50" -gt "$sla_limit" ]]; then
        echo "- \`$name\` ($category): p50=${p50}ms, SLA=${sla_limit}ms"
      fi
    done
  fi
  echo ""
  echo "---"
  echo ""
  echo "Generated by scripts/hook-bench-all.sh — $DATE_STR"
} > "$REPORT"

if [[ "$QUIET" -eq 0 ]]; then
  echo "hook-bench-all: total=$total critical_violations=$critical_violations analysis_violations=$analysis_violations"
  echo "  report: ${REPORT#$REPO_ROOT/}"
fi

exit 0
