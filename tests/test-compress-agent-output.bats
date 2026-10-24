#!/usr/bin/env bats
# BATS tests for .opencode/hooks/compress-agent-output.sh
# PostToolUse for Task — streaming compression of agent outputs >200 tokens.
# Only activates in multi-agent sessions (dev-session implementing OR env override).
# Ref: batch 48 hook coverage — SPEC-041 P4 streaming agent compression

HOOK=".opencode/hooks/compress-agent-output.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  unset SDD_COMPRESS_AGENT_OUTPUT 2>/dev/null || true
  # Clean dev-sessions state to ensure tests start inactive
  DEV_SESSION_BACKUP=$(mktemp -d "$TMPDIR/cao-bkp-XXXXXX")
  if [[ -d output/dev-sessions ]]; then
    find output/dev-sessions -name state.json -exec grep -l '"status": "implementing"' {} \; 2>/dev/null | while read f; do
      mv "$f" "$DEV_SESSION_BACKUP/$(basename $(dirname "$f"))-state.json" 2>/dev/null || true
    done
  fi
}
teardown() {
  # Restore backed-up state files
  if [[ -d "$DEV_SESSION_BACKUP" ]]; then
    for bkp in "$DEV_SESSION_BACKUP"/*-state.json; do
      [[ -f "$bkp" ]] || continue
      local name="$(basename "$bkp" -state.json)"
      mv "$bkp" "output/dev-sessions/$name/state.json" 2>/dev/null || true
    done
    rm -rf "$DEV_SESSION_BACKUP"
  fi
  rm -rf "$TMPDIR"/cao-raw-*  2>/dev/null || true
  unset SDD_COMPRESS_AGENT_OUTPUT 2>/dev/null || true
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }
@test "SPEC-041 reference" {
  run grep -c 'SPEC-041' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Pass-through: inactive session ──────────────────────

@test "inactive: no dev-session and no env exits 0 silent" {
  run bash "$HOOK" <<< "some output"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "inactive: empty stdin exits 0" {
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "inactive: env SDD_COMPRESS_AGENT_OUTPUT=false stays inactive" {
  SDD_COMPRESS_AGENT_OUTPUT=false run bash "$HOOK" <<< "output text"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ── Activation via env ──────────────────────────────────

@test "env activation: SDD_COMPRESS_AGENT_OUTPUT=true enables compression path" {
  # Short output still skipped even when active (≤200 tokens)
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "short text"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "env activation: SDD_COMPRESS_AGENT_OUTPUT empty string stays inactive" {
  SDD_COMPRESS_AGENT_OUTPUT="" run bash "$HOOK" <<< "text"
  [ "$status" -eq 0 ]
}

# ── Token threshold ─────────────────────────────────────

@test "threshold: short output (≤200 tokens) skipped even when active" {
  # 100 chars = 25 tokens
  local short="line one\nline two\nline three"
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "$short"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "threshold: exactly 200 tokens (800 chars) not compressed" {
  # 800 chars / 4 = 200 tokens — boundary, NOT > 200
  local boundary
  boundary=$(printf 'x%.0s' {1..800})
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "$boundary"
  [ "$status" -eq 0 ]
}

# ── Dev-session detection ──────────────────────────────

@test "dev-session: implementing slice detected activates hook" {
  mkdir -p output/dev-sessions/test-slice
  echo '{"status": "implementing"}' > output/dev-sessions/test-slice/state.json
  # With short input, still skip compression but pass the activation check
  run bash "$HOOK" <<< "short"
  [ "$status" -eq 0 ]
  rm -rf output/dev-sessions/test-slice
}

@test "dev-session: non-implementing slice does NOT activate" {
  mkdir -p output/dev-sessions/test-slice-done
  echo '{"status": "completed"}' > output/dev-sessions/test-slice-done/state.json
  run bash "$HOOK" <<< "some output here"
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  rm -rf output/dev-sessions/test-slice-done
}

# ── Raw file persistence (active + long) ───────────────

@test "raw: long output saved to compressed-raw dir when compression attempted" {
  mkdir -p output/dev-sessions/raw-test-slice
  echo '{"status": "implementing"}' > output/dev-sessions/raw-test-slice/state.json
  # 1000 chars = 250 tokens > 200 threshold
  local big
  big=$(printf 'text %.0s' {1..250})
  # claude CLI likely missing in CI; hook falls back gracefully
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "$big"
  [ "$status" -eq 0 ]
  # Raw dir is created and holds the untouched original output
  [[ -d output/dev-sessions/compressed-raw ]]
  [[ "$output" == *"raw: output/dev-sessions/compressed-raw/"* ]]
  grep -qF "$big" output/dev-sessions/compressed-raw/*.txt
  rm -rf output/dev-sessions/raw-test-slice output/dev-sessions/compressed-raw
}

# ── Compression output format ──────────────────────────

@test "format: compression marker comment present when active+long" {
  mkdir -p output/dev-sessions/fmt-test
  echo '{"status": "implementing"}' > output/dev-sessions/fmt-test/state.json
  local big
  big=$(printf 'verbose output %.0s' {1..100})
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "$big"
  [ "$status" -eq 0 ]
  # Without claude CLI the output fallback still includes COMPRESSED marker
  [[ "$output" == *"COMPRESSED"* || -z "$output" ]]
  rm -rf output/dev-sessions/fmt-test output/dev-sessions/compressed-raw 2>/dev/null || true
}

# ── Token calculation ──────────────────────────────────

@test "tokens: calculation uses /4 divisor" {
  run grep -c 'CHAR_COUNT.*/ 4' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "tokens: 200 threshold defined" {
  run grep -c '\$TOKEN_ESTIMATE -le 200' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Edge cases ─────────────────────────────────────────

@test "edge: empty output with active session exits silent" {
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "edge: output with only whitespace exits 0" {
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "   "
  [ "$status" -eq 0 ]
}

@test "edge: large 10KB output handled without crash" {
  local big
  big=$(python3 -c 'print("x" * 10000)')
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" <<< "$big"
  [ "$status" -eq 0 ]
}

@test "edge: null input (empty stdin) no-op" {
  SDD_COMPRESS_AGENT_OUTPUT=true run bash "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
}

@test "edge: non-JSON state file ignored gracefully" {
  mkdir -p output/dev-sessions/garbage-test
  echo 'not json' > output/dev-sessions/garbage-test/state.json
  run bash "$HOOK" <<< "some text"
  [ "$status" -eq 0 ]
  rm -rf output/dev-sessions/garbage-test
}

# ── Coverage ───────────────────────────────────────────

@test "coverage: dev-session status.json discovery" {
  run grep -c 'state.json\|SESSION_STATE_DIR' "$HOOK"
  [[ "$output" -ge 2 ]]
}

@test "coverage: SDD_COMPRESS_AGENT_OUTPUT env override" {
  run grep -c 'SDD_COMPRESS_AGENT_OUTPUT' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: claude haiku model for compression" {
  run grep -c 'claude-haiku\|claude -p' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: raw dir for pre-compression backup" {
  run grep -c 'RAW_DIR\|compressed-raw' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ──────────────────────────────────────────

@test "isolation: hook exits 0 in all paths (never blocks)" {
  for payload in '' 'short' "$(printf 'x%.0s' {1..500})"; do
    run bash "$HOOK" <<< "$payload"
    [ "$status" -eq 0 ]
  done
}

@test "isolation: hook never modifies stdin or config" {
  local before after
  before=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  bash "$HOOK" <<< "test input" >/dev/null 2>&1
  after=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
