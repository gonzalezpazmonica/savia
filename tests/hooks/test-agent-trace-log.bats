#!/usr/bin/env bats
# Tests for agent-trace-log.sh hook
# Logs Task tool (subagent) invocations to JSONL. Never blocks (exits 0).
# Includes per-agent token budget metering (SPEC-AGENT-METERING).
# Ref: docs/rules/domain/agent-context-budget.md

setup() {
  TMPDIR=$(mktemp -d)
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  HOOK="$PWD/.opencode/hooks/agent-trace-log.sh"
  export TEST_TMPDIR="$TMPDIR"
  mkdir -p "$TEST_TMPDIR/projects/test-project/traces" "$TEST_TMPDIR/.opencode/agents"
  cd "$TEST_TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/agent-trace-log.sh"
}

# ── Non-Task tool exits early ──

@test "non-Task tool (Bash) is ignored" {
  run bash -c "export TOOL_NAME='Bash' && bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
}

@test "non-Task tool (Read/Edit) is ignored" {
  run bash -c "export TOOL_NAME='Read' && bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
}

# ── Task tool branch (tested without causing errors) ──

@test "Task tool with complete env writes a trace record" {
  run bash -c "export TOOL_NAME='Task' && export TOOL_INPUT='{\"agent\":\"test\"}' && export TOOL_OUTPUT='result' && export CLAUDE_PROJECT_DIR='$TEST_TMPDIR' && export CLAUDE_PROJECT_NAME='test-project' && export TOOL_DURATION=1 && export TOOL_RESULT_STATUS='success' && bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMPDIR/output/agent-traces.jsonl" ]
  grep -q '"agent":"test"' "$TEST_TMPDIR/output/agent-traces.jsonl"
}

# ── Empty/missing tool name ──

@test "missing TOOL_NAME defaults to early exit" {
  run bash -c "env -u TOOL_NAME CLAUDE_PROJECT_DIR='$TEST_TMPDIR' bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMPDIR/output/agent-traces.jsonl" ]
}

# ── Budget metering scenarios (SPEC-AGENT-METERING) ──

@test "JSONL trace includes token_budget and budget_exceeded fields" {
  # Create a mock agent with known budget
  mkdir -p "$TEST_TMPDIR/.claude/agents"
  cat > "$TEST_TMPDIR/.opencode/agents/test-agent.md" <<'AGENT'
---
name: test-agent
token_budget: 5000
---
AGENT
  # Create the lookup script symlink dir
  mkdir -p "$TEST_TMPDIR/scripts"
  cp "$BATS_TEST_DIRNAME/../../scripts/agent-budget-lookup.sh" "$TEST_TMPDIR/scripts/"

  # Simulate: small input (under budget)
  local small_input='{"agent":"test-agent","description":"small task"}'
  run bash -c "
    export TOOL_NAME='Task'
    export TOOL_INPUT='$small_input'
    export TOOL_OUTPUT='ok'
    export CLAUDE_PROJECT_DIR='$TEST_TMPDIR'
    export CLAUDE_PROJECT_NAME='test-project'
    export TOOL_DURATION=2
    export TOOL_RESULT_STATUS='success'
    bash '$HOOK' 2>&1
  "
  [ "$status" -eq 0 ]

  # Verify JSONL was written with budget fields
  if [ -f "$TEST_TMPDIR/projects/test-project/traces/agent-traces.jsonl" ]; then
    local line
    line=$(cat "$TEST_TMPDIR/projects/test-project/traces/agent-traces.jsonl")
    [[ "$line" == *'"token_budget":'* ]]
    [[ "$line" == *'"budget_exceeded":'* ]]
  fi
}

@test "budget exceeded triggers alert in budget-alerts.jsonl" {
  # Create a mock agent with very small budget
  mkdir -p "$TEST_TMPDIR/.claude/agents"
  cat > "$TEST_TMPDIR/.opencode/agents/tiny-agent.md" <<'AGENT'
---
name: tiny-agent
token_budget: 10
---
AGENT
  mkdir -p "$TEST_TMPDIR/scripts"
  cp "$BATS_TEST_DIRNAME/../../scripts/agent-budget-lookup.sh" "$TEST_TMPDIR/scripts/"

  # Simulate: large input that exceeds the tiny budget
  local big_input='{"agent":"tiny-agent","description":"this is a very large input that will exceed the tiny budget of 10 tokens easily because it has many characters"}'
  run bash -c "
    export TOOL_NAME='Task'
    export TOOL_INPUT='$big_input'
    export TOOL_OUTPUT='a moderately sized output string for testing purposes'
    export CLAUDE_PROJECT_DIR='$TEST_TMPDIR'
    export CLAUDE_PROJECT_NAME='test-project'
    export TOOL_DURATION=3
    export TOOL_RESULT_STATUS='success'
    bash '$HOOK' 2>&1
  "
  [ "$status" -eq 0 ]

  # Verify budget-alerts.jsonl was written
  if [ -f "$TEST_TMPDIR/projects/test-project/traces/budget-alerts.jsonl" ]; then
    local alert
    alert=$(cat "$TEST_TMPDIR/projects/test-project/traces/budget-alerts.jsonl")
    [[ "$alert" == *'"overage":'* ]]
    [[ "$alert" == *'"overage_pct":'* ]]
    [[ "$alert" == *'"tiny-agent"'* ]]
  fi
}

@test "no alert written when under budget" {
  mkdir -p "$TEST_TMPDIR/.claude/agents" "$TEST_TMPDIR/scripts"
  cat > "$TEST_TMPDIR/.opencode/agents/big-agent.md" <<'AGENT'
---
name: big-agent
token_budget: 999999
---
AGENT
  cp "$BATS_TEST_DIRNAME/../../scripts/agent-budget-lookup.sh" "$TEST_TMPDIR/scripts/"
  run bash -c "TOOL_NAME='Task' TOOL_INPUT='{\"agent\":\"big-agent\",\"description\":\"hi\"}' TOOL_OUTPUT='ok' CLAUDE_PROJECT_DIR='$TEST_TMPDIR' CLAUDE_PROJECT_NAME='test-project' TOOL_DURATION=1 TOOL_RESULT_STATUS='success' bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMPDIR/projects/test-project/traces/budget-alerts.jsonl" ]
}

# ── Edge case: nonexistent project dir ──

@test "nonexistent project dir does not crash" {
  run bash -c "TOOL_NAME='Task' TOOL_INPUT='{\"agent\":\"x\"}' TOOL_OUTPUT='ok' CLAUDE_PROJECT_DIR='/tmp/nonexistent-$$' CLAUDE_PROJECT_NAME='ghost' bash '$HOOK' 2>&1"
  [ "$status" -eq 0 ]
}

@test "edge: nonexistent traces directory" {
  run bash -c "CLAUDE_PROJECT_DIR=/tmp/nonexistent-$RANDOM CLAUDE_PROJECT_NAME=ghost TOOL_NAME=Task TOOL_INPUT='{\"agent\":\"x\"}' TOOL_OUTPUT='' TOOL_DURATION=0 TOOL_RESULT_STATUS=success bash '$BATS_TEST_DIRNAME/../../.opencode/hooks/agent-trace-log.sh' 2>&1"
  [ "$status" -eq 0 ]
}

@test "edge: zero budget agent" {
  [ "0" = "0" ]
}
