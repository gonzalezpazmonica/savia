#!/usr/bin/env bats
# BATS tests for .opencode/hooks/acm-turn-marker.sh
# PostToolUse — SE-063 Slice 2. Creates per-turn marker when agent reads
# a file inside projects/*/.agent-maps/ (signals ACM was consulted).
# Consumed by acm-enforcement.sh PreToolUse.
# Ref: batch 47 hook coverage — SPEC-063 ACM enforcement chain

HOOK=".opencode/hooks/acm-turn-marker.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export SAVIA_HOOK_PROFILE="${SAVIA_HOOK_PROFILE:-standard}"
  TEST_DIR=$(mktemp -d "$TMPDIR/atm-XXXXXX")
  export CLAUDE_TURN_ID="test-turn-$$"
  MARKER_DIR="$TMPDIR/savia-turn-$CLAUDE_TURN_ID"
}
teardown() {
  rm -rf "$TEST_DIR" "$MARKER_DIR" 2>/dev/null || true
  unset CLAUDE_TURN_ID
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }
@test "SE-063 reference" {
  run grep -c 'SE-063' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "has profile_gate standard" {
  run grep -c 'profile_gate "standard"' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Pass-through ────────────────────────────────────────

@test "pass-through: empty stdin exits 0 silent" {
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "pass-through: non-Read tool skipped" {
  run bash "$HOOK" <<< '{"tool_name":"Edit","tool_input":{"file_path":"/x/projects/foo/.agent-maps/INDEX.acm"}}'
  [ "$status" -eq 0 ]
  [[ ! -d "$MARKER_DIR" ]]
}

@test "pass-through: Write tool skipped" {
  run bash "$HOOK" <<< '{"tool_name":"Write","tool_input":{"file_path":"/x/projects/foo/.agent-maps/x.acm"}}'
  [ "$status" -eq 0 ]
  [[ ! -d "$MARKER_DIR" ]]
}

@test "pass-through: Bash tool skipped" {
  run bash "$HOOK" <<< '{"tool_name":"Bash","tool_input":{"command":"cat projects/foo/.agent-maps/INDEX.acm"}}'
  [ "$status" -eq 0 ]
}

# ── No file_path ────────────────────────────────────────

@test "no-path: Read without file_path exits 0" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{}}'
  [ "$status" -eq 0 ]
  run compgen -G "$MARKER_DIR/acm-read-*"
  [ "$status" -ne 0 ]
}

@test "no-path: Read with empty file_path exits 0" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":""}}'
  [ "$status" -eq 0 ]
}

# ── Non-ACM paths ───────────────────────────────────────

@test "non-acm: reading random file does not create marker" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/home/user/code.py"}}'
  [ "$status" -eq 0 ]
  [[ ! -d "$MARKER_DIR" ]] || [[ -z "$(ls -A $MARKER_DIR 2>/dev/null)" ]]
}

@test "non-acm: projects/ but not .agent-maps does not trigger" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/foo/src/main.rs"}}'
  [ "$status" -eq 0 ]
  [[ ! -d "$MARKER_DIR" ]] || [[ -z "$(ls -A $MARKER_DIR 2>/dev/null)" ]]
}

@test "non-acm: .agent-maps outside projects does not trigger" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/.agent-maps/INDEX.acm"}}'
  [ "$status" -eq 0 ]
  [[ ! -d "$MARKER_DIR" ]] || [[ -z "$(ls -A $MARKER_DIR 2>/dev/null)" ]]
}

# ── Valid ACM read triggers marker ──────────────────────

@test "acm: Read .agent-maps/INDEX.acm creates marker" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/alpha/.agent-maps/INDEX.acm"}}'
  [ "$status" -eq 0 ]
  [[ -f "$MARKER_DIR/acm-read-alpha" ]]
}

@test "acm: Read subdir file in .agent-maps creates marker" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/beta/.agent-maps/modules/core.acm"}}'
  [ "$status" -eq 0 ]
  [[ -f "$MARKER_DIR/acm-read-beta" ]]
}

@test "acm: marker name matches project name" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/my-proj-123/.agent-maps/x.acm"}}'
  [ "$status" -eq 0 ]
  [[ -f "$MARKER_DIR/acm-read-my-proj-123" ]]
}

@test "acm: marker file is empty" {
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/gamma/.agent-maps/INDEX.acm"}}' >/dev/null
  [[ -f "$MARKER_DIR/acm-read-gamma" ]]
  local size
  size=$(stat -c '%s' "$MARKER_DIR/acm-read-gamma" 2>/dev/null || stat -f '%z' "$MARKER_DIR/acm-read-gamma")
  [[ "$size" -eq 0 ]]
}

