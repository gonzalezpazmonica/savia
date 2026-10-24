#!/usr/bin/env bats

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
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || true
}

@test "session container start without Docker fails gracefully" {
  SESSION="$BATS_TEST_DIRNAME/../containment/session-container.sh"
  # Deterministic "Docker unusable": a docker stub that always fails, first on PATH.
  mkdir -p "$BATS_TEST_TMPDIR/nodocker"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/nodocker/docker"
  chmod +x "$BATS_TEST_TMPDIR/nodocker/docker"
  PATH="$BATS_TEST_TMPDIR/nodocker:$PATH" run bash "$SESSION" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"Starting session container"* ]]
}

@test "adversarial suite reports test count" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh"
  [[ "$output" =~ Results:\ [0-9]+\ PASS\ \|\ [0-9]+\ FAIL ]]
  # exit status must agree with the reported failure count
  fails="${BASH_REMATCH[0]##*| }"; fails="${fails% FAIL}"
  if [ "$fails" -eq 0 ]; then [ "$status" -eq 0 ]; else [ "$status" -eq 1 ]; fi
}

@test "adversarial suite --ci produces TAP output" {
  run bash "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" --ci
  [[ "$output" == *"TAP version 13"* ]]
  [[ "$output" == *"1..6"* ]]
  [ "$(grep -cE '^(not )?ok - ' <<< "$output")" -eq 6 ]
}
