#!/usr/bin/env bats
# Test strategy: validation of scripts/labs-preregister.sh against a simulated
# Labs repo in $BATS_TEST_TMPDIR (the script is copied so ROOT = the sandbox).
# Covers: any positive L<n> line that exists in labs/ROADMAP.md, rejection of
# malformed or unknown lines, fail-closed without Labs, and a failing commit
# (pre-commit hook exit 1) must give rc != 0.
# Ref: docs/rules/domain/radical-honesty.md (fail-closed, no silent success)
# Ref: scripts/labs-preregister.sh

setup() {
  TMPDIR=$(mktemp -d)
  SANDBOX="$BATS_TEST_TMPDIR/sandbox"
  mkdir -p "$SANDBOX/scripts" "$SANDBOX/labs/notebook"
  cp "$BATS_TEST_DIRNAME/../../scripts/labs-preregister.sh" "$SANDBOX/scripts/"
  SCRIPT="$SANDBOX/scripts/labs-preregister.sh"
  printf '# Labs roadmap\n\n| L1 | base |\n| L13 | metacognicion |\n| L42 | linea nueva |\n' > "$SANDBOX/labs/ROADMAP.md"
  git -C "$SANDBOX/labs" init -q
  git -C "$SANDBOX/labs" config user.email t@example.com
  git -C "$SANDBOX/labs" config user.name tester
  git -C "$SANDBOX/labs" config commit.gpgsign false
  git -C "$SANDBOX/labs" add -A
  git -C "$SANDBOX/labs" commit -q -m init
}

teardown() {
  rm -rf "$TMPDIR" "$SANDBOX"
}

run_pre() {
  local line="$1"
  run bash "$SCRIPT" --title "Hipotesis $line" --line "$line" --method m \
    --metric x --success s --failure f --sample 10
}

@test "target uses set -euo pipefail safety flags" {
  grep -q 'set -euo pipefail' "$BATS_TEST_DIRNAME/../../scripts/labs-preregister.sh"
}

@test "positive: line L42 is accepted when present in ROADMAP" {
  run_pre L42
  [ "$status" -eq 0 ]
  [[ "$output" == *"Preregistered:"* ]]
}

@test "positive: line L1 is accepted" {
  run_pre L1
  [ "$status" -eq 0 ]
}

@test "positive: line L13 is accepted" {
  run_pre L13
  [ "$status" -eq 0 ]
}

@test "positive: happy path writes hypothesis file and commits it" {
  run_pre L42
  [ "$status" -eq 0 ]
  [ -f "$SANDBOX/labs/hypotheses/hipotesis-l42.md" ]
  grep -q 'line: L42' "$SANDBOX/labs/hypotheses/hipotesis-l42.md"
  run git -C "$SANDBOX/labs" log --format=%s -1
  [[ "$output" == *"preregister: L42"* ]]
  run git -C "$SANDBOX/labs" status --porcelain
  [ -z "$output" ]
}

@test "positive: optional budgets are recorded" {
  run bash "$SCRIPT" --title T --line L42 --method m --metric x --success s \
    --failure f --sample 3 --budget-tokens 500 --budget-hours 2
  [ "$status" -eq 0 ]
  grep -q 'budget_tokens: 500' "$SANDBOX/labs/hypotheses/t.md"
}

@test "negative: line L0 is rejected as invalid" {
  run_pre L0
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "negative: line L-1 is rejected as invalid" {
  run_pre L-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "negative: line Lx is rejected as invalid" {
  run_pre Lx
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "negative: bare number 42 without L is rejected as invalid" {
  run_pre 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "negative: nonexistent line L99 is rejected with a clear message" {
  run_pre L99
  [ "$status" -ne 0 ]
  [[ "$output" == *"L99"* ]]
  [[ "$output" == *"ROADMAP"* ]]
  [ ! -e "$SANDBOX/labs/hypotheses" ]
}

@test "negative: L4 is not accepted just because L42 exists (no prefix match)" {
  run_pre L4
  [ "$status" -ne 0 ]
}

@test "negative: missing required fields fails" {
  run bash "$SCRIPT" --title T
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required fields"* ]]
}

@test "negative: failing commit (pre-commit hook exit 1) gives rc != 0" {
  mkdir -p "$SANDBOX/labs/.git/hooks"
  printf '#!/bin/sh\necho hook-says-no >&2\nexit 1\n' > "$SANDBOX/labs/.git/hooks/pre-commit"
  chmod +x "$SANDBOX/labs/.git/hooks/pre-commit"
  run_pre L42
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit"* ]]
  [[ "$output" != *"Preregistered:"* ]]
}

@test "edge: Labs unavailable (no labs dir) fails closed" {
  rm -rf "$SANDBOX/labs"
  run_pre L1
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "edge: ROADMAP.md missing fails closed" {
  rm -f "$SANDBOX/labs/ROADMAP.md"
  run_pre L1
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROADMAP"* ]]
}

@test "edge: empty line value is rejected as missing" {
  run_pre ""
  [ "$status" -eq 1 ]
}

@test "edge: leading-zero line L042 is rejected" {
  run_pre L042
  [ "$status" -ne 0 ]
}
