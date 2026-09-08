#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_ROOT="$(mktemp -d)"
  TEST_BIN="$TEST_ROOT/bin"
  mkdir -p "$TEST_BIN/tests"
  printf '#!/usr/bin/env bash\nrm -f "$ROOT/.pr-summary.md"\necho "1/1 suites"\n' > "$TEST_BIN/timeout"
  chmod +x "$TEST_BIN/timeout"
  touch "$TEST_BIN/tests/run-all.sh"
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
