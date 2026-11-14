#!/usr/bin/env bash
# scripts/overnight-sprint-loop.sh — SE-226: stateless overnight-sprint orchestrator
set -uo pipefail
#
# Usage:
#   overnight-sprint-loop.sh --sprint-id <id> --tasks <json-file> [--max-tasks 10] [--dry-run]
#
# Behavior:
#   - Reads state.json for each task; skips non-pending
#   - Writes checkpoint BEFORE and AFTER each task
#   - Model escalation: fast → mid → heavy (TOKEN_EXHAUSTION only)
#   - Aborts after AGENT_MAX_CONSECUTIVE_FAILURES consecutive failures (default: 3)
#   - Time-box per task: AGENT_TASK_TIMEOUT_MINUTES (default: 15)
#   - Audit log: output/agent-runs/<sprint-id>-audit.log
#   - stdlib-only bash; no external deps in the orchestrator
#   - SE-472: before EACH task, check_authority (scripts/lib/overnight-authority.sh) verifies the
#     operator grant; not valid → no new task starts, pending tasks → suspended (fail-closed).
#     It is checked again before each model escalation (a new agent launch).
#     Exit code 4 = batch stopped for lack of authority (0 = batch finished normally).
#     Suspended tasks are not resumed automatically: renew the grant and reset them to
#     "pending" in state.json (or start a new sprint) before running the loop again.
#   - The loop manages state only; actual agent execution is done by the caller hook
#
# Ref: SE-226, docs/rules/domain/autonomous-safety.md
set -uo pipefail

# ── Path resolution ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")}}}"
AGENT_RUNS_DIR="$WORKSPACE_DIR/output/agent-runs"
STATE_SCRIPT="$SCRIPT_DIR/overnight-sprint-state.sh"
# SE-472: vigencia de la autoridad antes de cada tarea (check_authority)
# shellcheck source=scripts/lib/overnight-authority.sh
source "$SCRIPT_DIR/lib/overnight-authority.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
MAX_CONSECUTIVE_FAILURES="${AGENT_MAX_CONSECUTIVE_FAILURES:-3}"
TASK_TIMEOUT_MIN="${AGENT_TASK_TIMEOUT_MINUTES:-15}"
MAX_TASKS=10
DRY_RUN=0
SPRINT_ID=""
TASKS_FILE=""

# Export loop context for recursion prevention (SPEC-RECURSION-GUARD)
# shellcheck source=scripts/recursion-guard-export.sh
source "$(dirname "$0")/recursion-guard-export.sh" "overnight-sprint"

# Model tier progression (TOKEN_EXHAUSTION escalation only)
MODEL_TIERS=("fast" "mid" "heavy")

# ── Helpers ──────────────────────────────────────────────────────────────────
_now()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
_log()  { printf '[%s] %s\n' "$(_now)" "$*"; }
_err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
_warn() { printf 'WARN:  %s\n' "$*" >&2; }

_jq_available() { command -v jq &>/dev/null; }

# Read a single value from state.json
_state_value() {
  local sprint_id="$1"
  local query="$2"
  local sf="$AGENT_RUNS_DIR/$sprint_id/state.json"
  [[ -f "$sf" ]] || return 1
  if _jq_available; then
    jq -r "$query" "$sf"
  else
    python3 -c "
import sys, json
data = json.load(open('$sf'))
import re
parts = [p for p in re.split(r'[.\[\]]+', '$query') if p]
val = data
for p in parts:
    if p.lstrip('-').isdigit():
        val = val[int(p)]
    else:
        val = val.get(p, '')
print(val if not isinstance(val, (dict, list)) else json.dumps(val))
"
  fi
}

# Get pending task IDs (returns space-separated list)
_pending_tasks() {
  local sprint_id="$1"
  local sf="$AGENT_RUNS_DIR/$sprint_id/state.json"
  [[ -f "$sf" ]] || return 1
  if _jq_available; then
    jq -r '.tasks[] | select(.status == "pending") | .id' "$sf"
  else
    python3 -c "
import json
data = json.load(open('$sf'))
for t in data.get('tasks', []):
    if t.get('status') == 'pending':
        print(t['id'])
"
  fi
}

