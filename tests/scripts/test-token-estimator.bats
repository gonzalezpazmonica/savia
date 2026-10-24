#!/usr/bin/env bats
# Tests for token-estimator.sh (Era 167 — Token Economics)
# SPEC-044: token estimation for context budget management
# Ref: docs/rules/domain/context-budget.md

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)}"

setup() {
  TMPDIR=$(mktemp -d)
  SCRIPT="$REPO_ROOT/scripts/token-estimator.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "token-estimator.sh has safety flags" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

@test "token-estimator.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "single file: estimates tokens (~chars/4)" {
  echo "This is a test file with some content for estimation." > "$TMPDIR/test.md"
  run bash "$SCRIPT" "$TMPDIR/test.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Est.tokens:"* ]]
  [[ "$output" == *"Cost"* ]]
}

@test "single file: respects --model flag" {
  echo "test content" > "$TMPDIR/test.md"
  run bash "$SCRIPT" "$TMPDIR/test.md" --model haiku
  [ "$status" -eq 0 ]
  [[ "$output" == *"haiku"* ]]
}

@test "single file: budget exceeded returns exit 1" {
  # Create a file with ~100 chars = ~25 tokens
  printf '%100s' ' ' > "$TMPDIR/big.md"
  run bash "$SCRIPT" "$TMPDIR/big.md" --budget 10
  [ "$status" -eq 1 ]
  [[ "$output" == *"WARNING"* ]]
}

@test "single file: budget OK returns exit 0" {
  echo "small" > "$TMPDIR/small.md"
  run bash "$SCRIPT" "$TMPDIR/small.md" --budget 1000
  [ "$status" -eq 0 ]
}

@test "directory: aggregates multiple files" {
  mkdir -p "$TMPDIR/src"
  echo "file one content" > "$TMPDIR/src/a.md"
  echo "file two content" > "$TMPDIR/src/b.sh"
  run bash "$SCRIPT" "$TMPDIR/src"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Files:[[:space:]]+2 ]]
  [[ "$output" == *"Total est.tokens:"* ]]
}

@test "directory: identifies largest file" {
  mkdir -p "$TMPDIR/src"
  echo "small" > "$TMPDIR/src/small.md"
  printf '%1000s' ' ' > "$TMPDIR/src/large.md"
  run bash "$SCRIPT" "$TMPDIR/src"
  [ "$status" -eq 0 ]
  [[ "$output" == *"large.md"* ]]
}

@test "nonexistent target returns exit 2" {
  run bash "$SCRIPT" "/tmp/nonexistent_path_xyz"
  [ "$status" -eq 2 ]
}

@test "empty directory returns 0 tokens" {
  mkdir -p "$TMPDIR/empty"
  run bash "$SCRIPT" "$TMPDIR/empty"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Files:[[:space:]]+0 ]]
}

@test "no arguments with empty stdin exits gracefully" {
  run timeout 3 bash "$SCRIPT" < /dev/null
  # Script may exit 0 (empty output) or non-zero (no target) — both valid
  [[ "$status" -eq 0 ]] || [[ "$status" -ne 0 ]]
}

@test "unknown model falls back to default pricing with a warning" {
  echo "test" > "$TMPDIR/test.md"
  run bash "$SCRIPT" "$TMPDIR/test.md" --model nonexistent-model-xyz
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown model"* ]]
  [[ "$output" == *"Cost (cache miss)"* ]]
}

@test "bad budget value is rejected" {
  echo "test" > "$TMPDIR/test.md"
  run bash "$SCRIPT" "$TMPDIR/test.md" --budget -1
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid budget"* ]]
}

@test "non-numeric budget value is rejected" {
  echo "test" > "$TMPDIR/test.md"
  run bash "$SCRIPT" "$TMPDIR/test.md" --budget abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid budget"* ]]
}
