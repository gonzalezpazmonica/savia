#!/usr/bin/env bats
# Latency ratchet (scripts/ci-extended-checks.sh check 9, SLA 20 ms): the
# common path of these hooks must not fork external processes. Running with an
# empty PATH makes any fork (cat, dirname, git...) surface as a failure or as
# "command not found" on stderr.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export EMPTY_BIN="$BATS_TEST_TMPDIR/empty-bin"
  mkdir -p "$EMPTY_BIN"
  export BASH_BIN="$(command -v bash)"
}

@test "memory-auto-capture: non Edit/Write tool exits without forking" {
  run env -i PATH="$EMPTY_BIN" HOME="$BATS_TEST_TMPDIR" TOOL_NAME=Read \
    "$BASH_BIN" .claude/hooks/memory-auto-capture.sh </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "memory-auto-capture: no TOOL_NAME exits without forking (bench input)" {
  run env -i PATH="$EMPTY_BIN" HOME="$BATS_TEST_TMPDIR" \
    "$BASH_BIN" .claude/hooks/memory-auto-capture.sh </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "memory-auto-capture: negative - Edit still proceeds past the early exit" {
  run env -i PATH="$EMPTY_BIN" HOME="$BATS_TEST_TMPDIR" TOOL_NAME=Edit \
    CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/nows" \
    "$BASH_BIN" .claude/hooks/memory-auto-capture.sh </dev/null
  # Reaches savia-env.sh (forks git/dirname): with an empty PATH it must
  # not take the silent early-exit path.
  [ -n "$output" ] || [ "$status" -ne 0 ]
}

@test "session-end-snapshot: drain and root resolution without forking" {
  run env -i PATH="$EMPTY_BIN" HOME="$BATS_TEST_TMPDIR" \
    "$BASH_BIN" .claude/hooks/session-end-snapshot.sh <<<'{"hook_event_name":"Stop"}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"command not found"* ]]
}

@test "session-end-snapshot: focal save runs once per session end" {
  run grep -c 'focal-switch.sh' .claude/hooks/session-end-snapshot.sh
  [ "$output" -eq 1 ]
}
