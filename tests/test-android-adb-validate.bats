#!/usr/bin/env bats
# BATS tests for .opencode/hooks/android-adb-validate.sh
# PreToolUse hook — classifies ADB commands: safe / risky / blocked.
# Exit 0 = allow, exit 2 = block.
# Ref: batch 46 hook coverage — SPEC-044 ADB safety classification

HOOK=".opencode/hooks/android-adb-validate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export SAVIA_HOOK_PROFILE="${SAVIA_HOOK_PROFILE:-standard}"
  TEST_HOME=$(mktemp -d "$TMPDIR/aav-home-XXXXXX")
}
teardown() {
  rm -rf "$TEST_HOME" 2>/dev/null || true
  cd /
}

@test "hook exists" { [[ -f "$HOOK" ]]; }
@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}
@test "passes bash -n syntax" { run bash -n "$HOOK"; [ "$status" -eq 0 ]; }
@test "has profile_gate standard" {
  run grep -c 'profile_gate "standard"' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# ── Non-ADB commands pass through ───────────────────────

@test "pass-through: unset TOOL_INPUT exits 0" {
  unset TOOL_INPUT 2>/dev/null || true
  HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "pass-through: non-ADB command exits 0" {
  TOOL_INPUT="ls -la /tmp" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "pass-through: random bash command exits 0" {
  TOOL_INPUT="git status" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

# ── Safe ADB operations ─────────────────────────────────

@test "safe: adb devices logged as SAFE" {
  TOOL_INPUT="adb devices" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"SAFE"* ]]
}

@test "safe: adb logcat allowed" {
  TOOL_INPUT="adb logcat -d" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "safe: adb shell getprop allowed" {
  TOOL_INPUT="adb shell getprop ro.build.version.release" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

# ── Risky operations: allowed + logged ──────────────────

@test "risky: adb install logged as RISKY" {
  TOOL_INPUT="adb install app.apk" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb uninstall logged as RISKY" {
  TOOL_INPUT="adb uninstall com.example.app" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb shell pm clear logged as RISKY" {
  TOOL_INPUT="adb shell pm clear com.example" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb push logged as RISKY" {
  TOOL_INPUT="adb push file.txt /sdcard/" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb reboot logged as RISKY" {
  TOOL_INPUT="adb reboot" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb shell monkey logged as RISKY" {
  TOOL_INPUT="adb shell monkey -p com.example 100" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb_install function name logged" {
  TOOL_INPUT="adb_install app.apk" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

@test "risky: adb shell am force-stop logged" {
  TOOL_INPUT="adb shell am force-stop com.example" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"RISKY"* ]]
}

# ── Blocked: destructive ops ────────────────────────────

@test "block: adb shell rm -rf exits 2" {
  TOOL_INPUT="adb shell rm -rf /data" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
  [[ "${output}${stderr:-}" == *"blocked for safety"* ]]
}

@test "block: adb shell rm -r / exits 2" {
  TOOL_INPUT="adb shell rm -r /storage/emulated" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
}

@test "block: adb shell format exits 2" {
  TOOL_INPUT="adb shell format /sdcard" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
}

@test "block: adb shell dd if= exits 2" {
  TOOL_INPUT="adb shell dd if=/dev/zero of=/data/x" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
}

@test "block: adb shell su - exits 2" {
  TOOL_INPUT="adb shell su -c id" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
}

@test "block: adb root exits 2" {
  TOOL_INPUT="adb root" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 2 ]
}

@test "block: destructive logged as BLOCKED" {
  TOOL_INPUT="adb shell rm -rf /cache" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" == *"BLOCKED"* ]]
}

# ── Log file creation ───────────────────────────────────

@test "log: log dir auto-created" {
  [[ ! -d "$TEST_HOME/.claude/logs" ]]
  TOOL_INPUT="adb devices" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [[ -d "$TEST_HOME/.claude/logs" ]]
}

@test "log: entries include ISO timestamp" {
  TOOL_INPUT="adb devices" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  run cat "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "log: multiple invocations append" {
  TOOL_INPUT="adb devices" HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  TOOL_INPUT="adb shell ls" HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  run wc -l < "$TEST_HOME/.claude/logs/android-adb.log"
  [[ "$output" -ge 2 ]]
}

# ── Edge cases ──────────────────────────────────────────

@test "edge: command without trailing space (adbdev)" {
  TOOL_INPUT="adbdev" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  # Pattern "adb " requires space, so adbdev without space should skip
  [ "$status" -eq 0 ]
}

@test "edge: adb inside longer command" {
  TOOL_INPUT="echo 'testing adb devices command'" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  # Contains "adb " so it will be processed as ADB
  [ "$status" -eq 0 ]
}

@test "edge: empty TOOL_INPUT exits 0" {
  TOOL_INPUT="" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: null-byte unicode in command (no overflow)" {
  TOOL_INPUT="adb shell echo 'special chars: !@#\$%'" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: large command with adb prefix no timeout" {
  local big
  big="adb shell echo $(printf 'x%.0s' {1..500})"
  TOOL_INPUT="$big" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
}

@test "edge: adb with no-arg subcommand" {
  TOOL_INPUT="adb" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
  # Pattern requires "adb " with space — bare "adb" does NOT match, skip
  [ "$status" -eq 0 ]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: BLOCKED_PATTERNS array defined" {
  run grep -c 'BLOCKED_PATTERNS=' "$HOOK"
  [[ "$output" -ge 1 ]]
}

@test "coverage: RISKY_PATTERNS array defined" {
  run grep -c 'RISKY_PATTERNS=' "$HOOK"
  [[ "$output" -ge 1 ]]
}

# Los dos patrones de rm (-rf y -r /) se unieron en uno que acepta cualquier orden de opciones (#1398):
# el recuento baja a 5 sin perder cobertura; el comportamiento lo prueban los tests de bloqueo.
@test "coverage: 5 blocked patterns defined" {
  local count
  count=$(sed -n '/BLOCKED_PATTERNS=/,/^)/p' "$HOOK" | grep -c '^ *".*"$' || echo 0)
  [[ "$count" -ge 5 ]]
}

@test "coverage: 9+ risky patterns defined" {
  local count
  count=$(sed -n '/RISKY_PATTERNS=/,/)/p' "$HOOK" | grep -c '".*"' || echo 0)
  [[ "$count" -ge 9 ]]
}

@test "coverage: TMPDIR used in tests" {
  run grep -c 'TMPDIR\|mktemp' "$BATS_TEST_FILENAME"
  [[ "$output" -ge 1 ]]
}

# ── Isolation ───────────────────────────────────────────

@test "isolation: exit codes limited to {0, 2}" {
  for cmd in "adb devices" "adb install x.apk" "adb shell rm -rf /" "ls"; do
    TOOL_INPUT="$cmd" HOME="$TEST_HOME" run bash "$HOOK" <<< ""
    [[ "$status" -eq 0 || "$status" -eq 2 ]]
  done
}

@test "isolation: hook does not modify repo" {
  local before after
  before=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  TOOL_INPUT="adb devices" HOME="$TEST_HOME" bash "$HOOK" <<< "" >/dev/null 2>&1
  after=$(find . -maxdepth 2 -type f 2>/dev/null | wc -l)
  [[ "$before" == "$after" ]]
}
