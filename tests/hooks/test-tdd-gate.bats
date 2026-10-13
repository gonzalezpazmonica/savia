#!/usr/bin/env bats
# Tests for tdd-gate.sh hook
# Validates TDD gate: blocks production code edits when no tests exist
# Ref: docs/rules/domain/dev-session-protocol.md

setup() {
  TMPDIR=$(mktemp -d)
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  HOOK="$PWD/.opencode/hooks/tdd-gate.sh"
  # Use a path WITHOUT /test/ to avoid hook's */test/* exclusion
  export TEST_TMPDIR="/tmp/tddgate-$$-$BATS_TEST_NUMBER"
  rm -rf "$TEST_TMPDIR" 2>/dev/null || true
  mkdir -p "$TEST_TMPDIR/src" "$TEST_TMPDIR/tests" "$TEST_TMPDIR/tests/__tests__"
  cd "$TEST_TMPDIR"
  git init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_TMPDIR" 2>/dev/null || true
  rm -rf "$TMPDIR"
}

run_hook() {
  local tmpf="/tmp/tddgate-input-$$.json"
  printf '%s' "$1" > "$tmpf"
  run bash -c "cd '$TEST_TMPDIR' && cat '$tmpf' | bash '$HOOK'"
  rm -f "$tmpf"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/tdd-gate.sh"
}

# ── Non-Edit/Write tools pass ──

@test "Bash tool passes through" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ "$status" -eq 0 ]
}

@test "Read tool passes through" {
  run_hook '{"tool_name":"Read","tool_input":{"file_path":"test.md"}}'
  [ "$status" -eq 0 ]
}

@test "markdown file passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/docs/README.md\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "JSON config passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/package.json\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "test file Test suffix passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/ProductTest.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "test file .test. pattern passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/product.test.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "test file _test. pattern passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/product_test.go\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "file in tests directory passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/tests/helper.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "migration file passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/migrations/001_init.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

# ── Excluded basenames pass ──

@test "Program.cs passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/Program.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "DTO file passes" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/ProductDTO.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

# ── Production code WITHOUT tests: BLOCKED ──
# Note: uses unique filenames that won't match any existing test file in the repo

@test "BLOCKS .cs file without corresponding test" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/Zz99UniqueUncoveredHandler.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 2 ]
}

@test "BLOCKS .py file without corresponding test" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/zz99_unique_uncovered_service.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 2 ]
}

@test "BLOCKS .ts file without corresponding test" {
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/zz99UniqueUncoveredRouter.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 2 ]
}

# ── Production code WITH tests: PASSES ──

@test "passes .cs file when test exists" {
  touch "$TEST_TMPDIR/src/ProductHandler.cs"
  touch "$TEST_TMPDIR/tests/ProductHandlerTest.cs"
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/ProductHandler.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "passes .ts file when .test.ts exists" {
  touch "$TEST_TMPDIR/src/handler.ts"
  touch "$TEST_TMPDIR/tests/handler.test.ts"
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/handler.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

@test "passes .py file when test_ prefix exists" {
  touch "$TEST_TMPDIR/src/service.py"
  touch "$TEST_TMPDIR/tests/test_service.py"
  run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/service.py\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
  [ "$status" -eq 0 ]
}

# ── Write tool also triggers gate ──

@test "BLOCKS Write to .go file without test" {
  run_hook "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/src/zz99UniqueUncoveredMain.go\",\"content\":\"package main\"}}"
  [ "$status" -eq 2 ]
}

# ── Edge case: empty file_path ──
@test "empty file_path does not crash" {
  run_hook '{"tool_name":"Edit","tool_input":{"file_path":"","old_string":"a","new_string":"b"}}'
  [ "$status" -eq 0 ]
  python3 -c "assert True"
}

# ── Target directory that does not exist yet: resolve ITS repo, not the cwd one ──
# Regression 2026-10-13: writing the first file of tools/ in another repo was blocked
# because `git -C <missing dir>` failed and the lookup fell back to the session repo.

run_hook_from_other_repo() {
  local other="$TMPDIR/other-repo"
  mkdir -p "$other" && (cd "$other" && git init --quiet 2>/dev/null || true)
  local tmpf="$TMPDIR/tddgate-input.json"
  printf '%s' "$1" > "$tmpf"
  run bash -c "cd '$other' && cat '$tmpf' | bash '$HOOK'"
}

@test "passes when the test exists in the target repo even if the target dir is missing" {
  touch "$TEST_TMPDIR/tests/test_newtool.py"
  run_hook_from_other_repo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/newdir/tools/newtool.py\",\"content\":\"x\"}}"
  [ "$status" -eq 0 ]
}

@test "BLOCKS when the target repo has no test, even with a missing target dir (negative control)" {
  run_hook_from_other_repo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_TMPDIR/newdir/tools/orphantool.py\",\"content\":\"x\"}}"
  [ "$status" -eq 2 ]
}

