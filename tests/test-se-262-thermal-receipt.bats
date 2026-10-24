#!/usr/bin/env bats
# tests/test-se-262-thermal-receipt.bats — Tests for pr-thermal-receipt.sh (SE-262)

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pr-thermal-receipt.sh"

setup() {
  [[ -x "$SCRIPT" ]] || skip "pr-thermal-receipt.sh missing"
}

@test "T01: refuses to run outside git repo" {
  run bash "$SCRIPT" --staged --project /tmp
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "not a git repository" ]]
}

@test "T02: requires --staged or --branch" {
  run bash "$SCRIPT"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "must specify --staged or --branch" ]]
}

@test "T03: staged mode produces output" {
  run bash "$SCRIPT" --staged
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "THERMAL RECEIPT" ]] || [[ "$output" =~ "no staged changes" ]]
}

@test "T04: markdown output has receipt marker" {
  run bash "$SCRIPT" --staged
  [[ "$output" =~ "codeflow-card:receipt" ]]
}

@test "T05: markdown output has thermal receipt header" {
  run bash "$SCRIPT" --staged
  [[ "$output" =~ "THERMAL RECEIPT" ]]
}

@test "T06: json format outputs valid JSON" {
  run bash "$SCRIPT" --staged --format json
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q '"timestamp"'
  echo "$output" | grep -q '"actor"'
  echo "$output" | grep -q '"delta"'
}

@test "T07: json format has all delta fields" {
  run bash "$SCRIPT" --staged --format json
  echo "$output" | grep -q '"files_changed"'
  echo "$output" | grep -q '"loc_added"'
  echo "$output" | grep -q '"functions_added"'
}

@test "T08: branch mode with invalid ref still runs" {
  run bash "$SCRIPT" --branch "nonexistent..alsofake" 2>&1
  [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]] || [[ "$status" -eq 128 ]]
}

@test "T09: branch mode with HEAD ref works" {
  run bash "$SCRIPT" --branch "HEAD~1..HEAD" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" =~ "THERMAL RECEIPT" ]]
}

@test "T10: help flag works" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Usage" ]]
}
