#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/containment-run.sh"
  CHECK="$BATS_TEST_DIRNAME/../scripts/containment-check.sh"
}

@test "fail-closed: N-contenido without Docker exits 2" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: N-hostil without Docker exits 2" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-hostil "echo should-fail"
  [ "$status" -eq 2 ]
}

@test "fail-closed: message explains what failed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo test"
  [[ "$output" =~ "BLOCKED" || "$output" =~ "not installed" || "$output" =~ "not available" ]]
}

@test "containment-check reports status even without Docker" {
  PATH=/nonexistent:$PATH run bash "$CHECK"
  [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

@test "containment-check --json produces valid JSON" {
  PATH=/nonexistent:$PATH run bash "$CHECK" --json
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['docker_available'] is False"
}

@test "session container start without Docker fails gracefully" {
  SESSION="$BATS_TEST_DIRNAME/../containment/session-container.sh"
  command -v docker >/dev/null 2>&1 && skip "docker presente: el caso sin Docker no es reproducible"
  PATH=/nonexistent:$PATH run -127 bash "$SESSION" start
  [[ "$output" == *"docker"* ]]
}

@test "adversarial suite reports test count" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh"
  [[ "$output" =~ "Results:" ]]
}

@test "adversarial suite --ci produces TAP output" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" --ci
  [[ "$output" =~ "TAP version" ]]
  [[ "$output" =~ "1..6" ]]
}
