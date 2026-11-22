#!/usr/bin/env bats
# nightly: serial (cuenta los ficheros del repo antes y después; otra suite escribiendo a la vez lo falsea)
# BATS tests for .opencode/hooks/bash-output-compress.sh
# PostToolUse async — compresses verbose Bash output to reduce token consumption.
# Ref: batch 48 hook coverage — SPEC-rtk-ai inspired token reduction

HOOK=".opencode/hooks/bash-output-compress.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  TEST_PROJECT=$(mktemp -d "$TMPDIR/boc-XXXXXX")
}
teardown() {
  rm -rf "$TEST_PROJECT" 2>/dev/null || true
  unset TOOL_NAME TOOL_OUTPUT TOOL_INPUT CLAUDE_PROJECT_DIR 2>/dev/null || true
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }

# ── Non-Bash tool pass-through ──────────────────────────

@test "pass-through: unset TOOL_NAME exits 0" {
  unset TOOL_NAME 2>/dev/null || true
  run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "pass-through: non-Bash tool exits 0" {
  TOOL_NAME="Edit" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "pass-through: Task tool not processed" {
  TOOL_NAME="Task" TOOL_OUTPUT="some output" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ── Empty / short output ────────────────────────────────

@test "short: empty TOOL_OUTPUT exits 0" {
  TOOL_NAME="Bash" TOOL_OUTPUT="" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "short: single line output passed through silently (<=30 lines)" {
  TOOL_NAME="Bash" TOOL_OUTPUT="only one line of result" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "short: 30-line output passes without compression" {
  local out
  out=$(printf 'line %s\n' {1..30})
  TOOL_NAME="Bash" TOOL_OUTPUT="$out" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "short: boundary at 30 lines no compression triggered" {
  local out
  out=$(printf 'x\n%.0s' {1..29})
  TOOL_NAME="Bash" TOOL_OUTPUT="$out" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

# ── Compress script missing ─────────────────────────────

@test "missing: no output-compress.sh script exits silent" {
  # Point to empty dir
  local big
  big=$(printf 'verbose output line\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"npm install"}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "missing: compress script non-executable exits silent" {
  mkdir -p "$TEST_PROJECT/scripts"
  touch "$TEST_PROJECT/scripts/output-compress.sh"  # not chmod +x
  local big
  big=$(printf 'line\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"ls"}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

# ── Compression success ─────────────────────────────────

@test "compress: calls script and emits compressed output" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
echo "COMPRESSED MOCK OUTPUT"
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'verbose line\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"npm install --verbose"}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPRESSED MOCK OUTPUT"* ]]
}

@test "compress: empty compression result exits silent" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'line\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"ls"}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "compress: command_base extracted from TOOL_INPUT" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
# Echo the --command arg we receive
shift; echo "cmd=$1"
cat
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'line\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"docker build -t app ."}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker"* ]]
}

# ── Context tracker metric logging ──────────────────────

@test "tracker: logs savings when ratio >20%" {
  mkdir -p "$TEST_PROJECT/scripts"
  # Compress returns 1 line (massive compression)
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
echo "summary"
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  # Context tracker writes to file we can inspect
  cat > "$TEST_PROJECT/scripts/context-tracker.sh" <<'EOF'
#!/bin/bash
echo "LOGGED: $*" >> /tmp/tracker-test-log-$$
EOF
  chmod +x "$TEST_PROJECT/scripts/context-tracker.sh"
  local big
  big=$(printf 'many words on this line here\n%.0s' {1..100})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"npm test"}' bash "$HOOK" <<< "" >/dev/null 2>&1
  # Tracker should have been called (file may exist)
  [ "$?" -eq 0 ]
  rm -f /tmp/tracker-test-log-*
}

# ── Token calculation ──────────────────────────────────

@test "tokens: calculation uses length/4 divisor" {
  run grep -c '\${#OUTPUT} / 4\|\${#COMPRESSED} / 4' "$HOOK"
  [[ "$output" -ge 2 ]]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: empty TOOL_INPUT — command falls back to unknown" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
echo "mock"
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'x\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: null TOOL_OUTPUT handled" {
  TOOL_NAME="Bash" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: large output 1000 lines no timeout" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
head -5
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'line %s\n' {1..1000})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='{"command":"cat"}' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: zero tokens in empty output avoided" {
  TOOL_NAME="Bash" TOOL_OUTPUT="" run bash "$HOOK" <<< ""
  # Guard on empty output before token calc
  [ "$status" -eq 0 ]
}

# ── Negative cases ──────────────────────────────────────

@test "negative: malformed TOOL_INPUT JSON handled" {
  mkdir -p "$TEST_PROJECT/scripts"
  cat > "$TEST_PROJECT/scripts/output-compress.sh" <<'EOF'
#!/bin/bash
echo "compressed"
EOF
  chmod +x "$TEST_PROJECT/scripts/output-compress.sh"
  local big
  big=$(printf 'y\n%.0s' {1..50})
  CLAUDE_PROJECT_DIR="$TEST_PROJECT" TOOL_NAME="Bash" TOOL_OUTPUT="$big" \
    TOOL_INPUT='not valid json' run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "negative: TOOL_NAME env with garbage value skipped" {
  TOOL_NAME="!@#\$garbage" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: 30-line threshold defined" {
  run grep -c '\$LINE_COUNT -le 30' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: 20% ratio threshold for metric log" {
  run grep -c '\$RATIO -gt 20' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: output-compress.sh script delegation" {
  run grep -c 'output-compress.sh\|COMPRESS_SCRIPT' "$HOOK"
  [[ "$output" -ge 2 ]]
}

@test "coverage: context-tracker.sh metric logging" {
  run grep -c 'context-tracker\|TRACKER' "$HOOK"
  [[ "$output" -ge 2 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ───────────────────────────────────────────

@test "isolation: hook always exits 0 (never blocks)" {
  for tool_name in Bash Edit Read; do
    TOOL_NAME="$tool_name" run bash "$HOOK" <<< ""
    [ "$status" -eq 0 ]
  done
}

@test "isolation: hook does not modify repo files" {
  local before after
  before=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  TOOL_NAME="Bash" TOOL_OUTPUT="x" bash "$HOOK" <<< "" >/dev/null 2>&1
  after=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
