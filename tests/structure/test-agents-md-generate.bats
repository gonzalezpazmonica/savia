#!/usr/bin/env bats
# Ref: SE-078 — agents-md-generate.sh

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT_DIR/scripts/agents-md-generate.sh"
  TMP=$(mktemp -d)
  AGENTS_DIR="$TMP/agents"
  mkdir -p "$AGENTS_DIR"
  export AGENTS_DIR
  export AGENTS_MD="$TMP/AGENTS.md"
  export PROJECT_ROOT="$TMP"
}

teardown() {
  rm -rf "$TMP"
}

# Helper: write a fake agent
make_agent() {
  local name="$1" perm="$2" model="${3:-claude-sonnet-4-6}" desc="${4:-test agent}"
  cat > "$AGENTS_DIR/${name}.md" <<EOF
---
name: ${name}
permission_level: ${perm}
description: ${desc}
tools:
  - Read
  - Bash
model: ${model}
---

# ${name}
EOF
}

# ── Usage / dispatch ─────────────────────────────────────────────────────────

@test "agents-md: --help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "agents-md: rejects unknown flag with exit 2" {
  run bash "$SCRIPT" --frobnicate
  [ "$status" -eq 2 ]
}

@test "agents-md: missing agents dir exits 3" {
  AGENTS_DIR="$TMP/nope" run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"agents dir not found"* ]]
}

# ── Generate (default mode) ─────────────────────────────────────────────────

@test "agents-md: generate emits valid header + table" {
  make_agent "alpha" "L1"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# AGENTS.md"* ]]
  [[ "$output" == *"| Name | Model | Permission | Tools | Description |"* ]]
  [[ "$output" == *"| alpha |"* ]]
}

@test "agents-md: generate produces N rows for N agents" {
  make_agent "alpha" "L1"
  make_agent "bravo" "L2"
  make_agent "charlie" "L3"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Count data rows (every row starting "| <name> |") — excludes the
  # header (`| Name |`) by matching the lowercased agent names directly.
  count=$(echo "$output" | grep -cE '^\| (alpha|bravo|charlie) \|')
  [ "$count" -eq 3 ]
}

@test "agents-md: generate is deterministic (twice = byte-equal)" {
  make_agent "alpha" "L1"
  make_agent "bravo" "L2"
  out1=$(bash "$SCRIPT")
  out2=$(bash "$SCRIPT")
  [ "$out1" = "$out2" ]
}

@test "agents-md: agents are sorted alphabetically" {
  make_agent "zulu" "L1"
  make_agent "alpha" "L1"
  make_agent "mike" "L1"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Get only the rows with agent names
  alpha_line=$(echo "$output" | grep -n '| alpha |' | head -1 | cut -d: -f1)
  mike_line=$(echo "$output" | grep -n '| mike |' | head -1 | cut -d: -f1)
  zulu_line=$(echo "$output" | grep -n '| zulu |' | head -1 | cut -d: -f1)
  [ "$alpha_line" -lt "$mike_line" ]
  [ "$mike_line" -lt "$zulu_line" ]
}

@test "agents-md: README.md inside agents dir is skipped" {
  make_agent "alpha" "L1"
  echo "# README" > "$AGENTS_DIR/README.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"| README |"* ]]
}

@test "agents-md: agent without name field is skipped with stderr warning" {
  cat > "$AGENTS_DIR/broken.md" <<'EOF'
---
permission_level: L1
description: missing name
---
EOF
  make_agent "alpha" "L1"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # The skipped agent must NOT appear as a data row in the output table.
  ! echo "$output" | grep -qE '^\| broken \|'
  # And alpha must still appear
  echo "$output" | grep -qE '^\| alpha \|'
}

@test "agents-md: long description is truncated to 120 chars" {
  local long_desc; long_desc=$(printf 'a%.0s' {1..200})
  make_agent "alpha" "L1" "claude-sonnet-4-6" "$long_desc"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # Find the row, extract description, check length ≤ 120 (3 dots count)
  row=$(echo "$output" | grep '^| alpha |' | head -1)
  [[ "$row" == *"..."* ]]
}

# ── --apply (atomic write) ──────────────────────────────────────────────────

@test "agents-md: --apply writes the file atomically" {
  make_agent "alpha" "L1"
  run bash "$SCRIPT" --apply
  [ "$status" -eq 0 ]
  [ -f "$AGENTS_MD" ]
  grep -q "| alpha |" "$AGENTS_MD"
}

@test "agents-md: --apply replaces existing AGENTS.md" {
  make_agent "alpha" "L1"
  echo "stale content" > "$AGENTS_MD"
  bash "$SCRIPT" --apply
  ! grep -q "stale content" "$AGENTS_MD"
  grep -q "| alpha |" "$AGENTS_MD"
}

# ── --check (drift detection) ───────────────────────────────────────────────

@test "agents-md: --check exits 1 when AGENTS.md missing" {
  make_agent "alpha" "L1"
  run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

@test "agents-md: --check exits 0 when in sync" {
  make_agent "alpha" "L1"
  bash "$SCRIPT" --apply >/dev/null
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
}

@test "agents-md: --check exits 1 when an agent is added without re-apply" {
  make_agent "alpha" "L1"
  bash "$SCRIPT" --apply >/dev/null
  make_agent "bravo" "L2"
  run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]]
}

@test "agents-md: --check exits 1 when AGENTS.md edited by hand" {
  make_agent "alpha" "L1"
  bash "$SCRIPT" --apply >/dev/null
  echo "extra hand-edit line" >> "$AGENTS_MD"
  run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: empty agents dir produces a header-only AGENTS.md" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# AGENTS.md"* ]]
  [[ "$output" == *"## Agents"* ]]
}

@test "edge: nonexistent description field falls back to dash" {
  cat > "$AGENTS_DIR/no-desc.md" <<'EOF'
---
name: no-desc
permission_level: L1
---
EOF
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| no-desc |"* ]]
}

@test "edge: large set of 30 agents produces 30 data rows" {
  for i in $(seq -f '%02g' 1 30); do
    make_agent "agent${i}" "L1"
  done
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | grep -c '^| agent')
  [ "$count" -eq 30 ]
}

# ── Static / safety / spec ref ──────────────────────────────────────────────

@test "spec ref: SE-078 cited in script header" {
  grep -q "SE-078" "$SCRIPT"
}

@test "safety: agents-md-generate.sh has set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "safety: no destructive git commands" {
  ! grep -E '^[^#]*git\s+(push|reset\s+--hard|branch\s+-D)' "$SCRIPT"
}

@test "agents-md: startup exposes shared context and frontend boundaries" {
  make_agent "alpha" "L1"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'read `CLAUDE.md`'* ]]
  [[ "$output" == *'.agents/skills'* ]]
  [[ "$output" == *'parallel-session-protocol.md'* ]]
  [[ "$output" == *'do not assume Codex runs'* ]]
}