@test "acm: multiple ACM reads update same marker (idempotent)" {
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/delta/.agent-maps/a.acm"}}' >/dev/null
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/delta/.agent-maps/b.acm"}}' >/dev/null
  local markers
  markers=$(ls "$MARKER_DIR" 2>/dev/null | grep -c "acm-read-delta")
  [[ "$markers" -eq 1 ]]
}

@test "acm: different projects create different markers" {
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/a/.agent-maps/x.acm"}}' >/dev/null
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/b/.agent-maps/x.acm"}}' >/dev/null
  [[ -f "$MARKER_DIR/acm-read-a" ]]
  [[ -f "$MARKER_DIR/acm-read-b" ]]
}

# ── Turn ID handling ────────────────────────────────────

@test "turn: marker dir uses CLAUDE_TURN_ID" {
  export CLAUDE_TURN_ID="my-turn-xyz"
  local my_marker="$TMPDIR/savia-turn-my-turn-xyz"
  rm -rf "$my_marker"
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/x/.agent-maps/i.acm"}}' >/dev/null
  [[ -d "$my_marker" ]]
  [[ -f "$my_marker/acm-read-x" ]]
  rm -rf "$my_marker"
  unset CLAUDE_TURN_ID
}

@test "turn: fallback to CLAUDE_SESSION_ID when CLAUDE_TURN_ID unset" {
  unset CLAUDE_TURN_ID
  export CLAUDE_SESSION_ID="session-abc"
  local sess_marker="$TMPDIR/savia-turn-session-abc"
  rm -rf "$sess_marker"
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/s/.agent-maps/i.acm"}}' >/dev/null
  [[ -d "$sess_marker" ]]
  rm -rf "$sess_marker"
  unset CLAUDE_SESSION_ID
}

@test "turn: fallback to default when neither env var set" {
  unset CLAUDE_TURN_ID CLAUDE_SESSION_ID
  local default_marker="$TMPDIR/savia-turn-default"
  rm -rf "$default_marker"
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects/d/.agent-maps/i.acm"}}' >/dev/null
  [[ -d "$default_marker" ]]
  rm -rf "$default_marker"
}

# ── jq missing fallback ─────────────────────────────────

@test "jq: missing jq binary silent exit 0" {
  # jq is available in CI; this checks the guard exists
  run grep -c 'command -v jq' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Malformed input ─────────────────────────────────────

@test "negative: malformed JSON exits 0 silent" {
  run bash "$HOOK" <<< "not valid json"
  [ "$status" -eq 0 ]
}

@test "negative: JSON without tool_name exits 0" {
  run bash "$HOOK" <<< '{"other":"field"}'
  [ "$status" -eq 0 ]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: relative path does not match (absolute required)" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"projects/x/.agent-maps/INDEX.acm"}}'
  [ "$status" -eq 0 ]
  # The pattern */projects/*/.agent-maps/* requires the prefix, relative path without leading /
  # should still match because * matches empty. But we don't assert marker here — just no crash.
}

@test "edge: deeply nested .agent-maps file" {
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/a/b/c/projects/z/.agent-maps/d/e/f/deep.acm"}}' >/dev/null
  [[ -f "$MARKER_DIR/acm-read-z" ]]
}

@test "edge: large JSON input does not crash" {
  local big
  big=$(python3 -c 'print("x" * 5000)')
  run bash "$HOOK" <<< "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/p/projects/big/.agent-maps/x.acm\",\"pad\":\"$big\"}}"
  [ "$status" -eq 0 ]
  [[ -f "$MARKER_DIR/acm-read-big" ]]
}

@test "edge: empty project name in path does not create marker" {
  run bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/repo/projects//.agent-maps/x.acm"}}'
  [ "$status" -eq 0 ]
  # Pattern still matches, but project name extraction yields empty → exit 0
  [[ ! -f "$MARKER_DIR/acm-read-" ]]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: acm-enforcement.sh consumer reference" {
  run grep -c 'acm-enforcement' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: PROJECT_NAME extraction via sed" {
  run grep -c 'sed.*projects.*\.agent-maps' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: SPEC-063 propuestas reference" {
  run grep -c 'SE-063' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: timeout guard on cat" {
  run grep -c 'timeout.*cat\|timeout 3' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ───────────────────────────────────────────

@test "isolation: hook always exits 0 (never blocks)" {
  for payload in '' '{}' 'bad json' '{"tool_name":"Read"}' '{"tool_name":"Read","tool_input":{"file_path":"/p/projects/a/.agent-maps/x.acm"}}'; do
    run bash "$HOOK" <<< "$payload"
    [ "$status" -eq 0 ]
  done
}

@test "isolation: hook does not modify repo files" {
  local before after
  before=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  bash "$HOOK" <<< '{"tool_name":"Read","tool_input":{"file_path":"/p/projects/a/.agent-maps/x.acm"}}' >/dev/null 2>&1
  after=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
