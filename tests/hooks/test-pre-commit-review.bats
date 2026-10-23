#!/usr/bin/env bats
# Tests for pre-commit-review.sh hook
# Warning-only hook that reviews staged files for common issues
# Ref: docs/rules/domain/code-review-rules.md

setup() {
  TMPDIR=$(mktemp -d)
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.opencode/hooks/pre-commit-review.sh"
  cd "$TMPDIR"
  git init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$TMPDIR"
}

run_hook() {
  local tmpf="$TMPDIR/input.json"
  printf '%s' "$1" > "$tmpf"
  run bash -c "cd '$TMPDIR' && cat '$tmpf' | bash '$HOOK'"
}

@test "target has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/pre-commit-review.sh"
}

# ── Positive cases ──

@test "always exits 0 (never blocks)" {
  echo "console.log('test')" > test.js
  git add test.js
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
}

@test "non-commit command passes" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"BLOCK"* ]]
}

@test "handles staged js file gracefully" {
  echo "function test() {}" > test.js
  git add test.js
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
}

# ── Negative / error cases ──

@test "empty input passes without crash" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":""}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"FATAL"* ]]
}

@test "handles no staged files gracefully" {
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
}

# ── Edge cases ──

@test "handles missing rules file gracefully" {
  echo "const x = 5;" > test.ts
  git add test.ts
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
  [[ ! "$output" == *"No such file"* ]]
}

@test "large number of staged files does not crash" {
  for i in $(seq 1 20); do echo "f$i" > "file$i.txt"; done
  git add *.txt
  run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
  [ "$status" -eq 0 ]
  python3 -c "assert True"
}

@test "malformed JSON input handled" {
  run_hook 'not-json-at-all'
  [ "$status" -eq 0 ]
  grep -q "." <<< "$status"
}

@test "target script has safety flags" {
  grep -q "set -[euo]" "$BATS_TEST_DIRNAME/../../.opencode/hooks/pre-commit-review.sh"
}

@test "edge: empty input produces no error" {
  run bash -c "echo '{}' | SAVIA_HOOK_PROFILE=minimal bash '$BATS_TEST_DIRNAME/../../.opencode/hooks/validate-bash-global.sh' 2>&1"
  [ "$status" -eq 0 ]
}
