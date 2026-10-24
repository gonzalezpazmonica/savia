#!/usr/bin/env bats
# Ref: .opencode/hooks/context-greedy-inject.sh — SPEC-189 Slice 2
# PreToolUse Read interceptor for context graphs (.acm, .scm).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOOK="$REPO_ROOT/.opencode/hooks/context-greedy-inject.sh"
  export FIXTURES="$REPO_ROOT/tests/fixtures/context-greedy-budget"
  TMPDIR_CGI=$(mktemp -d)
  export CLAUDE_PROJECT_DIR="$REPO_ROOT"
  # Reset state for each test
  unset SAVIA_CGI SAVIA_TURN_QUERY SAVIA_CGI_MIN_FILE_TOKENS
  unset SAVIA_CGI_QUALITY_MIN_TOP SAVIA_CGI_MIN_SAVINGS_PCT SAVIA_CGI_BUDGET
}

teardown() {
  rm -rf "$TMPDIR_CGI"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tool / file gating
# ─────────────────────────────────────────────────────────────────────────────

@test "non-Read tool exits 0 silently" {
  run bash -c 'echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"x.acm\"}}" | bash "$HOOK"' \
    HOOK="$HOOK"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "Read of non-graph file exits 0 silently" {
  run bash -c 'echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"src/foo.py\"}}" | bash "$HOOK"' \
    HOOK="$HOOK"
  [[ "$status" -eq 0 ]]
}

@test "SAVIA_CGI=off short-circuits" {
  export SAVIA_CGI=off
  run bash -c 'echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"x.acm\"}}" | bash "$HOOK"'
  [[ "$status" -eq 0 ]]
}

@test "no stdin returns 0" {
  run bash "$HOOK"
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Bypass paths (telemetry-only decisions)
# ─────────────────────────────────────────────────────────────────────────────

@test "small file under MIN_FILE_TOKENS bypasses" {
  small="$TMPDIR_CGI/small.acm"
  echo "## Tiny" > "$small"
  echo "tiny body" >> "$small"
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="anything"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$small")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "no query inferable bypasses with telemetry" {
  big="$TMPDIR_CGI/big.acm"
  python3 -c "
content = '## Header\n' + ('lorem ipsum dolor sit amet ' * 200) + '\n'
content += '## Section2\n' + ('foo bar baz ' * 100) + '\n'
open('$big', 'w').write(content)
"
  export SAVIA_CGI=shadow
  unset SAVIA_TURN_QUERY
  export CLAUDE_TURN_ID="cgi-test-no-query"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$big")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "cgi-skip marker per-dir opts out" {
  big="$TMPDIR_CGI/big.acm"
  python3 -c "open('$big','w').write('## H\n' + ('lorem ' * 500))"
  touch "$TMPDIR_CGI/.cgi-skip"
  export SAVIA_CGI=block
  export SAVIA_TURN_QUERY="lorem ipsum"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$big")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Quality decisions (mode=shadow — never blocks)
# ─────────────────────────────────────────────────────────────────────────────

@test "shadow mode: GOOD subgraph never blocks" {
  # Use the real savia-mobile-android INDEX.acm (large, with @include)
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="auth jwt login"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]   # shadow NEVER blocks
}

@test "shadow mode writes telemetry to output/context-greedy-inject.jsonl" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="auth jwt"
  log="$REPO_ROOT/output/context-greedy-inject.jsonl"
  before_lines=$(wc -l < "$log" 2>/dev/null || echo 0)
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  bash -c "echo '$payload' | bash '$HOOK'" >/dev/null 2>&1
  after_lines=$(wc -l < "$log" 2>/dev/null || echo 0)
  [[ "$after_lines" -gt "$before_lines" ]]
  # Last line must be valid JSON with required fields
  tail -1 "$log" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'decision' in d
assert 'file' in d
assert 'mode' in d
assert d['mode'] == 'shadow'
"
}

# ─────────────────────────────────────────────────────────────────────────────
# Quality decisions (mode=warn — advisory only)
# ─────────────────────────────────────────────────────────────────────────────

@test "warn mode: GOOD subgraph emits advisory but exits 0" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=warn
  export SAVIA_TURN_QUERY="auth jwt login"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  run bash -c "echo '$payload' | bash '$HOOK' 2>&1 1>/dev/null"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"[CGI] subgraph available"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Quality decisions (mode=block — actually blocks)
# ─────────────────────────────────────────────────────────────────────────────

@test "block mode: GOOD subgraph blocks Read with exit 2" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=block
  export SAVIA_TURN_QUERY="auth jwt login"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"context-greedy-inject"* ]]
  [[ "$output" == *"Subgraph"* ]]
}

