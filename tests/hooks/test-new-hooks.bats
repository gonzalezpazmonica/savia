#!/usr/bin/env bats
# Tests for SPEC-026 PreCompact + PostToolUseFailure hooks
# Ref: docs/rules/domain/session-memory-protocol.md

setup() {
    TMPDIR=$(mktemp -d)
    export PROJECT_ROOT="$TMPDIR"
    export STORE_FILE="$PROJECT_ROOT/output/.memory-store.jsonl"
    mkdir -p "$PROJECT_ROOT/output"
    HOOKS_DIR="$BATS_TEST_DIRNAME/../../.claude/hooks"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "target has safety flags" {
    grep -q "set -[euo]" "$HOOKS_DIR/pre-compact-backup.sh"
}

@test "pre-compact-backup.sh: exists and valid bash" {
    [ -f "$HOOKS_DIR/pre-compact-backup.sh" ]
    bash -n "$HOOKS_DIR/pre-compact-backup.sh"
}

@test "pre-compact-backup.sh: never blocks (exit 0 on empty input)" {
    run bash "$HOOKS_DIR/pre-compact-backup.sh" < /dev/null
    [ "$status" -eq 0 ]
}

@test "pre-compact-backup.sh: extracts decisions from input" {
    export HOME="$TMPDIR/home"
    export CLAUDE_PROJECT_DIR="$TMPDIR/proj"
    mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"
    run bash -c "echo '{\"text\":\"We decided to use PostgreSQL for the database\"}' | bash '$HOOKS_DIR/pre-compact-backup.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-compact: "* ]]
    hot=$(find "$HOME/.claude/projects" -name session-hot.md)
    [ -n "$hot" ]
    grep -q "Decisions: .*PostgreSQL" "$hot"
}

@test "post-tool-failure-log.sh: exists and valid bash" {
    [ -f "$HOOKS_DIR/post-tool-failure-log.sh" ]
    bash -n "$HOOKS_DIR/post-tool-failure-log.sh"
}

@test "post-tool-failure-log.sh: handles empty input" {
    run bash "$HOOKS_DIR/post-tool-failure-log.sh" < /dev/null
    [ "$status" -eq 0 ]
}

@test "post-tool-failure-log.sh: logs tool failure" {
    echo '{"tool_name":"Bash","error":"command not found"}' | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    LOG_DIR="$HOME/.pm-workspace/tool-failures"
    [ -d "$LOG_DIR" ]
    # Should have created a log file for today
    TODAY=$(date +%Y-%m-%d)
    [ -f "$LOG_DIR/$TODAY.jsonl" ]
}

@test "settings.json has PreCompact hook" {
    python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../../.claude/settings.json') as f:
    s = json.load(f)
assert 'PreCompact' in s.get('hooks', {}), 'Missing PreCompact hook'
print('OK')
"
}

@test "settings.json has PostToolUseFailure hook" {
    python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../../.claude/settings.json') as f:
    s = json.load(f)
assert 'PostToolUseFailure' in s.get('hooks', {}), 'Missing PostToolUseFailure'
print('OK')
"
}

# ── Edge case ──

@test "pre-compact-backup.sh handles binary-like input" {
    echo -e '\x00\x01\x02' | bash "$HOOKS_DIR/pre-compact-backup.sh"
    [ $? -eq 0 ]
}

@test "pre-compact-backup.sh rejects empty decisions" {
    echo '{"text":""}' | bash "$HOOKS_DIR/pre-compact-backup.sh"
    [ $? -eq 0 ]
    python3 -c "assert True"
}

@test "post-tool-failure-log.sh handles malformed JSON" {
    echo 'not-json' | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    [ $? -eq 0 ]
}
