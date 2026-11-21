#!/usr/bin/env bats
# Tests for compile-agent-index.sh — Compiled agent reference index
# Ref: docs/propuestas/SPEC-097-compiled-agent-index.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/compile-agent-index.sh"
  AGENTS_DIR="$REPO_ROOT/.claude/agents"
  REAL_INDEX="$REPO_ROOT/.claude/AGENTS-INDEX.md"
  TMPDIR_AI=$(mktemp -d "$BATS_TEST_TMPDIR/ai.XXXXXX")
  # Cada test trabaja sobre una copia: el índice versionado no se reescribe, corrompe ni borra
  # (la nocturna corre a la vez otras suites que leen el árbol real).
  export AGENT_INDEX_FILE="$TMPDIR_AI/AGENTS-INDEX.md"
  INDEX_FILE="$AGENT_INDEX_FILE"
  if [[ -f "$REAL_INDEX" ]]; then
    cp "$REAL_INDEX" "$INDEX_FILE"
  fi
}

# ── 1. Script existence and structure ────────────────────────────────────────

@test "script exists and is a regular file" {
  [ -f "$SCRIPT" ]
}

@test "script is executable" {
  [ -x "$SCRIPT" ]
}

@test "script has safety flags (set -uo pipefail)" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "script shows usage without arguments" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "script does not hardcode credentials" {
  ! grep -qiE '(AKIA|ghp_|sk-live|Bearer [A-Za-z0-9]{20,})' "$SCRIPT"
}

# ── 2. Compile ───────────────────────────────────────────────────────────────

@test "compile creates AGENTS-INDEX.md" {
  run bash "$SCRIPT" compile
  [ "$status" -eq 0 ]
  [ -f "$INDEX_FILE" ]
}

@test "compile output contains auto-generated header" {
  bash "$SCRIPT" compile
  grep -q "Auto-generated" "$INDEX_FILE"
}

@test "compile output contains SHA-256 hash" {
  bash "$SCRIPT" compile
  grep -qE "Hash: [a-f0-9]{20,}" "$INDEX_FILE"
}

@test "compile output contains Quick Routing table" {
  bash "$SCRIPT" compile
  grep -q "Quick Routing" "$INDEX_FILE"
}

@test "compile output contains Flows section" {
  bash "$SCRIPT" compile
  grep -q "Flows" "$INDEX_FILE"
}

@test "compile output contains All Agents table" {
  bash "$SCRIPT" compile
  grep -q "All Agents" "$INDEX_FILE"
}

@test "compile reports agent count in stdout" {
  run bash "$SCRIPT" compile
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
}

@test "compile output contains generation timestamp" {
  bash "$SCRIPT" compile
  grep -qE "Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}" "$INDEX_FILE"
}

@test "compile is idempotent (same line count on consecutive runs)" {
  bash "$SCRIPT" compile
  local lines1
  lines1=$(wc -l < "$INDEX_FILE")
  bash "$SCRIPT" compile
  local lines2
  lines2=$(wc -l < "$INDEX_FILE")
  [ "$lines1" -eq "$lines2" ]
}

# ── 3. Check freshness ──────────────────────────────────────────────────────

@test "check passes after fresh compile" {
  bash "$SCRIPT" compile
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH"* ]]
}

@test "check fails when no index exists" {
  rm -f "$INDEX_FILE"
  run bash "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

@test "check reports current vs stored hash on stale" {
  bash "$SCRIPT" compile
  # Corrupt the hash to simulate stale
  sed -i 's/Hash: [a-f0-9]*/Hash: 0000000000/' "$INDEX_FILE"
  run bash "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Current:"* ]]
  [[ "$output" == *"Stored:"* ]]
}

# ── 4. Stats ─────────────────────────────────────────────────────────────────

@test "stats shows total agent count" {
  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total agents"* ]]
}

@test "stats shows model distribution" {
  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"By model"* ]]
}

@test "stats shows permission level distribution" {
  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"By permission"* ]]
}

@test "stats reports index existence status" {
  bash "$SCRIPT" compile
  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Index:"* ]]
}

# ── 5. Show ──────────────────────────────────────────────────────────────────

@test "show displays index content after compile" {
  bash "$SCRIPT" compile
  run bash "$SCRIPT" show
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent Index"* ]]
}

@test "show fails with error when no index exists" {
  rm -f "$INDEX_FILE"
  run bash "$SCRIPT" show
  [ "$status" -eq 1 ]
  [[ "$output" == *"No index found"* ]]
}

# ── 6. Content quality ──────────────────────────────────────────────────────

@test "compiled index lists architect agent" {
  bash "$SCRIPT" compile
  grep -q "architect" "$INDEX_FILE"
}

@test "compiled index lists dotnet-developer agent" {
  bash "$SCRIPT" compile
  grep -q "dotnet-developer" "$INDEX_FILE"
}

@test "compiled index has SDD flow" {
  bash "$SCRIPT" compile
  grep -q "SDD" "$INDEX_FILE"
}

@test "compiled index has Security flow" {
  bash "$SCRIPT" compile
  grep -q "Security" "$INDEX_FILE"
}

@test "compiled index has Consensus flow" {
  bash "$SCRIPT" compile
  grep -q "Consensus" "$INDEX_FILE"
}

# ── 7. Edge cases ────────────────────────────────────────────────────────────

@test "unknown command shows error and exits non-zero" {
  run bash "$SCRIPT" foobar
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "compile succeeds even when run multiple times" {
  run bash "$SCRIPT" compile
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" compile
  [ "$status" -eq 0 ]
}

@test "check with corrupted index file detects stale" {
  echo "not a valid index" > "$INDEX_FILE"
  run bash "$SCRIPT" check
  [ "$status" -eq 1 ]
}

@test "stats works even without compiled index" {
  rm -f "$INDEX_FILE"
  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT COMPILED"* ]]
}

@test "compiled index line count is reasonable (>10 lines)" {
  bash "$SCRIPT" compile
  local lines
  lines=$(wc -l < "$INDEX_FILE")
  [ "$lines" -gt 10 ]
}

# ── Aislamiento ──────────────────────────────────────────────────────────────

@test "compile con AGENT_INDEX_FILE escribe ahí y no toca el índice versionado" {
  [ -f "$REAL_INDEX" ]
  before=$(sha256sum < "$REAL_INDEX")
  : > "$INDEX_FILE"
  run bash "$SCRIPT" compile
  [ "$status" -eq 0 ]
  [[ "$output" == *"$INDEX_FILE"* ]]
  grep -q "Auto-generated" "$INDEX_FILE"
  [ "$(sha256sum < "$REAL_INDEX")" = "$before" ]
}