# Get task description by id
_task_description() {
  local sprint_id="$1"
  local task_id="$2"
  local sf="$AGENT_RUNS_DIR/$sprint_id/state.json"
  if _jq_available; then
    jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .description' "$sf"
  else
    python3 -c "
import json
data = json.load(open('$sf'))
for t in data.get('tasks', []):
    if str(t.get('id')) == '$task_id':
        print(t.get('description', ''))
        break
"
  fi
}

# SE-472: exit code when the batch stops for lack of authority
AUTHORITY_STOP_EXIT=4

# SE-472: suspend pending tasks (and, optionally, the task in progress) after a failed
# authority check. Sets AUTHORITY_SUSPENDED_N. The audit records what really happened:
# if the state update fails, it says suspend_failed instead of claiming suspension.
_authority_stop() {
  local sprint_id="$1" pending_ids="$2" current_task="${3:-}"
  local n
  n="$(printf '%s\n' "$pending_ids" | grep -c .)"
  [[ -n "$current_task" ]] && n=$(( n + 1 ))
  local scope
  scope="$(authority_scope)"
  local -a extra=()
  [[ -n "$current_task" ]] && extra=(--task-id "$current_task")
  local err
  if err="$(bash "$STATE_SCRIPT" suspend --reason "$AUTHORITY_REASON" "${extra[@]}" 2>&1 >/dev/null)"; then
    AUTHORITY_SUSPENDED_N="$n"
    _log "ABORT: $AUTHORITY_REASON — $n tarea(s) suspendida(s), no arranca ninguna nueva"
    _audit "$sprint_id" "AUTHORITY_SUSPENDED reason=$AUTHORITY_REASON suspended=$n scope=$scope${current_task:+ task_in_progress=$current_task}"
  else
    AUTHORITY_SUSPENDED_N=0
    _warn "ABORT: $AUTHORITY_REASON — no se pudo marcar suspended: ${err//$'\n'/ }"
    _log "ABORT: $AUTHORITY_REASON — no arranca ninguna tarea nueva (estado sin actualizar)"
    _audit "$sprint_id" "AUTHORITY_SUSPEND_FAILED reason=$AUTHORITY_REASON pending=$n scope=$scope"
  fi
}

# Append to audit log
_audit() {
  local sprint_id="$1"
  local message="$2"
  local audit_file="$AGENT_RUNS_DIR/${sprint_id}-audit.log"
  printf '[%s] %s\n' "$(_now)" "$message" >> "$audit_file"
}

# ── Coherence Court wiring (SE-350) ─────────────────────────────────────────
# Deterministic, non-saturating: registers each completed task as a premise in
# the sprint's coherence registry and runs the cheap `check` gate (no LLM).
# The full 4-judge LLM audit is opt-in at flow END (COHERENCE_AUDIT_JUDGES=1)
# via /coherence-court — NEVER per-task (would saturate an overnight loop).
COHERENCE_SCRIPT="$SCRIPT_DIR/coherence-court.sh"

_coherence_enabled() {
  [[ "${OVERNIGHT_COHERENCE_GATE:-on}" != "off" ]] || return 1
  [[ -f "$COHERENCE_SCRIPT" ]] || return 1
  return 0
}

# Register a completed task as a decision premise. Advisory — never fails the loop.
_coherence_register() {
  local sprint_id="$1" task_id="$2" description="$3"
  _coherence_enabled || return 0
  _py3_avail=0; command -v python3 &>/dev/null && _py3_avail=1
  [[ "$_py3_avail" -eq 1 ]] || { _warn "  coherence: python3 missing — skip premise registration"; return 0; }
  # Ensure the flow registry exists (idempotent)
  bash "$COHERENCE_SCRIPT" premises "$sprint_id" init >/dev/null 2>&1
  local pid
  pid=$(bash "$COHERENCE_SCRIPT" premises "$sprint_id" add decision \
        "task $task_id completado: $description" --stage "task-$task_id" 2>/dev/null)
  if [[ -n "$pid" ]]; then
    _audit "$sprint_id" "COHERENCE_PREMISE task_id=$task_id premise_id=$pid"
  else
    _warn "  coherence: no se pudo registrar premisa para task $task_id"
  fi
}

