#!/usr/bin/env bats
# Ref: docs/rules/domain/agent-context-budget.md

setup() {
  TMPDIR=$(mktemp -d)
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/agent-budget-lookup.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$SCRIPT"
}

@test "known agent returns correct budget (Heavy)" {
  result=$(bash "$SCRIPT" architect)
  [[ "$result" == "13000" ]]
}

@test "known agent returns correct budget (Standard)" {
  result=$(bash "$SCRIPT" dotnet-developer)
  [[ "$result" == "8500" ]]
}

@test "known agent returns correct budget (Light)" {
  result=$(bash "$SCRIPT" tech-writer)
  [[ "$result" == "4500" ]]
}

@test "known agent returns correct budget (Minimal)" {
  result=$(bash "$SCRIPT" azure-devops-operator)
  [[ "$result" == "2200" ]]
}

@test "unknown agent returns 0" {
  result=$(bash "$SCRIPT" nonexistent-agent)
  [[ "$result" == "0" ]]
}

@test "no argument returns 0" {
  result=$(bash "$SCRIPT")
  [[ "$result" == "0" ]]
}

@test "exit code is always 0" {
  bash "$SCRIPT" nonexistent-agent
  [[ $? -eq 0 ]]
  bash "$SCRIPT"
  [[ $? -eq 0 ]]
}

# ── Negative cases ──

@test "invalid agent with empty string returns 0" {
  result=$(bash "$SCRIPT" "")
  [[ "$result" == "0" ]]
}

@test "bad agent name with dots fails gracefully" {
  run bash "$SCRIPT" "bad.agent.name"
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]]
}

# ── Edge cases ──

@test "agent name with special characters returns 0" {
  result=$(bash "$SCRIPT" "agent-with-many-dashes-here")
  [ "$result" == "0" ]
  grep -q "0" <<< "$result"
}

@test "boundary: max budget agent returns expected value" {
  # SPEC-AGENT-METERING defines Heavy tier at 13000
  result=$(bash "$SCRIPT" architect)
  python3 -c "import json; assert $result == 13000"
}

@test "core hooks use safety flags" {
  grep -q "set -[euo]" "$REPO_ROOT/.opencode/hooks/validate-bash-global.sh"
}