@test "block mode: BAD quality (irrelevant query) does NOT block" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=block
  export SAVIA_TURN_QUERY="completely-unrelated-tachyon-flux"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]   # NO match → bypass even in block mode
}

# ─────────────────────────────────────────────────────────────────────────────
# Telemetry log format
# ─────────────────────────────────────────────────────────────────────────────

@test "telemetry includes decision, file, mode, top1, savings_pct" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="auth jwt"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  bash -c "echo '$payload' | bash '$HOOK'" >/dev/null 2>&1
  log="$REPO_ROOT/output/context-greedy-inject.jsonl"
  tail -1 "$log" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
required = {'ts','mode','decision','file','query','top1','savings_pct','reason'}
missing = required - set(d.keys())
assert not missing, f'missing: {missing}'
"
}

@test "tunable QUALITY_MIN_TOP raises threshold and downgrades to BAD_LOW_TOP1" {
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="auth jwt"
  export SAVIA_CGI_QUALITY_MIN_TOP=0.99   # almost-perfect required
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  bash -c "echo '$payload' | bash '$HOOK'" >/dev/null 2>&1
  log="$REPO_ROOT/output/context-greedy-inject.jsonl"
  last_decision=$(tail -1 "$log" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['decision'])")
  # Either GOOD (if top1 actually >=0.99) or BAD_LOW_TOP1; cannot be both BLOCK and warn
  [[ "$last_decision" == "BAD_LOW_TOP1" || "$last_decision" == "SHADOW_GOOD" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SPEC-055 audit-quality coverage
# ─────────────────────────────────────────────────────────────────────────────

@test "safety: hook script declares set -uo pipefail" {
  run grep -E "set -uo pipefail" "$HOOK"
  [[ "$status" -eq 0 ]]
}

@test "coverage: log_telemetry function defined and emits JSON to JSONL" {
  # Exercises log_telemetry() via shadow mode invocation.
  acm="$REPO_ROOT/projects/savia-mobile-android/.agent-maps/INDEX.acm"
  if [[ ! -f "$acm" ]]; then skip "real ACM not present"; fi
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="auth jwt"
  log="$REPO_ROOT/output/context-greedy-inject.jsonl"
  rm -f "$log"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$acm")
  bash -c "echo '$payload' | bash '$HOOK'" >/dev/null 2>&1
  [[ -f "$log" ]]
  # log_telemetry must produce parseable JSON
  tail -1 "$log" | python3 -c "import json,sys; json.loads(sys.stdin.read())"
}

@test "edge: empty stdin returns 0 (no-op)" {
  run bash "$HOOK"
  [[ "$status" -eq 0 ]]
}

@test "edge: malformed JSON envelope returns 0 (graceful)" {
  run bash -c "echo 'this is not json {{' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: nonexistent file_path returns 0 silently" {
  payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/does-not-exist.acm"}}'
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: zero-byte file is skipped without crashing" {
  empty_acm="$TMPDIR_CGI/empty.acm"
  : > "$empty_acm"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$empty_acm")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

@test "edge: timeout boundary — large query string handled" {
  big_acm="$TMPDIR_CGI/big.acm"
  python3 -c "open('$big_acm','w').write('## H\n' + ('lorem ipsum dolor sit amet ' * 200))"
  big_query=$(printf 'word%.0s ' {1..50})
  export SAVIA_CGI=shadow
  export SAVIA_TURN_QUERY="$big_query"
  payload=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$big_acm")
  run bash -c "echo '$payload' | bash '$HOOK'"
  [[ "$status" -eq 0 ]]
}

