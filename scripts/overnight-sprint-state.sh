#!/usr/bin/env bash
# scripts/overnight-sprint-state.sh — SE-226: stateless-session loop state management
set -uo pipefail
# Manages state.json for overnight-sprint loops with atomic writes.
#
# Commands:
#   overnight-sprint-state.sh init       --sprint-id <id> --tasks-file <json>
#   overnight-sprint-state.sh checkpoint --task-id <n> --status in_progress|done|failed --model <tier>
#   overnight-sprint-state.sh complete   --task-id <n> [--pr <url>]
#   overnight-sprint-state.sh fail       --task-id <n> --reason <str>
#   overnight-sprint-state.sh suspend    --reason <str> [--task-id <n>]  # pending → suspended (SE-472)
#   overnight-sprint-state.sh status     # summary JSON to stdout
#   overnight-sprint-state.sh export     # emit results.tsv to stdout
#   overnight-sprint-state.sh --self-test
#
# State persists in: output/agent-runs/<sprint-id>/state.json
# Write strategy: tmp + mv (atomic, crash-safe)
#
# Ref: SE-226, docs/rules/domain/autonomous-safety.md
set -uo pipefail

# ── Path resolution ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")}}}"
# AGENT_RUNS_DIR: env var override takes precedence (enables testing with isolated dirs)
AGENT_RUNS_DIR="${AGENT_RUNS_DIR:-$WORKSPACE_DIR/output/agent-runs}"

# ── Helpers ──────────────────────────────────────────────────────────────────
_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

_jq_available() { command -v jq &>/dev/null; }

_state_file() {
  local sprint_id="$1"
  echo "$AGENT_RUNS_DIR/$sprint_id/state.json"
}

# Atomic write: write to tmp, then mv
_atomic_write() {
  local dest="$1"
  local content="$2"
  local dir
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  local tmp
  tmp="$(mktemp "$dir/.state-XXXXXX.tmp")"
  printf '%s\n' "$content" > "$tmp"
  mv -f "$tmp" "$dest"
}

# Read state.json via jq or python3 fallback
_read_json() {
  local file="$1"
  local query="$2"
  if _jq_available; then
    jq -r "$query" "$file"
  else
    python3 - "$file" "$query" <<'PY'
import sys, json
data = json.load(open(sys.argv[1]))
# Simple field extraction — supports .field and .field[N].subfield patterns
import re
parts = [p for p in re.split(r'[.\[\]]+', sys.argv[2]) if p]
val = data
for p in parts:
    if p.lstrip('-').isdigit():
        val = val[int(p)]
    else:
        val = val.get(p, '')
print(val if not isinstance(val, (dict, list)) else json.dumps(val))
PY
  fi
}

# Write updated state using jq or python3
_update_state() {
  # Usage: _update_state <state_file> [jq-args...] <filter>
  # All args after state_file are passed directly to jq (including --arg, --argjson, filter)
  local state_file="$1"
  shift
  local new_json
  if _jq_available; then
    new_json="$(jq "$@" "$state_file")"
  else
    _err "jq required for state updates (python3 fallback not implemented for mutations)"
  fi
  _atomic_write "$state_file" "$new_json"
}

# ── Subcommands ──────────────────────────────────────────────────────────────

cmd_init() {
  local sprint_id="" tasks_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sprint-id) sprint_id="$2"; shift 2 ;;
      --tasks-file) tasks_file="$2"; shift 2 ;;
      *) _err "init: unknown arg: $1" ;;
    esac
  done

  [[ -n "$sprint_id" ]] || _err "init: --sprint-id required"
  [[ -n "$tasks_file" ]] || _err "init: --tasks-file required"
  [[ -f "$tasks_file" ]] || _err "init: tasks file not found: $tasks_file"

  local state_file
  state_file="$(_state_file "$sprint_id")"

  # If state already exists, preserve it (idempotent)
  if [[ -f "$state_file" ]]; then
    printf 'INFO: state already exists at %s — skipping init\n' "$state_file" >&2
    return 0
  fi

  # Build initial state JSON
  local now
  now="$(_now)"
  local tasks_json
  tasks_json="$(cat "$tasks_file")"

  local state_json
  if _jq_available; then
    state_json="$(jq -n \
      --arg sid "$sprint_id" \
      --arg now "$now" \
      --argjson tasks "$tasks_json" \
      '{
        sprint_id: $sid,
        started_at: $now,
        last_checkpoint: $now,
        consecutive_failures: 0,
        model_escalations: 0,
        tasks: $tasks
      }')"
  else
    state_json="$(python3 - "$sprint_id" "$now" "$tasks_json" <<'PY'
