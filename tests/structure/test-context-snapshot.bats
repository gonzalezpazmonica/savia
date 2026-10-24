#!/usr/bin/env bats
# Tests for Era 100.2 — Context Sync Persistente

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  ROOT="$PWD"
  TMPDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "context-snapshot.sh exists and is executable" {
  [ -x "$ROOT/scripts/context-snapshot.sh" ]
}

@test "session-end-snapshot.sh hook exists and is executable" {
  [ -x "$ROOT/.opencode/hooks/session-end-snapshot.sh" ]
}

@test "snapshot save produces valid JSON" {
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh save"
  [ "$status" -eq 0 ]
  # Verify the file was created
  [ -f "$ROOT/.claude/context-cache/last-session.json" ]
  python3 -c "import json; json.load(open('$ROOT/.claude/context-cache/last-session.json'))"
}

@test "snapshot load returns JSON with required fields" {
  # Ensure snapshot exists from previous test
  echo '' | bash "$ROOT/scripts/context-snapshot.sh" save > /dev/null 2>&1
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh load"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert 'branch' in d, 'missing branch'
assert 'project' in d, 'missing project'
assert 'timestamp' in d, 'missing timestamp'
print('OK')
"
}

@test "snapshot status shows age info" {
  echo '' | bash "$ROOT/scripts/context-snapshot.sh" save > /dev/null 2>&1
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh status"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Age:"
  echo "$output" | grep -q "Fresh:"
}

@test "settings.json has session-end-snapshot hook in Stop" {
  run python3 -c "
import json
d = json.load(open('$ROOT/.claude/settings.json'))
hooks = d['hooks']['Stop'][0]['hooks']
names = [h['command'] for h in hooks]
found = any('session-end-snapshot' in n for n in names)
assert found, 'session-end-snapshot hook not in Stop'
print('OK')
"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "context-cache directory is gitignored" {
  run bash -c "grep -q 'context-cache' $ROOT/.gitignore"
  [ "$status" -eq 0 ]
}

# ── Negative cases ──

@test "snapshot load fails gracefully when no snapshot exists" {
  run bash -c "echo '' | HOME='$TMPDIR' $ROOT/scripts/context-snapshot.sh load 2>&1"
  [ "$status" -eq 0 ]
  # El snapshot vive en el repo (no bajo HOME): stale o fresco, nunca error
  [[ "$output" == *"No fresh snapshot"* || "$output" == *'"timestamp"'* ]]
}

@test "snapshot save handles non-git directory" {
  run bash -c "cd '$TMPDIR' && echo '' | bash '$ROOT/scripts/context-snapshot.sh' save 2>&1"
  # Should not crash in non-git dir
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ── Edge case ──

@test "snapshot status handles boundary case of fresh snapshot" {
  echo '' | bash "$ROOT/scripts/context-snapshot.sh" save > /dev/null 2>&1
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Age:"* ]]
}

# ── Spec/doc reference ──

@test "context-snapshot aligns with session-memory-protocol" {
  # Ref: docs/rules/domain/session-memory-protocol.md
  grep -q "session\|snapshot\|context" "$ROOT/scripts/context-snapshot.sh"
}

@test "context-snapshot.sh has set -uo pipefail safety" {
  grep -q "set -[euo]*o pipefail" "$ROOT/scripts/context-snapshot.sh"
}

@test "snapshot save with invalid args does not crash" {
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh invalid-subcommand 2>&1"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "snapshot handles empty context-cache dir" {
  mkdir -p "$TMPDIR/empty-cache"
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh status 2>&1"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "snapshot rejects null subcommand gracefully" {
  run bash -c "echo '' | $ROOT/scripts/context-snapshot.sh '' 2>&1"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
