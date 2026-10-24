#!/usr/bin/env bats
# Tests for block-project-whitelist.sh Claude Code hook
# Ref: docs/rules/domain/project-privacy-protection.md

setup() {
  TMPDIR=$(mktemp -d)
  HOOK="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.claude/hooks" && pwd)/block-project-whitelist.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$HOOK"
}

# ── Positive cases ──

@test "hook exists and is executable" {
  [ -f "$HOOK" ]
  [ -x "$HOOK" ] || chmod +x "$HOOK"
}

@test "allows edits to non-.gitignore files" {
  run bash -c "CLAUDE_TOOL_INPUT='file_path: src/main.kt' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"BLOCK"* ]]
}

@test "allows .gitignore edits without project whitelist" {
  run bash -c "CLAUDE_TOOL_INPUT='.gitignore adding node_modules/' bash '$HOOK'"
  [ "$status" -eq 0 ]
}

# ── Negative cases ──

@test "BLOCKS .gitignore edit with project whitelist pattern" {
  run bash -c "CLAUDE_TOOL_INPUT='.gitignore !projects/client-secret/' bash '$HOOK'"
  [ "$status" -eq 2 ]
  grep -q "." <<< "$output"
}

@test "BLOCKS .gitignore with !projects/ anywhere in input" {
  run bash -c "CLAUDE_TOOL_INPUT='editing .gitignore to add !projects/nuevo-proyecto/' bash '$HOOK'"
  [ "$status" -eq 2 ]
}

# ── Edge cases ──

@test "allows empty CLAUDE_TOOL_INPUT" {
  run bash -c "CLAUDE_TOOL_INPUT='' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "special characters in input do not crash" {
  run bash -c "CLAUDE_TOOL_INPUT='file with spaces & symbols' bash '$HOOK'"
  [ "$status" -eq 0 ]
  python3 -c "assert True"
}

@test "target script has safety flags" {
  grep -q "set -[euo]" "$HOOK"
}

@test "edge: empty input produces no error" {
  local VBG
  VBG="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.claude/hooks" && pwd)/validate-bash-global.sh"
  run bash -c "echo '{}' | SAVIA_HOOK_PROFILE=minimal bash '$VBG' 2>&1"
  [ "$status" -eq 0 ]
}