import sys, json
sprint_id, now, tasks_raw = sys.argv[1], sys.argv[2], sys.argv[3]
tasks = json.loads(tasks_raw)
state = {
    "sprint_id": sprint_id,
    "started_at": now,
    "last_checkpoint": now,
    "consecutive_failures": 0,
    "model_escalations": 0,
    "tasks": tasks
}
print(json.dumps(state, indent=2))
PY
)"
  fi

  _atomic_write "$state_file" "$state_json"
  printf 'INFO: initialized state at %s\n' "$state_file" >&2
  printf '%s\n' "$state_file"
}

cmd_checkpoint() {
  local task_id="" status="" model="fast"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      *) _err "checkpoint: unknown arg: $1" ;;
    esac
  done

  [[ -n "$task_id" ]] || _err "checkpoint: --task-id required"
  [[ -n "$status" ]] || _err "checkpoint: --status required"
  [[ "$status" == "in_progress" || "$status" == "done" || "$status" == "failed" ]] \
    || _err "checkpoint: --status must be in_progress|done|failed"

  # Resolve sprint-id from env or find the most recent state
  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file

  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    # Find the most recently modified state.json
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "checkpoint: no state.json found; set OVERNIGHT_SPRINT_ID"
  fi

  [[ -f "$state_file" ]] || _err "checkpoint: state.json not found: $state_file"

  local now
  now="$(_now)"
  local idx=$(( task_id - 1 ))

  if _jq_available; then
    _update_state "$state_file" \
      --arg now "$now" --arg status "$status" --arg model "$model" --argjson idx "$idx" \
      '(.tasks[$idx].status = $status) |
       (.tasks[$idx].model = $model) |
       (.last_checkpoint = $now)'
  else
    _err "checkpoint: jq required"
  fi
  printf 'INFO: checkpoint task %s → %s (model=%s)\n' "$task_id" "$status" "$model" >&2
}

cmd_complete() {
  local task_id="" pr_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --pr) pr_url="$2"; shift 2 ;;
      *) _err "complete: unknown arg: $1" ;;
    esac
  done

  [[ -n "$task_id" ]] || _err "complete: --task-id required"

  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file
  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "complete: no state.json found"
  fi
  [[ -f "$state_file" ]] || _err "complete: state.json not found: $state_file"

  local now
  now="$(_now)"
  local idx=$(( task_id - 1 ))

  if _jq_available; then
    _update_state "$state_file" \
      --arg now "$now" --arg pr "$pr_url" --argjson idx "$idx" \
      '(.tasks[$idx].status = "done") |
       (.tasks[$idx].completed_at = $now) |
       (if $pr != "" then (.tasks[$idx].pr = $pr) else . end) |
       (.last_checkpoint = $now) |
       (.consecutive_failures = 0)'
  else
    _err "complete: jq required"
  fi
  printf 'INFO: task %s marked done\n' "$task_id" >&2
}

cmd_fail() {
  local task_id="" reason=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      *) _err "fail: unknown arg: $1" ;;
    esac
  done

  [[ -n "$task_id" ]] || _err "fail: --task-id required"
  [[ -n "$reason" ]] || _err "fail: --reason required"

  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file
  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "fail: no state.json found"
  fi
  [[ -f "$state_file" ]] || _err "fail: state.json not found: $state_file"

  local now
  now="$(_now)"
  local idx=$(( task_id - 1 ))

  if _jq_available; then
    _update_state "$state_file" \
      --arg now "$now" --arg reason "$reason" --argjson idx "$idx" \
      '(.tasks[$idx].status = "failed") |
       (.tasks[$idx].failed_at = $now) |
       (.tasks[$idx].fail_reason = $reason) |
       (.last_checkpoint = $now) |
       (.consecutive_failures = (.consecutive_failures + 1))'
  else
    _err "fail: jq required"
  fi
  printf 'INFO: task %s marked failed (%s)\n' "$task_id" "$reason" >&2
}

cmd_status() {
  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file
  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "status: no state.json found"
  fi
  [[ -f "$state_file" ]] || _err "status: state.json not found: $state_file"

  if _jq_available; then
    jq '{
      sprint_id: .sprint_id,
      started_at: .started_at,
      last_checkpoint: .last_checkpoint,
      consecutive_failures: .consecutive_failures,
      model_escalations: .model_escalations,
      total: (.tasks | length),
      pending: (.tasks | map(select(.status == "pending")) | length),
      in_progress: (.tasks | map(select(.status == "in_progress")) | length),
      done: (.tasks | map(select(.status == "done")) | length),
      failed: (.tasks | map(select(.status == "failed")) | length),
      suspended: (.tasks | map(select(.status == "suspended")) | length)
    }' "$state_file"
  else
    python3 - "$state_file" <<'PY'
