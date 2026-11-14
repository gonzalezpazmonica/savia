#!/usr/bin/env bats
# Tests for SPEC-068 Hook Enhancements (Era 165)
# Ref: docs/rules/domain/critical-rules-extended.md
# Covers: pre-compact tier classification, post-compact session-hot, failure categorization

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)}"

setup() {
    TMPDIR=$(mktemp -d)
    export PROJECT_ROOT="$TMPDIR"
    export HOME="$TMPDIR/home"
    export CLAUDE_PROJECT_DIR="$TMPDIR/workspace"
    mkdir -p "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
    # Derive PROJ_SLUG the same way hooks do (matching sed pattern)
    PROJ_SLUG=$(echo "$CLAUDE_PROJECT_DIR" | sed 's|[/:\\]|-|g; s|^-||')
    mkdir -p "$HOME/.claude/projects/$PROJ_SLUG/memory"
    mkdir -p "$HOME/.pm-workspace/tool-failures"
    mkdir -p "$TMPDIR/output"
    mkdir -p "$TMPDIR/scripts"

    HOOKS_DIR="$REPO_ROOT/.claude/hooks"
    SCRIPTS_DIR="$REPO_ROOT/scripts"
    SESSION_HOT="$HOME/.claude/projects/$PROJ_SLUG/memory/session-hot.md"

    # Stub memory-store.sh to avoid side effects
    cat > "$TMPDIR/scripts/memory-store.sh" << 'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$TMPDIR/scripts/memory-store.sh"
}

teardown() {
    rm -rf "$TMPDIR"
}

# ── PRE-COMPACT: TIER CLASSIFICATION ──

@test "pre-compact: safety flags present" {
    grep -q "set -uo pipefail" "$HOOKS_DIR/pre-compact-backup.sh"
}

@test "pre-compact: exit 0 on empty input" {
    run bash "$HOOKS_DIR/pre-compact-backup.sh" < /dev/null
    [ "$status" -eq 0 ]
}

# SE-529 S1: la carga de PreCompact son metadatos; la conversación se lee de transcript_path.
_pc_transcript() { # _pc_transcript <texto de la persona> → imprime la carga del hook
    mkdir -p "$HOME/.claude/projects/p"
    python3 -I -c 'import json,sys; print(json.dumps({"type":"user","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1" > "$HOME/.claude/projects/p/s.jsonl"
    printf '{"transcript_path":"%s","hook_event_name":"PreCompact"}' "$HOME/.claude/projects/p/s.jsonl"
}

@test "pre-compact: Tier B decisions written to session-hot.md" {
    _pc_transcript "We decided to use Redis for caching" | bash "$HOOKS_DIR/pre-compact-backup.sh"
    [ -f "$SESSION_HOT" ]
    grep -qi "decid" "$SESSION_HOT"
}

@test "pre-compact: Tier B corrections written to session-hot.md" {
    _pc_transcript "no not that, change to PostgreSQL instead" | bash "$HOOKS_DIR/pre-compact-backup.sh"
    [ -f "$SESSION_HOT" ]
    grep -qi "change to" "$SESSION_HOT" || grep -qi "not that" "$SESSION_HOT"
}

@test "pre-compact: text inside hook metadata is not treated as conversation (SE-529 S1)" {
    run bash "$HOOKS_DIR/pre-compact-backup.sh" <<< '{"text":"We decided to use Redis for caching"}'
    [ "$status" -eq 0 ]
    [ ! -f "$SESSION_HOT" ] || ! grep -qi "redis" "$SESSION_HOT"
}

# ── POST-COMPACT: SESSION-HOT REINJECTION ──

@test "post-compact: reinjects session-hot.md when present" {
    export PROJECT_ROOT="$TMPDIR"
    echo "## Session Context" > "$SESSION_HOT"
    echo "Decisions: chose Redis for caching" >> "$SESSION_HOT"
    # Create empty memory store so script runs
    touch "$TMPDIR/output/.memory-store.jsonl"
    run bash "$SCRIPTS_DIR/post-compaction.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Session Continuity"* ]]
}

@test "post-compact: truncates session-hot.md after consumption" {
    export PROJECT_ROOT="$TMPDIR"
    echo "Decisions: chose Redis" > "$SESSION_HOT"
    touch "$TMPDIR/output/.memory-store.jsonl"
    bash "$SCRIPTS_DIR/post-compaction.sh" > /dev/null 2>&1 || true
    # File should be empty after consumption
    [ ! -s "$SESSION_HOT" ]
}

@test "post-compact: handles missing session-hot.md gracefully" {
    export PROJECT_ROOT="$TMPDIR"
    rm -f "$SESSION_HOT"
    touch "$TMPDIR/output/.memory-store.jsonl"
    run bash "$SCRIPTS_DIR/post-compaction.sh"
    [ "$status" -eq 0 ]
}

# ── POST-TOOL-FAILURE: STRUCTURED CATEGORIZATION ──

@test "failure-log: categorizes permission errors" {
    echo '{"tool_name":"Bash","error":"permission denied: /etc/hosts"}' \
        | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    LOG_FILE="$HOME/.pm-workspace/tool-failures/$(date +%Y-%m-%d).jsonl"
    [ -f "$LOG_FILE" ]
    grep -q '"category":"permission"' "$LOG_FILE"
    grep -q '"retry_hint"' "$LOG_FILE"
}

@test "failure-log: categorizes not-found errors" {
    echo '{"tool_name":"Read","error":"no such file or directory: /tmp/nope.md"}' \
        | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    LOG_FILE="$HOME/.pm-workspace/tool-failures/$(date +%Y-%m-%d).jsonl"
    grep -q '"category":"not_found"' "$LOG_FILE"
}

@test "failure-log: categorizes timeout errors" {
    echo '{"tool_name":"Bash","error":"command timed out after 120s"}' \
        | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    LOG_FILE="$HOME/.pm-workspace/tool-failures/$(date +%Y-%m-%d).jsonl"
    grep -q '"category":"timeout"' "$LOG_FILE"
}

@test "failure-log: exit 0 on empty input" {
    run bash "$HOOKS_DIR/post-tool-failure-log.sh" < /dev/null
    [ "$status" -eq 0 ]
}

@test "failure-log: detects repeated failure pattern" {
    LOG_FILE="$HOME/.pm-workspace/tool-failures/$(date +%Y-%m-%d).jsonl"
    # Pre-populate with 2 failures for same tool
    echo '{"ts":"t1","tool":"Bash","category":"syntax"}' >> "$LOG_FILE"
    echo '{"ts":"t2","tool":"Bash","category":"syntax"}' >> "$LOG_FILE"
    # Third failure should trigger pattern detection
    echo '{"tool_name":"Bash","error":"syntax error near unexpected token"}' \
        | bash "$HOOKS_DIR/post-tool-failure-log.sh"
    grep -q '"pattern":"repeated"' "$LOG_FILE"
}
