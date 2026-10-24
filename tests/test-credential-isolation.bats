#!/usr/bin/env bats

setup() {
  TESTDIR=$(mktemp -d)
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/containment-run.sh"
  CHECK="$BATS_TEST_DIRNAME/../scripts/containment-check.sh"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "N-anfitrion runs on host" {
  run bash "$SCRIPT" N-anfitrion "echo host-ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"host-ok"* ]]
}

@test "N-contenido without Docker fails closed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo test"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]] || [[ "$output" == *"not installed"* ]]
}

@test "N-hostil without Docker fails closed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-hostil "echo test"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]] || [[ "$output" == *"not installed"* ]]
}

@test "Unknown level rejected" {
  run bash "$SCRIPT" N-unknown "echo test"
  [ "$status" -eq 2 ]
}

@test "container policy file exists" {
  [ -f "$BATS_TEST_DIRNAME/../containment/container-policy.json" ]
}

@test "Dockerfile.base exists and valid" {
  [ -f "$BATS_TEST_DIRNAME/../containment/Dockerfile.base" ]
  grep -q "FROM" "$BATS_TEST_DIRNAME/../containment/Dockerfile.base"
}

@test "session-container script exists and executable" {
  [ -f "$BATS_TEST_DIRNAME/../containment/session-container.sh" ]
  [ -x "$BATS_TEST_DIRNAME/../containment/session-container.sh" ]
}

@test "execution levels documented in policy" {
  [ -f "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md" ]
  grep -q "N-anfitrion" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
  grep -q "N-contenido" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
  grep -q "N-hostil" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
}

@test "classify-execution-level works" {
  run bash "$BATS_TEST_DIRNAME/../scripts/classify-execution-level.sh" --help 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: classify-execution-level.sh"* ]]
  [[ "$output" == *"N-anfitrion"* ]]
}

@test "safety: containment-run has set -uo pipefail" {
  head -2 "$SCRIPT" | grep -q "set -euo pipefail"
}

@test "safety: containment-check has set -uo pipefail" {
  head -2 "$CHECK" | grep -q "set -euo pipefail"
}

@test "safety: adversarial script has set -uo pipefail" {
  head -2 "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" | grep -q "set -euo pipefail"
}
