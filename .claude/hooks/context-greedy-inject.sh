#!/usr/bin/env bash
set -uo pipefail
# context-greedy-inject.sh — SPEC-189 Slice 2: PreToolUse Read injector.
#
# When an agent invokes Read on a context-graph file (.acm, .scm), this hook
# evaluates whether a token-budgeted subgraph would replace the full file
# without losing relevance. It only acts when the subgraph quality crosses
# objective thresholds. Otherwise it bypasses silently.
#
# Decision tree (in order):
#   1. SAVIA_CGI=off                → exit 0
#   2. Tool != Read                 → exit 0
#   3. file_path not .acm/.scm      → exit 0
#   4. file_dir/.cgi-skip exists    → exit 0
#   5. File too small (< MIN_FILE_TOKENS)  → exit 0 (no point)
#   6. No query inferable           → exit 0 (telemetry: NO_QUERY)
#   7. Run context-greedy-budget --quality-json
#   8. Quality GOOD + mode=block    → exit 2, redirect to subgraph file
#   9. Quality GOOD + mode=warn     → exit 0, advisory to stderr
#  10. Quality GOOD + mode=shadow   → exit 0, telemetry only (DEFAULT)
#  11. Quality BAD                  → exit 0, telemetry, agent reads original
#
# Quality criteria (no LLM judge — all numeric, robust to query noise):
#   top1_score      >= QUALITY_MIN_TOP    (default 0.50)
#   savings_pct     >= MIN_SAVINGS_PCT    (default 30)
#   nodes_selected  >= 1
#   nodes_selected/nodes_total <= 0.99   (sanity: not "everything")
#
# Telemetry: output/context-greedy-inject.jsonl (one JSON per call).
# Useful for measuring real-world hit rate before promoting from shadow→block.
#
# Bypass:
#   SAVIA_CGI=off        → hook completely disabled
#   SAVIA_CGI=warn       → no block, advisory + telemetry
#   SAVIA_CGI=block      → block + redirect (after data validates)
#   SAVIA_CGI=shadow     → DEFAULT — telemetry only, never blocks
#
# Per-dir opt-out:
#   touch <file_dir>/.cgi-skip   → empty marker; skips Read in that dir.
#
# Tunables (env-overridable):
#   SAVIA_CGI_MIN_FILE_TOKENS   = 1500
#   SAVIA_CGI_QUALITY_MIN_TOP   = 0.50
#   SAVIA_CGI_MIN_SAVINGS_PCT   = 30
#   SAVIA_CGI_BUDGET            = 2000
#
# Ref: SPEC-189 docs/propuestas/SPEC-189-greedy-context-budget.md

# Source savia-env.sh — same convention as other hooks. If absent, the
# script falls back to PROJECT_DIR/pwd-derived defaults.
SAVIA_ENV="$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
if [[ -f "$SAVIA_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$SAVIA_ENV"
fi
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$(pwd)}}"

MODE="${SAVIA_CGI:-shadow}"
case "$MODE" in
  off) exit 0 ;;
  warn|block|shadow) ;;
  *) MODE="shadow" ;;
esac

MIN_FILE_TOKENS="${SAVIA_CGI_MIN_FILE_TOKENS:-1500}"
QUALITY_MIN_TOP="${SAVIA_CGI_QUALITY_MIN_TOP:-0.50}"
MIN_SAVINGS_PCT="${SAVIA_CGI_MIN_SAVINGS_PCT:-30}"
DEFAULT_BUDGET="${SAVIA_CGI_BUDGET:-2000}"

LOG_FILE="${CLAUDE_PROJECT_DIR}/output/context-greedy-inject.jsonl"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log_telemetry() {
  # Args: decision file query top1 savings reason
  local decision="${1:-UNKNOWN}"
  local file="${2:-}"
  local query="${3:-}"
  local top1="${4:-0}"
  local savings="${5:-0}"
  local reason="${6:-}"
  # Escape via jq so quotes/backslashes in query/reason are safe
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$(date -Iseconds 2>/dev/null || date)" \
           --arg mode "$MODE" \
           --arg decision "$decision" \
           --arg file "$file" \
           --arg query "$query" \
           --arg top1 "$top1" \
           --arg savings "$savings" \
           --arg reason "$reason" \
           '{ts:$ts, mode:$mode, decision:$decision, file:$file, query:$query, top1:($top1|tonumber? // 0), savings_pct:($savings|tonumber? // 0), reason:$reason}' \
      >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# Need jq for parsing
command -v jq >/dev/null 2>&1 || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit context-greedy-inject; }