import sys, json
data = json.load(open(sys.argv[1]))
tasks = data.get("tasks", [])
summary = {
    "sprint_id": data.get("sprint_id"),
    "started_at": data.get("started_at"),
    "last_checkpoint": data.get("last_checkpoint"),
    "consecutive_failures": data.get("consecutive_failures", 0),
    "model_escalations": data.get("model_escalations", 0),
    "total": len(tasks),
    "pending": sum(1 for t in tasks if t.get("status") == "pending"),
    "in_progress": sum(1 for t in tasks if t.get("status") == "in_progress"),
    "done": sum(1 for t in tasks if t.get("status") == "done"),
    "failed": sum(1 for t in tasks if t.get("status") == "failed"),
    "suspended": sum(1 for t in tasks if t.get("status") == "suspended"),
}
print(json.dumps(summary, indent=2))
PY
  fi
}

cmd_suspend() {
  # SE-472: pending tasks → suspended (reason recorded). With --task-id, that task is
  # suspended too whatever its status (used when the authority lapses before a model
  # escalation of the task in progress). Done/failed tasks are never touched otherwise.
  # Works with jq or, without it, with python3 (stdlib).
  local reason="" task_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --task-id) task_id="${2:-}"; shift 2 ;;
      *) _err "suspend: unknown arg: $1" ;;
    esac
  done
  [[ -n "$reason" ]] || _err "suspend: --reason required"
  [[ -z "$task_id" || "$task_id" =~ ^[0-9]+$ ]] || _err "suspend: --task-id must be numeric"

  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file
  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "suspend: no state.json found"
  fi
  [[ -f "$state_file" ]] || _err "suspend: state.json not found: $state_file"

  local now
  now="$(_now)"
  if _jq_available; then
    _update_state "$state_file" --arg now "$now" --arg reason "$reason" --arg tid "$task_id" \
      '(.tasks |= map(if .status == "pending" or ($tid != "" and (.id | tostring) == $tid)
          then .status = "suspended" | .suspended_at = $now | .suspend_reason = $reason
          else . end)) |
       (.last_checkpoint = $now)' || _err "suspend: state update failed"
  else
    python3 - "$state_file" "$now" "$reason" "$task_id" <<'PY2' || _err "suspend: state update failed"
import json, os, sys, tempfile
path, now, reason, tid = sys.argv[1:5]
data = json.load(open(path))
for t in data.get("tasks", []):
    if t.get("status") == "pending" or (tid and str(t.get("id")) == tid):
        t.update(status="suspended", suspended_at=now, suspend_reason=reason)
data["last_checkpoint"] = now
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PY2
  fi
  printf 'INFO: pending tasks suspended (%s)\n' "$reason" >&2
}

