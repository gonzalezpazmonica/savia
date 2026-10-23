#!/usr/bin/env bats
# Tests for SE-091 CAVEMAN-ALWAYS — auto-grill-me.sh + auto-zoom-out.sh
# Ref: SPEC-SE-091-CAVEMAN-ALWAYS, docs/rules/domain/caveman-default.md

GRILL_HOOK="${BATS_TEST_DIRNAME}/../.opencode/hooks/auto-grill-me.sh"
ZOOM_HOOK="${BATS_TEST_DIRNAME}/../.opencode/hooks/auto-zoom-out.sh"
CAVEMAN_DOC="${BATS_TEST_DIRNAME}/../docs/rules/domain/caveman-default.md"
SETTINGS="${BATS_TEST_DIRNAME}/../.claude/settings.json"

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------

@test "auto-grill-me.sh exists" {
  [[ -f "$GRILL_HOOK" ]]
}

@test "auto-grill-me.sh is executable" {
  [[ -x "$GRILL_HOOK" ]]
}

@test "auto-zoom-out.sh exists" {
  [[ -f "$ZOOM_HOOK" ]]
}

@test "auto-zoom-out.sh is executable" {
  [[ -x "$ZOOM_HOOK" ]]
}

@test "auto-grill-me.sh uses set -uo pipefail" {
  run grep -E "set -uo pipefail" "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out.sh uses set -uo pipefail" {
  run grep -E "set -uo pipefail" "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# auto-grill-me: code file triggers
# ---------------------------------------------------------------------------

@test "auto-grill-me: triggers on .py file with Edit" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="src/main.py" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
  # message sent to stderr (run lo mezcla en $output)
  [[ "$output" == *"[auto-grill-me]"* ]]
}

@test "auto-grill-me: triggers on .sh file with Write" {
  run env OPENCODE_TOOL_NAME="Write" OPENCODE_TOOL_INPUT_PATH="scripts/deploy.sh" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-grill-me: triggers on .ts file" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="src/api.ts" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-grill-me: no-op for .md file" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="docs/readme.md" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-grill-me: no-op for .json file" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH=".claude/settings.json" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-grill-me: no-op when TOOL_NAME=Bash" {
  run env OPENCODE_TOOL_NAME="Bash" OPENCODE_TOOL_INPUT_PATH="src/main.py" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-grill-me: no-op when TOOL_NAME=Read" {
  run env OPENCODE_TOOL_NAME="Read" OPENCODE_TOOL_INPUT_PATH="src/main.py" bash "$GRILL_HOOK"
  [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# auto-zoom-out: architecture file triggers
# ---------------------------------------------------------------------------

@test "auto-zoom-out: triggers on ROADMAP.md with Edit" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="ROADMAP.md" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out: triggers on docs/propuestas/X.md" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="docs/propuestas/SE-099.md" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out: triggers on SPEC-*.md" {
  run env OPENCODE_TOOL_NAME="Write" OPENCODE_TOOL_INPUT_PATH="SPEC-185-something.md" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out: no-op for .py file" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="src/main.py" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out: no-op when TOOL_NAME=Bash" {
  run env OPENCODE_TOOL_NAME="Bash" OPENCODE_TOOL_INPUT_PATH="ROADMAP.md" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out: no-op when TOOL_NAME=Read" {
  run env OPENCODE_TOOL_NAME="Read" OPENCODE_TOOL_INPUT_PATH="ROADMAP.md" bash "$ZOOM_HOOK"
  [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# caveman-default.md
# ---------------------------------------------------------------------------

@test "caveman-default.md exists with caveman restrictions" {
  [[ -f "$CAVEMAN_DOC" ]]
  run grep -c "Zero filler\|Zero sugar-coating\|Token efficiency\|Default brevity\|Self-strip\|No preamble" "$CAVEMAN_DOC"
  [[ "$status" -eq 0 && "$output" -ge 4 ]]
}

# ---------------------------------------------------------------------------
# settings.json registration
# ---------------------------------------------------------------------------

@test "auto-grill-me registered in .claude/settings.json" {
  run grep "auto-grill-me" "$SETTINGS"
  [[ "$status" -eq 0 ]]
}

@test "auto-zoom-out registered in .claude/settings.json" {
  run grep "auto-zoom-out" "$SETTINGS"
  [[ "$status" -eq 0 ]]
}

@test "settings.json is valid JSON" {
  run python3 -c "import json, sys; json.load(open('$SETTINGS'))"
  [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Score auditor — hook quality score >= 80
# ---------------------------------------------------------------------------

@test "score auditor: SE-091 hooks score >= 80" {
  # Scoring criteria: existence(20) + executable(20) + set-uo-pipefail(20) + env-vars(20) + registered(20)
  local score=0

  [[ -f "$GRILL_HOOK" ]]  && (( score += 10 ))
  [[ -f "$ZOOM_HOOK" ]]   && (( score += 10 ))

  [[ -x "$GRILL_HOOK" ]]  && (( score += 10 ))
  [[ -x "$ZOOM_HOOK" ]]   && (( score += 10 ))

  grep -q "set -uo pipefail" "$GRILL_HOOK" && (( score += 10 ))
  grep -q "set -uo pipefail" "$ZOOM_HOOK"  && (( score += 10 ))

  grep -q "OPENCODE_TOOL_NAME"    "$GRILL_HOOK" && (( score += 10 ))
  grep -q "OPENCODE_TOOL_INPUT"   "$GRILL_HOOK" && (( score += 5  ))
  grep -q "OPENCODE_TOOL_NAME"    "$ZOOM_HOOK"  && (( score += 10 ))
  grep -q "OPENCODE_TOOL_INPUT"   "$ZOOM_HOOK"  && (( score += 5  ))

  grep -q "auto-grill-me" "$SETTINGS" && (( score += 5 ))
  grep -q "auto-zoom-out" "$SETTINGS" && (( score += 5 ))

  echo "Score: $score/100" >&3
  [[ "$score" -ge 80 ]]
}

# ── Isolation (setup/teardown with tmpdir) ────────────────────────────────────

setup() {
  HOOK_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$HOOK_TMPDIR"
}

# ── Edge cases ────────────────────────────────────────────────────────────────

@test "edge: empty TOOL_NAME → hooks are no-op (exit 0)" {
  run env OPENCODE_TOOL_NAME="" OPENCODE_TOOL_INPUT_PATH="main.py" bash "$GRILL_HOOK"
  [ "$status" -eq 0 ]
}

@test "edge: null/empty FILE_PATH → grill-me exits 0 (no match)" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="" bash "$GRILL_HOOK"
  [ "$status" -eq 0 ]
}

@test "edge: nonexistent file path still exits 0 (hooks are non-blocking)" {
  run env OPENCODE_TOOL_NAME="Write" OPENCODE_TOOL_INPUT_PATH="/nonexistent/path/file.py" bash "$GRILL_HOOK"
  [ "$status" -eq 0 ]
}

@test "edge: zero-length filename exits 0 for zoom-out" {
  run env OPENCODE_TOOL_NAME="Edit" OPENCODE_TOOL_INPUT_PATH="" bash "$ZOOM_HOOK"
  [ "$status" -eq 0 ]
}

@test "edge: no args to hooks exits 0 (hooks never require args)" {
  run bash "$GRILL_HOOK"
  [ "$status" -eq 0 ]
  run bash "$ZOOM_HOOK"
  [ "$status" -eq 0 ]
}
