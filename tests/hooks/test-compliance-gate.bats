#!/usr/bin/env bats
# Tests for compliance-gate.sh hook (PreToolUse).
# Desde #1413 el hook no evalúa nada y sale siempre con 0: la verificación la hace `.githooks/pre-commit` en
# el repo real del commit (tests/test-compliance-precommit.bats) y la CI con `runner.sh --range`.
# Esta suite fija ese contrato también por la vía antigua (variable CLAUDE_TOOL_INPUT): con un runner que
# falla y deja marca, el hook no bloquea ni lo ejecuta.
# Ref: docs/rules/domain/hook-profiles.md

setup() {
  TMPDIR=$(mktemp -d)
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.opencode/hooks/compliance-gate.sh"
  export TEST_TMPDIR="$TMPDIR"
}

teardown() {
  rm -rf "$TMPDIR"
}

runner_que_falla() {  # runner que deja marca y sale con 1: si el hook lo ejecutara, el test lo vería
  mkdir -p "$TEST_TMPDIR/.claude/compliance"
  printf '#!/bin/bash\ntouch "%s/ejecutado"\necho warn >&2\nexit 1\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/.claude/compliance/runner.sh"
  chmod +x "$TEST_TMPDIR/.claude/compliance/runner.sh"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$HOOK"
}

@test "echo command passes through" {
  run bash -c "CLAUDE_TOOL_INPUT='echo hello' CLAUDE_PROJECT_DIR='$TEST_TMPDIR' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "git commit with no runner.sh passes" {
  run bash -c "CLAUDE_TOOL_INPUT='git commit -m test' CLAUDE_PROJECT_DIR='$TEST_TMPDIR' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "git commit con un runner que falla: sale con 0 y no lo ejecuta (lo hace el pre-commit)" {
  runner_que_falla
  run bash -c "CLAUDE_TOOL_INPUT='git commit -m test' CLAUDE_PROJECT_DIR='$TEST_TMPDIR' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/ejecutado" ]
}

@test "git commit por stdin JSON con un runner que falla: tampoco lo ejecuta" {
  runner_que_falla
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git commit -m x\"}}" | CLAUDE_PROJECT_DIR="$1" bash "$2"' _ "$TEST_TMPDIR" "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/ejecutado" ]
}

@test "el hook no contiene ninguna salida bloqueante ni llama al runner" {
  run grep -cE 'exit[[:space:]]+[12]' "$HOOK"
  [ "$output" = "0" ]
  run grep -cE '^[^#]*runner\.sh' "$HOOK"
  [ "$output" = "0" ]
}

@test "empty input passes" {
  run bash -c "CLAUDE_TOOL_INPUT='' CLAUDE_PROJECT_DIR='$TEST_TMPDIR' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"ERROR"* ]]
}

@test "nonexistent project dir handled" {
  run bash -c "CLAUDE_TOOL_INPUT='git commit -m test' CLAUDE_PROJECT_DIR='/tmp/nonexistent-$$' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "edge: empty input produces no error" {
  run bash -c "echo '{}' | SAVIA_HOOK_PROFILE=minimal bash '$BATS_TEST_DIRNAME/../../.opencode/hooks/validate-bash-global.sh' 2>&1"
  [ "$status" -eq 0 ]
}
