#!/usr/bin/env bats
# rule-usage-analyzer.sh: validación de --root / --output (revisión PR #1353)

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rule-usage-analyzer.sh"

@test "--root without value fails with a clear error, not unbound variable" {
  run bash "$SCRIPT" --root
  [ "$status" -eq 2 ]
  [[ "$output" == *"--root requiere"* ]]
  [[ "$output" != *"unbound"* ]]
}

@test "--root pointing to a nonexistent directory fails" {
  run bash "$SCRIPT" --root /nonexistent-dir-xyz
  [ "$status" -eq 2 ]
  [[ "$output" == *"--root requiere"* ]]
}

@test "--output without value fails" {
  run bash "$SCRIPT" --output
  [ "$status" -eq 2 ]
  [[ "$output" == *"--output requiere"* ]]
}

@test "--root with an existing empty directory still succeeds" {
  local d
  d=$(mktemp -d)
  run bash "$SCRIPT" --root "$d" --summary
  rmdir "$d"
  [ "$status" -eq 0 ]
}