# Need stdin
if [[ -t 0 ]]; then
  exit 0
fi
INPUT=$(cat 2>/dev/null || true)
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "Read" ]] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  *.acm|*.scm) ;;
  *) exit 0 ;;
esac

[[ -f "$FILE_PATH" && -r "$FILE_PATH" ]] || exit 0

FILE_DIR=$(dirname "$FILE_PATH")
[[ -f "$FILE_DIR/.cgi-skip" ]] && {
  log_telemetry "BYPASS_OPTOUT" "$FILE_PATH" "" "" "" "cgi-skip marker present"
  exit 0
}

FILE_BYTES=$(wc -c < "$FILE_PATH" 2>/dev/null || echo 0)
FILE_TOKENS=$(( FILE_BYTES / 4 ))
# Note: for .acm files with @include the expanded graph can be much larger
# than the raw file. The pre-filter is a coarse early bail-out; the real
# size check happens after running the script (using tokens_full_graph from
# the quality JSON). Keep the pre-filter very small (~200 tokens) so we
# only skip trivially tiny inputs.
PREFILTER_MIN=200
if (( FILE_TOKENS < PREFILTER_MIN )); then
  log_telemetry "BYPASS_TOO_SMALL_RAW" "$FILE_PATH" "" "" "" "file_tokens=$FILE_TOKENS < $PREFILTER_MIN (raw)"
  exit 0
fi

# Resolve script path
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CGB_SCRIPT="$HOOK_DIR/../../scripts/context-greedy-budget.py"
if [[ ! -f "$CGB_SCRIPT" ]]; then
  log_telemetry "BYPASS_NO_SCRIPT" "$FILE_PATH" "" "" "" "context-greedy-budget.py not found"
  exit 0
fi

# Extract query from turn context.
# Priority:
#   1. SAVIA_TURN_QUERY (env override, used in tests)
#   2. $TMPDIR/savia-turn-<TURN_ID>/last-prompt.txt (set by other hooks)
#   3. None → bypass
QUERY="${SAVIA_TURN_QUERY:-}"
if [[ -z "$QUERY" ]]; then
  TURN_ID="${CLAUDE_TURN_ID:-${CLAUDE_SESSION_ID:-default}}"
  TURN_FILE="${TMPDIR:-/tmp}/savia-turn-${TURN_ID}/last-prompt.txt"
  if [[ -f "$TURN_FILE" ]]; then
    QUERY=$(tail -c 500 "$TURN_FILE" 2>/dev/null | tr '\n' ' ' | head -c 200)
  fi
fi

QUERY=$(printf '%s' "$QUERY" | tr -cd '[:print:]' | sed 's/^ *//;s/ *$//')

