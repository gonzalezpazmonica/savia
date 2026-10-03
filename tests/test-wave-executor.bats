#!/usr/bin/env bats
# Tests for wave-executor.sh — DAG scheduling engine
# Ref: .opencode/skills/dag-scheduling/SKILL.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/wave-executor.sh"
  export FIXTURES="$REPO_ROOT/tests/fixtures"
  TMPDIR_WE=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_WE"
}

@test "happy path: 3 tasks 2 waves all succeed" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-happy.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "success"'
  echo "$output" | jq -e '.total_waves == 2'
  echo "$output" | jq -e '.total_tasks == 3'
}

@test "diamond dependency: A->B,C->D = 3 waves" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-diamond.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_waves == 3'
  echo "$output" | jq -e '.waves[0].tasks[0].id == "A"'
}

@test "empty task graph succeeds with 0 waves" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-empty.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "success"'
  echo "$output" | jq -e '.total_waves == 0'
}

@test "cycle detected exits 2" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-cycle.json"
  [ "$status" -eq 2 ]
}

@test "missing dependency exits 2" {
  local tmp=$(mktemp)
  echo '{"tasks":[{"id":"test","command":"echo t","depends_on":["compile"]}]}' > "$tmp"
  run bash "$SCRIPT" "$tmp"
  [ "$status" -eq 2 ]
  rm -f "$tmp"
}

@test "duplicate task ID exits 2" {
  local tmp=$(mktemp)
  echo '{"tasks":[{"id":"build","command":"echo 1","depends_on":[]},{"id":"build","command":"echo 2","depends_on":[]}]}' > "$tmp"
  run bash "$SCRIPT" "$tmp"
  [ "$status" -eq 2 ]
  rm -f "$tmp"
}

@test "task fails mid-wave exits 1" {
  local tmp=$(mktemp)
  echo '{"tasks":[{"id":"good","command":"true","depends_on":[]},{"id":"bad","command":"false","depends_on":[]}]}' > "$tmp"
  run bash "$SCRIPT" "$tmp"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "failed"'
  rm -f "$tmp"
}

@test "overflow splits into sub-waves" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-overflow.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.total_waves == 2'
}

@test "missing expected file fails task" {
  local tmp=$(mktemp)
  echo '{"tasks":[{"id":"gen","command":"true","depends_on":[],"expected_files":["/tmp/nonexistent-wave-test-file.xyz"]}]}' > "$tmp"
  run bash "$SCRIPT" "$tmp"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.waves[0].tasks[0].expected_files_present == false'
  rm -f "$tmp"
}

@test "report flag writes to file" {
  local rpt=$(mktemp)
  run bash "$SCRIPT" "$FIXTURES/wave-dag-happy.json" --report "$rpt"
  [ "$status" -eq 0 ]
  jq -e '.status == "success"' "$rpt"
  rm -f "$rpt"
}

@test "no arguments exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "nonexistent file exits 2" {
  run bash "$SCRIPT" "/tmp/no-such-file-wave.json"
  [ "$status" -eq 2 ]
}

# ── Negative cases ──

@test "invalid JSON content exits with error" {
  echo "not valid json" > "$TMPDIR_WE/bad.json"
  run bash "$SCRIPT" "$TMPDIR_WE/bad.json"
  [ "$status" -ne 0 ]
}

@test "tasks with failing command report failure" {
  echo '{"tasks":[{"id":"fail1","command":"exit 42","depends_on":[]}]}' > "$TMPDIR_WE/fail-cmd.json"
  run bash "$SCRIPT" "$TMPDIR_WE/fail-cmd.json"
  [ "$status" -ne 0 ]
}

# ── Edge case ──

@test "single task with no dependencies succeeds" {
  echo '{"tasks":[{"id":"solo","command":"echo hello","depends_on":[]}]}' > "$TMPDIR_WE/solo.json"
  run bash "$SCRIPT" "$TMPDIR_WE/solo.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"solo"* ]]
  echo "$output" | jq -e '.total_tasks == 1'
}

@test "happy path output contains success status string" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-happy.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"success"* ]]
}

@test "cycle detection output indicates error" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-cycle.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cycle"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"Cycle"* ]]
}

# ── Interfaz y señales (SE-376) ──

@test "usage: --report sin ruta sale por usage con exit 2" {
  run bash "$SCRIPT" "$FIXTURES/wave-dag-happy.json" --report
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "is_posint: SDD_MAX_PARALLEL_AGENTS no numérico es invalid (exit 2)" {
  SDD_MAX_PARALLEL_AGENTS=abc run bash "$SCRIPT" "$FIXTURES/wave-dag-happy.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"SDD_MAX_PARALLEL_AGENTS"* ]]
}

@test "on_signal: SIGHUP al motor termina sus tareas y sale con 143" {
  echo '{"tasks":[{"id":"long","command":"sleep 23.417","depends_on":[]}]}' > "$TMPDIR_WE/long.json"
  bash "$SCRIPT" "$TMPDIR_WE/long.json" >/dev/null 2>&1 &
  local ep=$! i rc=0
  for i in $(seq 1 50); do pgrep -x -f "sleep 23.417" >/dev/null && break; sleep 0.1; done
  kill -HUP "$ep"
  wait "$ep" || rc=$?
  [ "$rc" -eq 143 ]
  sleep 0.3
  run pgrep -x -f "sleep 23.417"
  [ "$status" -ne 0 ]
}