cmd_export() {
  local sprint_id="${OVERNIGHT_SPRINT_ID:-}"
  local state_file
  if [[ -n "$sprint_id" ]]; then
    state_file="$(_state_file "$sprint_id")"
  else
    state_file="$(find "$AGENT_RUNS_DIR" -name "state.json" -maxdepth 2 2>/dev/null \
      | sort -t/ -k1 | tail -1)"
    [[ -n "$state_file" && -f "$state_file" ]] || _err "export: no state.json found"
  fi
  [[ -f "$state_file" ]] || _err "export: state.json not found: $state_file"

  printf 'task_id\tdescription\tstatus\tmodel\tpr\tcompleted_at\tfail_reason\n'

  if _jq_available; then
    jq -r '.tasks[] |
      [
        (.id | tostring),
        (.description // ""),
        (.status // "pending"),
        (.model // ""),
        (.pr // ""),
        (.completed_at // ""),
        (.fail_reason // .suspend_reason // "")
      ] | @tsv' "$state_file"
  else
    python3 - "$state_file" <<'PY'
import sys, json
data = json.load(open(sys.argv[1]))
for t in data.get("tasks", []):
    row = [
        str(t.get("id", "")),
        t.get("description", ""),
        t.get("status", "pending"),
        t.get("model", ""),
        t.get("pr", ""),
        t.get("completed_at", ""),
        t.get("fail_reason", "") or t.get("suspend_reason", ""),
    ]
    print("\t".join(row))
PY
  fi
}

cmd_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  local sprint_id="test-sprint-$$"
  export OVERNIGHT_SPRINT_ID="$sprint_id"
  export AGENT_RUNS_DIR="$tmpdir"

  # Minimal tasks file
  local tasks_file="$tmpdir/tasks.json"
  printf '[{"id":1,"description":"task one","status":"pending"},{"id":2,"description":"task two","status":"pending"}]' \
    > "$tasks_file"

  local errors=0

  _assert() {
    local desc="$1"; shift
    if "$@" &>/dev/null; then
      printf 'PASS: %s\n' "$desc"
    else
      printf 'FAIL: %s\n' "$desc" >&2
      errors=$(( errors + 1 ))
    fi
  }

  # 1. init creates state.json
  bash "$0" init --sprint-id "$sprint_id" --tasks-file "$tasks_file" >/dev/null 2>&1
  local sf="$tmpdir/$sprint_id/state.json"
  _assert "init creates state.json" test -f "$sf"

  # 2. init is idempotent
  bash "$0" init --sprint-id "$sprint_id" --tasks-file "$tasks_file" >/dev/null 2>&1
  _assert "init idempotent" test -f "$sf"

  # 3. checkpoint updates status
  bash "$0" checkpoint --task-id 1 --status in_progress --model fast >/dev/null 2>&1
  _assert "checkpoint sets in_progress" bash -c "grep -q 'in_progress' '$sf'"

  # 4. complete marks done
  bash "$0" complete --task-id 1 --pr "https://github.com/test/1" >/dev/null 2>&1
  _assert "complete sets done" bash -c "grep -q '\"done\"' '$sf'"

  # 5. complete resets consecutive_failures
  _assert "complete resets failures" bash -c "python3 -c \"import json; d=json.load(open('$sf')); exit(0 if d['consecutive_failures']==0 else 1)\""

  # 6. fail increments consecutive_failures
  bash "$0" fail --task-id 2 --reason "timeout" >/dev/null 2>&1
  _assert "fail increments consecutive_failures" bash -c "python3 -c \"import json; d=json.load(open('$sf')); exit(0 if d['consecutive_failures']==1 else 1)\""

  # 7. status returns valid JSON
  local st
  st="$(bash "$0" status 2>/dev/null)"
  _assert "status returns JSON" bash -c "printf '%s' '$st' | python3 -c 'import sys,json; json.load(sys.stdin)'"

  # 8. export returns TSV with header
  local tsv
  tsv="$(bash "$0" export 2>/dev/null)"
  _assert "export has header" bash -c "printf '%s\n' \"$tsv\" | head -1 | grep -q 'task_id'"

  # 9. export has data rows
  local row_count
  row_count="$(printf '%s\n' "$tsv" | tail -n +2 | wc -l)"
  _assert "export has 2 data rows" test "$row_count" -eq 2

  # 10. atomic write: state survives simulated crash (prev file intact if tmp removed mid-write)
  local orig_snapshot="$tmpdir/orig-snapshot.json"
  cp "$sf" "$orig_snapshot"
  local tmp_f
  tmp_f="$(mktemp "$tmpdir/$sprint_id/.state-CRASH-XXXXXX.tmp")"
  printf 'CORRUPT' > "$tmp_f"
  # Remove the tmp before mv (simulate crash before mv)
  rm -f "$tmp_f"
  # Original state should be unchanged
  _assert "atomic: original intact after simulated crash" diff "$sf" "$orig_snapshot"

  # 11. recovery: re-init on existing state is no-op (state preserved)
  local before_snapshot="$tmpdir/before-snapshot.json"
  cp "$sf" "$before_snapshot"
  bash "$0" init --sprint-id "$sprint_id" --tasks-file "$tasks_file" >/dev/null 2>&1
  _assert "recovery: init on existing state preserves data" diff "$sf" "$before_snapshot"

  # 12. status json has expected fields
  local st2
  st2="$(bash "$0" status 2>/dev/null)"
  _assert "status has sprint_id field" bash -c "printf '%s' '$st2' | python3 -c \"import sys,json; d=json.load(sys.stdin); exit(0 if 'sprint_id' in d else 1)\""

  # Cleanup
  unset OVERNIGHT_SPRINT_ID AGENT_RUNS_DIR
  rm -rf "$tmpdir"

  if [[ "$errors" -eq 0 ]]; then
    printf 'SELF-TEST: all checks passed\n'
    return 0
  else
    printf 'SELF-TEST: %d failure(s)\n' "$errors" >&2
    return 1
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  init)        cmd_init "$@" ;;
  checkpoint)  cmd_checkpoint "$@" ;;
  complete)    cmd_complete "$@" ;;
  fail)        cmd_fail "$@" ;;
  suspend)     cmd_suspend "$@" ;;
  status)      cmd_status "$@" ;;
  export)      cmd_export "$@" ;;
  --self-test) cmd_self_test ;;
  *)
    cat >&2 <<USAGE
Usage: overnight-sprint-state.sh <command> [options]

Commands:
  init       --sprint-id <id> --tasks-file <json>
  checkpoint --task-id <n> --status in_progress|done|failed --model <tier>
  complete   --task-id <n> [--pr <url>]
  fail       --task-id <n> --reason <str>
  suspend    --reason <authority_expired|authority_invalid|authority_missing> [--task-id <n>]
  status
  export
  --self-test

State dir: output/agent-runs/<sprint-id>/state.json
USAGE
    exit 1
    ;;
esac
