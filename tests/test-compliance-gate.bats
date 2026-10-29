#!/usr/bin/env bats
# BATS tests for compliance-gate.sh
# SCRIPT=.opencode/hooks/compliance-gate.sh
# SPEC: SPEC-081 — Hook test coverage
#
# Desde #1413 el PreToolUse compliance-gate no evalúa nada: la verificación la hace `.githooks/pre-commit`
# en el repo real del commit (tests/test-compliance-precommit.bats) y la CI con `runner.sh --range`.
# Esta suite fija que el hook no bloquea ni ejecuta el runner, para cualquier entrada.

SCRIPT=".opencode/hooks/compliance-gate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/compliance-gate"
  mkdir -p "$TEST_TMPDIR/.claude/compliance"
  # Un runner que fallaría siempre y deja marca: si el hook lo ejecutara, el test lo vería.
  printf '#!/bin/sh\ntouch "%s/ejecutado"\nexit 1\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/.claude/compliance/runner.sh"
  chmod +x "$TEST_TMPDIR/.claude/compliance/runner.sh"
  export CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
}

gate() {  # gate <orden>: entrada JSON por stdin, como la entrega el runtime
  local json; json=$(jq -n --arg c "$1" '{tool_input:{command:$c}}')
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SCRIPT"
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "script has set -uo pipefail" {
  head -5 "$SCRIPT" | grep -q "set -uo pipefail"
}

@test "git commit: sale con 0 y no ejecuta el runner (lo hace el pre-commit)" {
  gate "git commit -m x"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/ejecutado" ]
}

@test "otras órdenes y entrada vacía: salen con 0" {
  for c in "ls -la" "git push origin feature/x" "git diff"; do
    gate "$c"; [ "$status" -eq 0 ]
  done
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
}

@test "coverage: el hook documenta dónde se verifica ahora (pre-commit y CI)" {
  grep -q "githooks/pre-commit" "$SCRIPT"
  grep -q "Compliance runner" "$SCRIPT"
}

@test "coverage: el pre-commit de git ejecuta runner.sh --staged" {
  grep -q "runner.sh --staged" .githooks/pre-commit
}

@test "coverage: la CI ejecuta runner.sh --range sobre el diff de la PR" {
  grep -q "runner.sh --range" .github/workflows/ci.yml
}