if [[ -z "$QUERY" || ${#QUERY} -lt 3 ]]; then
  log_telemetry "BYPASS_NO_QUERY" "$FILE_PATH" "" "" "" "no inferable query"
  exit 0
fi

# Run greedy budget
QUALITY_FILE=$(mktemp 2>/dev/null) || exit 0
SUBGRAPH_FILE=$(mktemp --suffix=.md 2>/dev/null) || { rm -f "$QUALITY_FILE"; exit 0; }

if ! python3 "$CGB_SCRIPT" "$FILE_PATH" "$QUERY" \
     --budget "$DEFAULT_BUDGET" --quality-json --format markdown \
     >"$SUBGRAPH_FILE" 2>"$QUALITY_FILE"
then
  log_telemetry "BYPASS_SCRIPT_FAILED" "$FILE_PATH" "$QUERY" "" "" "script exit nonzero"
  rm -f "$QUALITY_FILE" "$SUBGRAPH_FILE"
  exit 0
fi

QUALITY_JSON=$(tail -n1 "$QUALITY_FILE" 2>/dev/null || echo "{}")
rm -f "$QUALITY_FILE"

if ! printf '%s' "$QUALITY_JSON" | jq -e . >/dev/null 2>&1; then
  log_telemetry "BYPASS_BAD_JSON" "$FILE_PATH" "$QUERY" "" "" "quality json malformed"
  rm -f "$SUBGRAPH_FILE"
  exit 0
fi

TOP1=$(printf '%s' "$QUALITY_JSON" | jq -r '.top1_score // 0')
SAVINGS=$(printf '%s' "$QUALITY_JSON" | jq -r '.savings_pct // 0')
NODES_SEL=$(printf '%s' "$QUALITY_JSON" | jq -r '.nodes_selected // 0')
NODES_TOT=$(printf '%s' "$QUALITY_JSON" | jq -r '.nodes_total // 0')
TOKENS_GRAPH=$(printf '%s' "$QUALITY_JSON" | jq -r '.tokens_full // 0')

# Real size check (post-expansion of @include): if the expanded graph is
# small enough that the agent reading the raw file is fine, bypass.
if (( TOKENS_GRAPH < MIN_FILE_TOKENS )); then
  log_telemetry "BYPASS_GRAPH_TOO_SMALL" "$FILE_PATH" "$QUERY" "$TOP1" "$SAVINGS" "tokens_graph=$TOKENS_GRAPH < $MIN_FILE_TOKENS"
  rm -f "$SUBGRAPH_FILE"
  exit 0
fi

# Quality decision (awk for float comparison)
DECISION=$(awk -v t="$TOP1" -v s="$SAVINGS" -v ns="$NODES_SEL" -v nt="$NODES_TOT" \
              -v mt="$QUALITY_MIN_TOP" -v ms="$MIN_SAVINGS_PCT" \
  'BEGIN {
    if (ns < 1) { print "BAD_NO_NODES"; exit }
    if (nt > 0 && (ns/nt) >= 0.99) { print "BAD_ALL_NODES"; exit }
    if (t+0 < mt+0) { print "BAD_LOW_TOP1"; exit }
    if (s+0 < ms+0) { print "BAD_LOW_SAVINGS"; exit }
    print "GOOD"
  }')

case "$DECISION" in
  GOOD)
    case "$MODE" in
      shadow)
        log_telemetry "SHADOW_GOOD" "$FILE_PATH" "$QUERY" "$TOP1" "$SAVINGS" "would_redirect_in_block_mode"
        rm -f "$SUBGRAPH_FILE"
        exit 0
        ;;
      warn)
        log_telemetry "WARN_GOOD" "$FILE_PATH" "$QUERY" "$TOP1" "$SAVINGS" "advisory_only"
        printf '\n[CGI] subgraph available: %s (saved %s%% — top1=%s)\n  See SAVIA_CGI=block to activate redirect.\n' \
          "$SUBGRAPH_FILE" "$SAVINGS" "$TOP1" >&2
        exit 0
        ;;
      block)
        log_telemetry "BLOCK_GOOD" "$FILE_PATH" "$QUERY" "$TOP1" "$SAVINGS" "redirect_to=$SUBGRAPH_FILE"
        cat >&2 <<EOF

[context-greedy-inject SPEC-189]
The full file (~$FILE_TOKENS tokens) is being skipped: a budgeted
subgraph is available with high relevance to the current turn.

  Original : $FILE_PATH
  Subgraph : $SUBGRAPH_FILE
  Query    : $QUERY
  Quality  : top1=$TOP1 savings=${SAVINGS}% (${NODES_SEL}/${NODES_TOT} nodes)

ACTION: Read the subgraph file instead for this turn.
If it misses critical context, retry with: SAVIA_CGI=off Read $FILE_PATH

Per-dir opt-out: touch $FILE_DIR/.cgi-skip
Mode env       : SAVIA_CGI={off,shadow,warn,block} (current: $MODE)
EOF
        exit 2
        ;;
    esac
    ;;
  *)
    log_telemetry "$DECISION" "$FILE_PATH" "$QUERY" "$TOP1" "$SAVINGS" "below_threshold"
    rm -f "$SUBGRAPH_FILE"
    exit 0
    ;;
esac
