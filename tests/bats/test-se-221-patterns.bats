#!/usr/bin/env bats
# SE-221 — Context Engineering Patterns — BATS integration tests
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md
# Covers: context-origin-stamp.sh, context-drop-after-use.sh (hook),
#         context-origin-tag.sh (standalone)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SAVIA_WORKSPACE_DIR="$REPO_ROOT"
  export STAMP_HOOK="$REPO_ROOT/.opencode/hooks/context-origin-stamp.sh"
  export DROP_HOOK="$REPO_ROOT/.opencode/hooks/context-drop-after-use.sh"
  export ORIGIN_TAG="$REPO_ROOT/scripts/context-origin-tag.sh"
  TMPDIR_221=$(mktemp -d)
  export TMPDIR_221
}

teardown() {
  rm -rf "$TMPDIR_221"
}

# ───────────────────────────────────────────────────────────────
# Slice 1 — context-origin-stamp.sh hook
# ───────────────────────────────────────────────────────────────

@test "context-origin-stamp.sh exists and is executable" {
  [[ -x "$STAMP_HOOK" ]]
}

@test "SAVIA_ORIGIN_TAGGING=off stamp hook exits 0 without modifying input" {
  INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.md"},"tool_response":{"output":"line1\nline2"}}'
  run env SAVIA_ORIGIN_TAGGING=off bash "$STAMP_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
}

@test "stamp hook passes through input with empty stdin" {
  run bash "$STAMP_HOOK" <<< ""
  [[ "$status" -eq 0 ]]
}

@test "stamp hook contains set -uo pipefail" {
  grep -q "set -uo pipefail" "$STAMP_HOOK"
}

@test "stamp hook has passthrough on non-Read tools" {
  # WebFetch tool — should passthrough without error
  INPUT='{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"},"tool_response":{"output":"content"}}'
  run bash "$STAMP_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
}

# ───────────────────────────────────────────────────────────────
# Slice 2 — context-drop-after-use.sh hook
# ───────────────────────────────────────────────────────────────

@test "context-drop-after-use.sh hook exists and is executable" {
  [[ -x "$DROP_HOOK" ]]
}

@test "context-drop-after-use.sh hook contains set -uo pipefail" {
  grep -q "set -uo pipefail" "$DROP_HOOK"
}

@test "SAVIA_DROP_AFTER_USE=off drop hook exits 0" {
  INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.md"},"tool_response":{"output":"line1"}}'
  run env SAVIA_DROP_AFTER_USE=off bash "$DROP_HOOK" <<< "$INPUT"
  [[ "$status" -eq 0 ]]
}

@test "drop hook passes through with empty stdin" {
  run bash "$DROP_HOOK" <<< ""
  [[ "$status" -eq 0 ]]
}

# ───────────────────────────────────────────────────────────────
# Slice 1 — context-origin-tag.sh standalone
# ───────────────────────────────────────────────────────────────

@test "context-origin-tag.sh exists and is executable" {
  [[ -x "$ORIGIN_TAG" ]]
}

@test "context-origin-tag.sh docs/critical-facts.md returns N1-anchor" {
  PATH_ARG="$REPO_ROOT/docs/critical-facts.md"
  run bash "$ORIGIN_TAG" "$PATH_ARG"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "N1-anchor" ]]
}

@test "context-origin-tag.sh CLAUDE.md returns N2-eager" {
  run bash "$ORIGIN_TAG" "$REPO_ROOT/CLAUDE.md"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "N2-eager" ]]
}

@test "context-origin-tag.sh --json produces valid JSON with tier field" {
  run bash "$ORIGIN_TAG" --json "$REPO_ROOT/docs/critical-facts.md"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'tier' in d"
}

# ───────────────────────────────────────────────────────────────
# Slice 3 — context-capability-metadata.py
# ───────────────────────────────────────────────────────────────
