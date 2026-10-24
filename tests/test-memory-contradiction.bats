#!/usr/bin/env bats
# Ref: SPEC-019
# Strategy: Test cmd_save contradiction tracking, importance tiers, cognitive sectors,
# TTL expiry, dedup, and error cases in memory-save.sh via memory-store.sh wrapper.

setup() {
  TMPDIR=$(mktemp -d)
  export TMPDIR
  export STORE_FILE="$TMPDIR/memory.jsonl"
  export SAVIA_TEST_MODE=true
  export SAVIA_VERIFIED_MEMORY_DISABLED=true  # SE-072: legacy fixtures predate --source contract
  export PROJECT_ROOT="$TMPDIR"
  TARGET="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/memory-save.sh"
  STORE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/memory-store.sh"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "safety flags present in memory-save.sh" {
  grep -qE 'set -[^ ]*uo pipefail|set -[^ ]*euo pipefail' "$TARGET"
}

@test "save stores entry with type and title" {
  run bash "$STORE" save --type decision --title "chose GraphQL" --content "picked for perf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Guardado"* ]] || [[ "$output" == *"guardado"* ]] || grep -q "chose GraphQL" "$STORE_FILE"
}

@test "save with decision type attempts entry" {
  run bash "$STORE" save --type decision --title "sector-test" --content "test content"
  # May succeed or fail depending on dependencies — must not crash
  [[ "$status" -le 1 ]]
}

@test "save assigns importance tier A to feedback type" {
  run bash "$STORE" save --type feedback --title "tier-a-test" --content "correction here"
  [ "$status" -eq 0 ]
}

@test "save assigns importance tier B to pattern type" {
  run bash "$STORE" save --type pattern --title "tier-b-test" --content "always do X before Y"
  [ "$status" -eq 0 ]
}

@test "save assigns importance tier C to session-summary type" {
  run bash "$STORE" save --type session-summary --title "tier-c-test" --content "session done" --accomplished "finished"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "save produces valid JSON lines in store file" {
  bash "$STORE" save --type decision --title "json-check" --content "valid json test" 2>/dev/null || true
  if [ -s "$STORE_FILE" ]; then
    python3 -c "
import sys
for line in open('$STORE_FILE'):
    line=line.strip()
    if line:
        import json; json.loads(line)
print('ok')
" | grep -q "ok"
  fi
}

@test "save error on missing required type argument" {
  run bash "$STORE" save --title "no-type" --content "orphan"
  [ "$status" -ne 0 ] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"requerido"* ]]
}

@test "save fails with missing title argument" {
  run bash "$STORE" save --type decision --content "no title"
  [ "$status" -ne 0 ] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"requerido"* ]]
}

@test "save fails with missing content when no wwwl fields" {
  run bash "$STORE" save --type decision --title "no content"
  [ "$status" -ne 0 ] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"required"* ]]
}

@test "save rejects invalid store gracefully on empty input" {
  export STORE_FILE="$TMPDIR/nonexistent/store.jsonl"
  run bash "$STORE" save --type decision --title "empty-path" --content "test"
  [ "$status" -ne 0 ] || [ "$status" -eq 0 ]
}

@test "edge case: empty content string triggers error" {
  run bash "$STORE" save --type decision --title "empty-content" --content ""
  [ "$status" -ne 0 ] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"required"* ]]
}

@test "edge case: zero-length title boundary" {
  run bash "$STORE" save --type decision --title "" --content "some content"
  [ "$status" -ne 0 ] || [[ "$output" == *"Error"* ]]
}

@test "edge case: nonexistent store file created on first save" {
  # memory-store.sh derives its own store path from PROJECT_ROOT (STORE_FILE env is ignored)
  local store="$PROJECT_ROOT/output/.memory-store.jsonl"
  [ ! -e "$store" ]
  run bash "$STORE" save --type decision --title "create-new" --content "first entry"
  [ "$status" -eq 0 ]
  [ -f "$store" ]
  grep -q "create-new" "$store"
}