# Deterministic gate at loop end (no LLM). Report-only — never blocks the loop.
_coherence_gate() {
  local sprint_id="$1"
  _coherence_enabled || return 0
  local n
  n=$(bash "$COHERENCE_SCRIPT" premises "$sprint_id" list --json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  if [[ "$n" -gt 0 ]]; then
    _audit "$sprint_id" "COHERENCE_GATE flow=$sprint_id premises=$n verdict=pass"
    echo "Coherence Court: $n premisa(s) registrada(s) en flujo '$sprint_id' (determinista, sin LLM)."
    if [[ "${COHERENCE_AUDIT_JUDGES:-0}" == "1" ]]; then
      echo "  Auditoría LLM (4 jueces) disponible: /coherence-court --flow $sprint_id"
    fi
  else
    _audit "$sprint_id" "COHERENCE_GATE flow=$sprint_id premises=0 verdict=single-stage"
  fi
}

# ── Agent runner hook ────────────────────────────────────────────────────────
# This function is the integration point. By default it is a NO-OP that returns
# PENDING (for testing / dry-run). Callers override it by sourcing this script
# and redefining run_agent_task().
#
# Contract:
#   run_agent_task <sprint_id> <task_id> <description> <model_tier>
#   exits with:
#     0 → success
#     2 → TOKEN_EXHAUSTION (trigger model escalation)
#     3 → OOM | TIMEOUT | INFRA_ERROR (abort without escalation)
#     * → generic failure

run_agent_task() {
  local sprint_id="$1"
  local task_id="$2"
  local description="$3"
  local model_tier="$4"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    _log "DRY-RUN: would execute task $task_id '$description' with model $model_tier"
    return 0
  fi

  # Default stub: caller must override this function for real execution.
  _warn "run_agent_task not implemented — return PENDING"
  return 0
}

# ── Arg parsing ──────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sprint-id)   SPRINT_ID="$2";   shift 2 ;;
      --tasks)       TASKS_FILE="$2";  shift 2 ;;
      --max-tasks)   MAX_TASKS="$2";   shift 2 ;;
      --dry-run)     DRY_RUN=1;        shift   ;;
      *) _err "unknown argument: $1" ;;
    esac
  done
  [[ -n "$SPRINT_ID" ]]  || _err "--sprint-id required"
  [[ -n "$TASKS_FILE" ]] || _err "--tasks required"
  [[ -f "$TASKS_FILE" ]] || _err "tasks file not found: $TASKS_FILE"
}

