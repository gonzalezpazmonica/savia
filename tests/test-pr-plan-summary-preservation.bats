#!/usr/bin/env bats
# SPEC-396 operational-integrity regression tests for pr-plan G6.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_ROOT="$(mktemp -d)"
  TEST_BIN="$TEST_ROOT/bin"
  mkdir -p "$TEST_BIN/tests"
  cat > "$TEST_BIN/timeout" <<'SH'
#!/usr/bin/env bash
rm -f "$ROOT/.pr-summary.md"
printf '%s\n' "$*" > "$ROOT/timeout-args"
case "${FAKE_TIMEOUT_MODE:-pass}" in
  pass) printf '1..1\nok 1 fake\n'; exit 0 ;;
  timeout) exit 124 ;;
  crash) echo "runner crashed"; exit 2 ;;
  incomplete) echo "runner ended without summary"; exit 0 ;;
esac
SH
  chmod +x "$TEST_BIN/timeout"
  touch "$TEST_BIN/tests/run-all.sh"
  export PR_PLAN_BATS_FILES="tests/fake.bats"
}

@test "G6 source gate uses strict pipefail safety" {
  grep -q 'set -uo pipefail' "$REPO_ROOT/scripts/pr-plan-gates.sh"
}

@test "G6 accepts one selected suite boundary and reports it" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [ "$status" -eq 0 ]
  [[ "$output" == *"1/1 changed suites"* ]]
}

@test "G6 passes the selected file list to bats" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [ "$status" -eq 0 ]
  grep -q 'bats tests/fake.bats' "$TEST_ROOT/timeout-args"
}

@test "G6 fails explicitly when the suite times out" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  export FAKE_TIMEOUT_MODE=timeout
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [[ "$output" == *"FAIL:"*"timed out"* ]]
}

@test "G6 fails explicitly when the suite runner crashes" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  export FAKE_TIMEOUT_MODE=crash
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [[ "$output" == *"FAIL:"*"exit 2"* ]]
}

@test "G6 rejects a successful runner without a suite summary" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  export FAKE_TIMEOUT_MODE=incomplete
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [[ "$output" == *"FAIL:"*"TAP completion plan"* ]]
}

@test "G6 reports an empty local suite selection" {
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  unset PR_PLAN_BATS_FILES
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [[ "$output" == *"WARN: no changed BATS suites"* ]]
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "G6 preserves the PR summary across test side effects" {
  printf 'summary that must survive\n' > "$TEST_ROOT/.pr-summary.md"
  export ROOT="$TEST_ROOT"
  export PATH="$TEST_BIN:$PATH"
  cd "$TEST_BIN"
  source "$REPO_ROOT/scripts/pr-plan-gates.sh"

  run g6

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/.pr-summary.md")" = "summary that must survive" ]
}
