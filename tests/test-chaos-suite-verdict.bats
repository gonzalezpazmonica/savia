#!/usr/bin/env bats
# SE-383 chaos aggregation invariant: any FAIL makes the suite fail.
# Ref: docs/specs/SE-383-harness-chaos-suite.spec.md

SCRIPT="tests/chaos/run-chaos-suite.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
  cd /
}

@test "chaos runner exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "chaos runner keeps strict pipefail safety" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "chaos runner exposes a deterministic aggregate verdict" {
  grep -q 'aggregate_verdict' "$SCRIPT"
}

@test "aggregate accepts all-pass results" {
  run bash "$SCRIPT" --aggregate 8 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"8 PASS / 0 FAIL-RED"* ]]
}

@test "aggregate reports the complete passing count" {
  run bash "$SCRIPT" --aggregate 3 0
  [ "$status" -eq 0 ]
  [[ "$output" == "-- chaos suite: 3 PASS / 0 FAIL-RED" ]]
}

@test "aggregate emits one deterministic summary line" {
  run bash "$SCRIPT" --aggregate 2 0
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "aggregate rejects mixed pass and fail results" {
  run bash "$SCRIPT" --aggregate 7 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"7 PASS / 1 FAIL-RED"* ]]
}

@test "aggregate rejects all-fail results" {
  run bash "$SCRIPT" --aggregate 0 8
  [ "$status" -ne 0 ]
}

@test "aggregate rejects an empty scenario set" {
  run bash "$SCRIPT" --aggregate 0 0
  [ "$status" -ne 0 ]
}

@test "aggregate rejects missing counters" {
  run bash "$SCRIPT" --aggregate 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage"* ]]
}

@test "aggregate rejects negative counters" {
  run bash "$SCRIPT" --aggregate -1 0
  [ "$status" -eq 2 ]
}

@test "aggregate rejects non-numeric counters" {
  run bash "$SCRIPT" --aggregate one zero
  [ "$status" -eq 2 ]
}
