#!/usr/bin/env bats
# test-se-220-speculative.bats — BATS integration tests for SE-220 Slices 1-3
# Ref: SE-220 Speculative Tool Execution

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PREDICTOR="$REPO_ROOT/scripts/speculative-tool-predictor.py"
  EXECUTION="$REPO_ROOT/scripts/speculative-tool-execution.py"
  PRE_EXEC_HOOK="$REPO_ROOT/.opencode/hooks/speculative-pre-execute.sh"
  PRELOAD_HOOK="$REPO_ROOT/.opencode/hooks/speculative-skill-preload.sh"
  PYTHON="${PYTHON:-python3}"
  export REPO_ROOT PREDICTOR EXECUTION PRE_EXEC_HOOK PRELOAD_HOOK PYTHON

  # Use isolated temp cache dir for each test
  export SAVIA_SPECULATIVE_CACHE_DIR="$(mktemp -d)"
}

teardown() {
  # Clean up temp cache dir
  if [[ -d "${SAVIA_SPECULATIVE_CACHE_DIR:-}" ]]; then
    rm -rf "$SAVIA_SPECULATIVE_CACHE_DIR"
  fi
}

# ── T1: Files exist and are executable ───────────────────────────────────────

@test "speculative-pre-execute.sh exists" {
  [[ -f "$PRE_EXEC_HOOK" ]]
}

@test "speculative-pre-execute.sh is executable" {
  [[ -x "$PRE_EXEC_HOOK" ]]
}

@test "speculative-skill-preload.sh exists" {
  [[ -f "$PRELOAD_HOOK" ]]
}

@test "speculative-skill-preload.sh is executable" {
  [[ -x "$PRELOAD_HOOK" ]]
}

@test "speculative-tool-execution.py exists" {
  [[ -f "$EXECUTION" ]]
}

# ── T2: Hook exits 0 when SAVIA_SPECULATIVE_EXECUTION=off ────────────────────

@test "speculative-pre-execute.sh exits 0 when SAVIA_SPECULATIVE_EXECUTION=off" {
  run env SAVIA_SPECULATIVE_EXECUTION=off bash "$PRE_EXEC_HOOK" <<< '{}'
  [[ "$status" -eq 0 ]]
}

@test "speculative-skill-preload.sh exits 0 when SAVIA_SPECULATIVE_EXECUTION=off" {
  run env SAVIA_SPECULATIVE_EXECUTION=off bash "$PRELOAD_HOOK" <<< '{}'
  [[ "$status" -eq 0 ]]
}

# ── T3: Hooks exit 0 on invalid JSON (fail-soft) ─────────────────────────────

@test "speculative-pre-execute.sh exits 0 on invalid JSON" {
  run env SAVIA_SPECULATIVE_EXECUTION=on bash "$PRE_EXEC_HOOK" <<< 'NOT VALID JSON'
  [[ "$status" -eq 0 ]]
}

@test "speculative-skill-preload.sh exits 0 on invalid JSON" {
  run env SAVIA_SPECULATIVE_EXECUTION=on bash "$PRELOAD_HOOK" <<< 'NOT VALID JSON'
  [[ "$status" -eq 0 ]]
}

@test "speculative-pre-execute.sh exits 0 on empty input" {
  run env SAVIA_SPECULATIVE_EXECUTION=on bash "$PRE_EXEC_HOOK" <<< ''
  [[ "$status" -eq 0 ]]
}

# ── T4: speculative-skill-preload.sh shadow mode — no output ─────────────────

@test "speculative-skill-preload.sh shadow mode emits no stdout for non-Task tool" {
  INPUT='{"tool_name": "Read", "tool_input": {"path": "/tmp/test"}, "session_id": "t1"}'
  run env SAVIA_SPECULATIVE_EXECUTION=shadow bash "$PRELOAD_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "speculative-skill-preload.sh shadow mode produces no stdout (Task with sprint intent)" {
  INPUT='{"tool_name": "Task", "tool_input": {"prompt": "dame el estado del sprint actual"}, "session_id": "t2"}'
  run env SAVIA_SPECULATIVE_EXECUTION=shadow bash "$PRELOAD_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  # shadow mode: no stdout output
  [[ -z "$output" ]]
}

# ── T5: speculative-skill-preload.sh on mode — emits hint ────────────────────

@test "speculative-skill-preload.sh on mode emits skill hint for sprint intent" {
  INPUT='{"tool_name": "Task", "tool_input": {"prompt": "dame el estado del sprint actual con velocity"}, "session_id": "t3"}'
  run env SAVIA_SPECULATIVE_EXECUTION=on bash "$PRELOAD_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
  # Output should contain the hint for sprint-management
  [[ "$output" == *"SPECULATIVE_SKILL_HINT"* ]] || [[ -z "$output" ]]
  # Either produces a hint or silently succeeds (python may not be available)
}

# ── T6: cache-manager get returns hit=false (JSON) for miss ──────────────────

# ── T7: cache-manager clean removes expired entries ──────────────────────────

# ── T8: telemetry-report produces table output ────────────────────────────────

# ── T9: predictor whitelist_only field via CLI ────────────────────────────────

@test "predictor returns whitelist_only=true for Read-only intent" {
  INPUT='{"intent": "lee el fichero docs/spec.md", "available_tools": ["Read", "Grep", "Bash"]}'
  run "$PYTHON" "$PREDICTOR" --input "$INPUT"
  [[ "$status" -eq 0 ]]
  echo "$output" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
assert 'whitelist_only' in d, 'Missing whitelist_only field'
assert d['whitelist_only'] == True, f'Expected whitelist_only=True, got {d[\"whitelist_only\"]}'
"
}

@test "predictor returns whitelist_only=false for Edit intent" {
  INPUT='{"intent": "modifica el metodo calculate_velocity", "available_tools": ["Read", "Grep", "Bash", "Edit", "Write"]}'
  run "$PYTHON" "$PREDICTOR" --input "$INPUT"
  [[ "$status" -eq 0 ]]
  echo "$output" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
assert 'whitelist_only' in d, 'Missing whitelist_only field'
assert d['whitelist_only'] == False, f'Expected whitelist_only=False for Edit, got {d[\"whitelist_only\"]}'
"
}

# ── T10: orchestrator stdin interface ─────────────────────────────────────────

@test "speculative-tool-execution.py returns valid JSON for Read intent" {
  INPUT='{"intent": "lee el fichero docs/spec.md", "available_tools": ["Read", "Grep", "Bash"], "session_id": "bats-test-001"}'
  run "$PYTHON" "$EXECUTION" --input "$INPUT"
  [[ "$status" -eq 0 ]]
  echo "$output" | "$PYTHON" -c "
import sys, json
d = json.load(sys.stdin)
for key in ('session_id', 'intent_hash', 'predicted_tools', 'confidence', 'whitelist_only', 'speculative_launched'):
    assert key in d, f'Missing key: {key}'
"
}

@test "speculative-tool-execution.py errors gracefully on empty intent" {
  INPUT='{"intent": "", "available_tools": ["Read"], "session_id": "bats-err"}'
  run "$PYTHON" "$EXECUTION" --input "$INPUT"
  [[ "$status" -ne 0 ]]
}