# ── Main loop ────────────────────────────────────────────────────────────────
run_loop() {
  local sprint_id="$SPRINT_ID"
  local audit_file="$AGENT_RUNS_DIR/${sprint_id}-audit.log"
  mkdir -p "$AGENT_RUNS_DIR"

  export OVERNIGHT_SPRINT_ID="$sprint_id"
  export AGENT_RUNS_DIR

  # Initialize state (idempotent — no-op if state already exists)
  bash "$STATE_SCRIPT" init --sprint-id "$sprint_id" --tasks-file "$TASKS_FILE" >/dev/null

  local started_at
  started_at="$(_now)"
  _audit "$sprint_id" "LOOP_START sprint_id=$sprint_id max_tasks=$MAX_TASKS dry_run=$DRY_RUN"
  _log "Loop started: sprint=$sprint_id max_tasks=$MAX_TASKS timeout=${TASK_TIMEOUT_MIN}m dry_run=$DRY_RUN"
  if authority_check_disabled; then
    _audit "$sprint_id" "grant-check disabled"
    _log "control de autoridad desactivado (decisión explícita de la operadora)"
  elif authority_scope_overridden; then
    _audit "$sprint_id" "grant-scope override scope=$(authority_scope)"
    _log "scope de autoridad distinto del de por defecto: $(authority_scope)"
  fi

  local tasks_run=0
  local tasks_done=0
  local tasks_failed=0
  local consecutive_failures=0
  local tasks_suspended=0
  local authority_stopped=0

  while true; do
    # Check task budget
    if [[ "$tasks_run" -ge "$MAX_TASKS" ]]; then
      _log "Reached max_tasks=$MAX_TASKS — stopping"
      _audit "$sprint_id" "LOOP_STOP reason=max_tasks tasks_run=$tasks_run done=$tasks_done failed=$tasks_failed"
      break
    fi

    # Check consecutive failure gate (autonomous-safety.md)
    if [[ "$consecutive_failures" -ge "$MAX_CONSECUTIVE_FAILURES" ]]; then
      _log "ABORT: consecutive_failures=$consecutive_failures >= max=$MAX_CONSECUTIVE_FAILURES"
      _audit "$sprint_id" "LOOP_ABORT reason=max_consecutive_failures consecutive_failures=$consecutive_failures"
      break
    fi

    # Read pending tasks
    local pending_ids
    pending_ids="$(_pending_tasks "$sprint_id" 2>/dev/null || echo "")"

    if [[ -z "$pending_ids" ]]; then
      _log "No pending tasks remaining — loop complete"
      _audit "$sprint_id" "LOOP_STOP reason=no_pending_tasks done=$tasks_done failed=$tasks_failed"
      break
    fi

    # SE-472: la autoridad se comprueba antes de CADA tarea. Fail-closed: caducada,
    # revocada, ausente o ilegible = no arranca nada nuevo; las pendientes quedan
    # suspendidas con el motivo. La tarea en curso no se mata (ya terminó o agotó su time-box).
    if ! check_authority; then
      _authority_stop "$sprint_id" "$pending_ids"
      _audit "$sprint_id" "LOOP_STOP reason=$AUTHORITY_REASON tasks_run=$tasks_run done=$tasks_done failed=$tasks_failed"
      tasks_suspended=$(( tasks_suspended + AUTHORITY_SUSPENDED_N ))
      authority_stopped=1
      break
    fi

    # Pick first pending task
    local task_id
    task_id="$(printf '%s\n' "$pending_ids" | head -1)"

    local description
    description="$(_task_description "$sprint_id" "$task_id")"

    _log "Task $task_id: '$description'"
    _audit "$sprint_id" "TASK_START task_id=$task_id description='$description'"

    # Model escalation loop
    local succeeded=0
    local task_exit_code=0
    local used_model="fast"

    local escalation_blocked=0
    for model_tier in "${MODEL_TIERS[@]}"; do
      used_model="$model_tier"

      # SE-472: una escalada relanza el agente; sin autoridad vigente no se relanza.
      if [[ "$model_tier" != "${MODEL_TIERS[0]}" ]] && ! check_authority; then
        escalation_blocked=1
        break
      fi

      # Checkpoint BEFORE
      bash "$STATE_SCRIPT" checkpoint \
        --task-id "$task_id" \
        --status in_progress \
        --model "$model_tier" >/dev/null 2>&1

      _log "  Attempting with model=$model_tier (timeout=${TASK_TIMEOUT_MIN}m)"

      # Execute with time-box
      local timeout_secs=$(( TASK_TIMEOUT_MIN * 60 ))
      task_exit_code=0

      if command -v timeout &>/dev/null; then
        timeout "$timeout_secs" bash -c \
          "run_agent_task '$sprint_id' '$task_id' '$description' '$model_tier'" \
          || task_exit_code=$?
      else
        # Fallback without timeout (stdlib only)
        run_agent_task "$sprint_id" "$task_id" "$description" "$model_tier" \
          || task_exit_code=$?
      fi

      if [[ "$task_exit_code" -eq 0 ]]; then
        succeeded=1
        break
      elif [[ "$task_exit_code" -eq 2 ]]; then
        # TOKEN_EXHAUSTION → escalate model
        _log "  TOKEN_EXHAUSTION on model=$model_tier — escalating"
        _audit "$sprint_id" "MODEL_ESCALATION task_id=$task_id from=$model_tier"
        # Update model_escalations counter in state
        if _jq_available; then
          local sf="$AGENT_RUNS_DIR/$sprint_id/state.json"
          local new_json
          new_json="$(jq '.model_escalations = (.model_escalations + 1)' "$sf")"
          local tmp_f
          tmp_f="$(mktemp "$(dirname "$sf")/.state-XXXXXX.tmp")"
          printf '%s\n' "$new_json" > "$tmp_f"
          mv -f "$tmp_f" "$sf"
        fi
        continue
      else
        # OOM / TIMEOUT / INFRA_ERROR — do NOT escalate model
        _warn "  task $task_id exit=$task_exit_code — no escalation (OOM/INFRA/TIMEOUT)"
        break
      fi
    done

    if [[ "$escalation_blocked" -eq 1 ]]; then
      local rest_ids
      rest_ids="$(_pending_tasks "$sprint_id" 2>/dev/null | grep -vx "$task_id" || true)"
      _authority_stop "$sprint_id" "$rest_ids" "$task_id"
      _audit "$sprint_id" "LOOP_STOP reason=$AUTHORITY_REASON tasks_run=$tasks_run done=$tasks_done failed=$tasks_failed escalation_of=$task_id"
      tasks_suspended=$(( tasks_suspended + AUTHORITY_SUSPENDED_N ))
      authority_stopped=1
      break
    fi

    # Checkpoint AFTER
    if [[ "$succeeded" -eq 1 ]]; then
      bash "$STATE_SCRIPT" complete --task-id "$task_id" >/dev/null 2>&1
      _audit "$sprint_id" "TASK_DONE task_id=$task_id model=$used_model"
      _coherence_register "$sprint_id" "$task_id" "$description"
      consecutive_failures=0
      tasks_done=$(( tasks_done + 1 ))
    else
      local fail_reason="exit_code=$task_exit_code"
      [[ "$task_exit_code" -eq 124 ]] && fail_reason="timeout_${TASK_TIMEOUT_MIN}m"
      bash "$STATE_SCRIPT" fail \
        --task-id "$task_id" \
        --reason "$fail_reason" >/dev/null 2>&1
      _audit "$sprint_id" "TASK_FAILED task_id=$task_id reason=$fail_reason"
      consecutive_failures=$(( consecutive_failures + 1 ))
      tasks_failed=$(( tasks_failed + 1 ))
      _warn "  task $task_id failed ($fail_reason); consecutive_failures=$consecutive_failures"
    fi

    tasks_run=$(( tasks_run + 1 ))
  done

  local ended_at
  ended_at="$(_now)"
  _audit "$sprint_id" "LOOP_END started_at=$started_at ended_at=$ended_at done=$tasks_done failed=$tasks_failed"

  _log "Loop ended: done=$tasks_done failed=$tasks_failed"
  [[ "$tasks_suspended" -gt 0 ]] && echo "$tasks_suspended tareas suspendidas por vigencia"
  _coherence_gate "$sprint_id"

  # Final status summary to stdout
  bash "$STATE_SCRIPT" status 2>/dev/null || true

  # SE-472: quien llama (cron, skill) distingue «lote completado» de «lote parado sin autoridad»
  [[ "$authority_stopped" -eq 1 ]] && return "$AUTHORITY_STOP_EXIT"
  return 0
}

# ── Entrypoint ───────────────────────────────────────────────────────────────
# Only run loop if script is invoked directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  parse_args "$@"
  run_loop
fi
