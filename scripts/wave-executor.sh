#!/usr/bin/env bash
set -uo pipefail
# wave-executor.sh — Generic wave execution engine for DAG task graphs
# Usage: wave-executor.sh <task-graph.json> [--report <output.json>]
# Exit: 0=success, 1=task failed, 2=invalid input, 3=timeout, 143/130=interrupted
# Env: SDD_MAX_PARALLEL_AGENTS (default 5, if the graph has no max_parallel)
#      SDD_DEFAULT_TIMEOUT_MIN (default 30, for tasks without timeout_seconds)
#      WAVE_KILL_AFTER (seconds between SIGTERM and SIGKILL on timeout, default 10)
# NOTE: no set -e — script manages exit codes manually via wait+ec pattern

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/wave-executor-lib.sh"

usage() { echo "usage: wave-executor.sh <graph.json> [--report out.json]" >&2; exit 2; }
is_posint() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 )); }

GRAPH_FILE="" REPORT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) [[ $# -ge 2 && -n "$2" ]] || { echo "--report requires a path" >&2; usage; }
      REPORT_FILE="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) GRAPH_FILE="$1"; shift ;;
  esac
done
[[ -z "$GRAPH_FILE" ]] && usage
[[ ! -f "$GRAPH_FILE" ]] && { echo "file not found: $GRAPH_FILE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }

DEF_MAX="${SDD_MAX_PARALLEL_AGENTS:-5}"
DEF_TMO_MIN="${SDD_DEFAULT_TIMEOUT_MIN:-30}"
KILL_AFTER="${WAVE_KILL_AFTER:-10}"
is_posint "$DEF_MAX" || { echo "SDD_MAX_PARALLEL_AGENTS must be an integer >= 1" >&2; exit 2; }
is_posint "$DEF_TMO_MIN" || { echo "SDD_DEFAULT_TIMEOUT_MIN must be an integer >= 1" >&2; exit 2; }
is_posint "$KILL_AFTER" || { echo "WAVE_KILL_AFTER must be an integer >= 1" >&2; exit 2; }

validate_graph "$GRAPH_FILE" || exit 2

MAX_P=$(jq -r --argjson d "$DEF_MAX" '.max_parallel // $d' "$GRAPH_FILE" | tr -d '\r')
TASK_COUNT=$(jq '.tasks | length' "$GRAPH_FILE" | tr -d '\r')
TIMEOUT_CMD=$(detect_timeout_cmd)

if [[ $TASK_COUNT -eq 0 ]]; then
  R='{"status":"success","total_waves":0,"total_tasks":0,"wall_clock_seconds":0,"sequential_estimate_seconds":0,"speedup_percent":0,"waves":[]}'
  if [[ -n "$REPORT_FILE" ]]; then echo "$R" > "$REPORT_FILE"; else echo "$R"; fi
  exit 0
fi

# Interrupción del motor: terminar las tareas en curso en vez de dejarlas huérfanas.
# TERM a timeout lo reenvía al grupo de la tarea y arma el kill-after.
declare -A PIDS=() STARTS=() TMPS=()
on_signal() {
  local sig="$1" p
  trap - TERM INT HUP
  for p in "${PIDS[@]}"; do kill -TERM "$p" 2>/dev/null; done
  for p in "${PIDS[@]}"; do wait "$p" 2>/dev/null; done
  for p in "${TMPS[@]}"; do rm -f "$p"; done
  echo "interrupted by SIG$sig: running tasks terminated" >&2
  [[ "$sig" == "INT" ]] && exit 130
  exit 143
}
trap 'on_signal TERM' TERM
trap 'on_signal INT' INT
trap 'on_signal HUP' HUP

WAVES_JSON=$(compute_waves "$GRAPH_FILE" "$MAX_P")
WAVE_COUNT=$(echo "$WAVES_JSON" | jq 'length' | tr -d '\r')
WALL_START=$SECONDS; SEQ_TOTAL=0; EXIT_CODE=0; REPORT_WAVES="[]"

for w in $(seq 0 $((WAVE_COUNT - 1))); do
  mapfile -t WAVE_IDS < <(echo "$WAVES_JSON" | jq -r ".[$w][]" | tr -d '\r')
  WAVE_RESULTS="[]"; WAVE_START=$SECONDS
  PIDS=() STARTS=() TMPS=()
  declare -A TMOS=()
  for tid in "${WAVE_IDS[@]}"; do
    CMD=$(jq -r --arg id "$tid" '.tasks[] | select(.id==$id) | .command' "$GRAPH_FILE" | tr -d '\r')
    TMO=$(jq -r --arg id "$tid" --argjson d "$((DEF_TMO_MIN * 60))" \
      '.tasks[] | select(.id==$id) | .timeout_seconds // $d' "$GRAPH_FILE" | tr -d '\r')
    TMOS[$tid]="$TMO"
    TMPF=$(mktemp); TMPS[$tid]="$TMPF"; STARTS[$tid]=$SECONDS
    if [[ -n "$TIMEOUT_CMD" ]]; then $TIMEOUT_CMD -k "$KILL_AFTER" "$TMO" bash -c "$CMD" >"$TMPF" 2>&1 </dev/null &
    else bash -c "$CMD" >"$TMPF" 2>&1 </dev/null & fi
    PIDS[$tid]=$!
  done
  for tid in "${WAVE_IDS[@]}"; do
    wait "${PIDS[$tid]}" 2>/dev/null && ec=0 || ec=$?
    dur=$(( SECONDS - ${STARTS[$tid]} )); SEQ_TOTAL=$((SEQ_TOTAL + dur))
    rm -f "${TMPS[$tid]}"
    # 124 (TERM) / 137 (KILL tras -k) solo son timeout si de verdad venció el plazo:
    # una tarea que sale con 124 por sí misma es un fallo normal.
    ST="success"
    if [[ $ec -ne 0 ]]; then
      ST="failed"
      [[ -n "$TIMEOUT_CMD" && ($ec -eq 124 || $ec -eq 137) ]] && (( dur >= ${TMOS[$tid]} )) && ST="timeout"
    fi
    FP=true
    if [[ "$ST" == "success" ]]; then
      verify_expected_files "$GRAPH_FILE" "$tid" || { ST="failed"; FP=false; ec=1; }
    fi
    [[ "$ST" != "success" ]] && FP=false
    WAVE_RESULTS=$(echo "$WAVE_RESULTS" | jq --arg id "$tid" --arg st "$ST" \
      --argjson ec "$ec" --argjson dur "$dur" --argjson fp "$FP" \
      '. + [{"id":$id,"status":$st,"exit_code":$ec,"duration_seconds":$dur,"expected_files_present":$fp}]')
    [[ "$ST" == "timeout" && $EXIT_CODE -eq 0 ]] && EXIT_CODE=3
    [[ "$ST" == "failed" && $EXIT_CODE -eq 0 ]] && EXIT_CODE=1
  done
  PIDS=() TMPS=()
  WDUR=$(( SECONDS - WAVE_START ))
  REPORT_WAVES=$(echo "$REPORT_WAVES" | jq --argjson w "$w" --argjson t "$WAVE_RESULTS" \
    --argjson d "$WDUR" '. + [{"wave":$w,"tasks":$t,"wave_duration_seconds":$d}]')
  if [[ $EXIT_CODE -ne 0 ]]; then
    for rw in $(seq $((w + 1)) $((WAVE_COUNT - 1))); do
      SK="[]"
      for sid in $(echo "$WAVES_JSON" | jq -r ".[$rw][]" | tr -d '\r'); do
        SK=$(echo "$SK" | jq --arg id "$sid" '. + [{"id":$id,"status":"skipped","exit_code":0,"duration_seconds":0,"expected_files_present":false}]')
      done
      REPORT_WAVES=$(echo "$REPORT_WAVES" | jq --argjson w "$rw" --argjson t "$SK" '. + [{"wave":$w,"tasks":$t,"wave_duration_seconds":0}]')
    done
    break
  fi
done

WALL=$(( SECONDS - WALL_START ))
[[ $SEQ_TOTAL -gt 0 ]] && SP=$(( (SEQ_TOTAL - WALL) * 100 / SEQ_TOTAL )) || SP=0
[[ $SP -lt 0 ]] && SP=0
STAT="success"; [[ $EXIT_CODE -ne 0 ]] && STAT="failed"
REPORT=$(jq -n --arg s "$STAT" --argjson tw "$WAVE_COUNT" --argjson tt "$TASK_COUNT" \
  --argjson wc "$WALL" --argjson se "$SEQ_TOTAL" --argjson sp "$SP" --argjson ws "$REPORT_WAVES" \
  '{status:$s,total_waves:$tw,total_tasks:$tt,wall_clock_seconds:$wc,sequential_estimate_seconds:$se,speedup_percent:$sp,waves:$ws}')
if [[ -n "$REPORT_FILE" ]]; then echo "$REPORT" > "$REPORT_FILE"; else echo "$REPORT"; fi
exit $EXIT_CODE
