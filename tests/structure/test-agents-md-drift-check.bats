#!/usr/bin/env bats
# Ref: SE-078 — agents-md-drift-check.sh

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT_DIR/scripts/agents-md-drift-check.sh"
  TMP=$(mktemp -d)
  AGENTS_DIR="$TMP/agents"
  mkdir -p "$AGENTS_DIR"
  export AGENTS_DIR
  export AGENTS_MD="$TMP/AGENTS.md"
  export PROJECT_ROOT="$TMP"
}

teardown() { rm -rf "$TMP"; }

make_agent() {
  cat > "$AGENTS_DIR/$1.md" <<EOF
---
name: $1
permission_level: L1
description: ${2:-test}
tools: [Read]
model: claude-sonnet-4-6
---

# $1
EOF
}

@test "drift-check: exits 0 when AGENTS.md matches generator" {
  make_agent "alpha"
  bash "$ROOT_DIR/scripts/agents-md-generate.sh" --apply >/dev/null
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "drift-check: exits 1 when AGENTS.md missing" {
  make_agent "alpha"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "drift-check: exits 1 when an agent added but AGENTS.md not regenerated" {
  make_agent "alpha"
  bash "$ROOT_DIR/scripts/agents-md-generate.sh" --apply >/dev/null
  make_agent "bravo"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]]
}

@test "drift-check: exits 1 when stale entry remains for deleted agent" {
  make_agent "alpha"
  make_agent "bravo"
  bash "$ROOT_DIR/scripts/agents-md-generate.sh" --apply >/dev/null
  rm "$AGENTS_DIR/bravo.md"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "drift-check: prints diff hint to stderr on drift" {
  make_agent "alpha"
  bash "$ROOT_DIR/scripts/agents-md-generate.sh" --apply >/dev/null
  make_agent "bravo"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift detected"* ]]
}

@test "edge: empty agents dir + missing AGENTS.md still produces drift exit 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "spec ref: SE-078 cited in drift-check header" {
  grep -q "SE-078" "$SCRIPT"
}

@test "safety: drift-check has set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}
