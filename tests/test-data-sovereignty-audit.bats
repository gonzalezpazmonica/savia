#!/usr/bin/env bats
# BATS tests for .opencode/hooks/data-sovereignty-audit.sh (PostToolUse async)
# Ref: batch 39 hook test coverage gap

HOOK=".opencode/hooks/data-sovereignty-audit.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export CLAUDE_PROJECT_DIR="$TMPDIR/workspace-$$"
  mkdir -p "$CLAUDE_PROJECT_DIR/output"
  # Hook requires security profile tier to activate (profile_gate "security")
  export SAVIA_HOOK_PROFILE=security
  # Default enabled; individual tests may override
  unset SAVIA_SHIELD_ENABLED
}
teardown() {
  rm -rf "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
  cd /
}

@test "hook exists and is executable" { [[ -x "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }

# ── Skip paths ───────────────────────────────────────────

@test "skip: SAVIA_SHIELD_ENABLED=false exits 0 (disabled)" {
  export SAVIA_SHIELD_ENABLED=false
  run bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/x.txt"}}'
  [ "$status" -eq 0 ]
}

@test "skip: empty stdin exits 0" {
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "skip: missing file_path exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{}}'
  [ "$status" -eq 0 ]
}

@test "skip: nonexistent file exits 0" {
  run bash "$HOOK" <<< '{"tool_input":{"file_path":"/nonexistent/file.txt"}}'
  [ "$status" -eq 0 ]
}

# ── Private file exemptions (is_public returns false) ────

@test "exempt: projects/ path not audited" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/projects/alpha/secret.sql"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "jdbc:mysql://x" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
  # No leak logged because file skipped as private
  [[ ! -s "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl" ]] || \
    ! grep -q 'LEAK_DETECTED' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "exempt: output/ path not audited" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/output/log.txt"
  echo "AKIAXXXXXXXXXXXXXXXX" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

@test "exempt: .local. files not audited" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/config.local.json"
  echo "ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

@test "exempt: .savia/ path not audited" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/.savia/state.json"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "sk-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

@test "exempt: data-sovereignty script bypasses self" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/scripts/data-sovereignty-check.sh"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "grep -E 'jdbc:'" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

# ── Leak detection (real leaks logged) ───────────────────

@test "detect: JDBC connection string logged as leak" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/example.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "use jdbc:mysql://server/db" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]  # async audit always exits 0
  grep -q 'connection_string_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "detect: AWS key logged as leak" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/leak.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "export AWS_KEY=AKIAIOSFODNN7EXAMPLE" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  grep -q 'aws_key_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "detect: private key logged" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/cert.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  printf -- "-----BEGIN RSA PRIVATE KEY-----\nMIIE\n" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  grep -q 'private_key_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "detect: internal IP 192.168.x.x logged" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/net.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "gateway 192.168.1.1" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  grep -q 'internal_ip_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

# ── Negative cases ───────────────────────────────────────

@test "negative: malformed JSON exits 0 (fail open)" {
  run bash "$HOOK" <<< "not json"
  [ "$status" -eq 0 ]
}

@test "negative: clean public file emits no leak" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/clean.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "This is a clean file with no secrets" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
  ! grep -q 'LEAK_DETECTED' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl" 2>/dev/null
}

@test "negative: empty file audited without crash" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/empty.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  : > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

# ── Edge cases ───────────────────────────────────────────

@test "edge: empty stdin logs TIMEOUT_SKIP marker" {
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl" ]
  grep -q '"verdict":"TIMEOUT_SKIP"' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "edge: github PAT pattern detected (constructed to avoid pre-commit block)" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/pat.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  # Construct pattern dynamically to avoid tripping block-credential-leak during test grep
  local prefix="ghp" sep="_" body="abcdefghijklmnopqrstuvwxyz0123456789"
  printf "token %s%s%s\n" "$prefix" "$sep" "$body" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  grep -q 'github_token_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

@test "edge: openai key sk-* pattern detected (constructed)" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/key.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  local prefix="sk" sep="-" body="abcdefghijklmnopqrstuvwxyz0123"
  printf "key: %s%s%s\n" "$prefix" "$sep" "$body" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  grep -q 'openai_key_in_public_file' "$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
}

# ── Coverage ──────────────────────────────────────────────

@test "coverage: is_public function defined" {
  run grep -c '^is_public()' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: iso_ts helper defined" {
  run grep -c 'iso_ts()' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: 6 leak patterns scanned (connection, aws, github, openai, private-key, ip)" {
  for pat in jdbc AKIA ghp_ sk- PRIVATE.KEY 192; do
    grep -q "$pat" "$HOOK" || fail "missing pattern: $pat"
  done
}

# ── Isolation ─────────────────────────────────────────────

@test "isolation: exit always 0 (PostToolUse async never blocks)" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/x.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "AKIAXXXXXXXXXXXXXXXX jdbc:mysql://x" > "$TMP_FILE"
  run bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"
  [ "$status" -eq 0 ]
}

@test "isolation: audit log appended, never overwrites" {
  local TMP_FILE="$CLAUDE_PROJECT_DIR/docs/a.md"
  mkdir -p "$(dirname "$TMP_FILE")"
  echo "AKIAXXXXXXXXXXXXXXXX" > "$TMP_FILE"
  bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}" >/dev/null 2>&1
  bash "$HOOK" <<< "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}" >/dev/null 2>&1
  lines=$(wc -l <"$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl")
  [[ "$lines" -ge 2 ]]
}
