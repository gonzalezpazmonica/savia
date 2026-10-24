#!/usr/bin/env bats
# Ref: SPEC-180 / docs/propuestas/SPEC-180-sentinel-safe-regen.md
# Tests for scripts/sentinel-regen.sh

setup() {
  cd "$BATS_TEST_DIRNAME/../.."
  SCRIPT="scripts/sentinel-regen.sh"
  TMPDIR_TEST="$(mktemp -d)"
  FILE="$TMPDIR_TEST/doc.md"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── AC1: inject preserves @user blocks ──────────────────────────────────────

@test "AC1: inject does not touch @user block (preserves human content)" {
  cat > "$FILE" <<'EOF'
# Title

<!-- @user:notes -->
HUMAN_OWNED_LINE_42
EOF
  echo "v1-content" | bash "$SCRIPT" inject "$FILE" main
  grep -q "HUMAN_OWNED_LINE_42" "$FILE"
  echo "v2-content" | bash "$SCRIPT" inject "$FILE" main
  grep -q "HUMAN_OWNED_LINE_42" "$FILE"
  grep -q "v2-content" "$FILE"
  ! grep -q "v1-content" "$FILE"
}

@test "AC1: inject creates block at EOF when section absent" {
  echo "# Header" > "$FILE"
  echo "fresh" | bash "$SCRIPT" inject "$FILE" newblock
  grep -q "<!-- @generated:newblock START" "$FILE"
  grep -q "fresh" "$FILE"
  grep -q "<!-- @generated:newblock END -->" "$FILE"
}

# ── AC2/AC3: hash drift detection ───────────────────────────────────────────

@test "AC2: verify-hash detects drift when generated block edited manually" {
  echo "original" | bash "$SCRIPT" inject "$FILE" sec
  # Tamper inside the block
  sed -i 's/original/tampered/' "$FILE"
  run bash "$SCRIPT" verify-hash "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT"* ]]
}

@test "AC3: verify-hash exits 0 on clean file" {
  echo "clean" | bash "$SCRIPT" inject "$FILE" a
  echo "more" | bash "$SCRIPT" inject "$FILE" b
  run bash "$SCRIPT" verify-hash "$FILE"
  [ "$status" -eq 0 ]
}

@test "AC3: verify-hash exits 1 on missing END marker (malformed)" {
  cat > "$FILE" <<'EOF'
<!-- @generated:broken START hash=00000000 -->
no end marker here
EOF
  run bash "$SCRIPT" verify-hash "$FILE"
  [ "$status" -ne 0 ]
}

# ── AC5: extract returns only generated content ─────────────────────────────

@test "AC5: extract returns inner content only" {
  printf 'line1\nline2\n' | bash "$SCRIPT" inject "$FILE" target
  run bash "$SCRIPT" extract "$FILE" target
  [ "$status" -eq 0 ]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line2"* ]]
  [[ "$output" != *"@generated"* ]]
}

# ── Idempotence ─────────────────────────────────────────────────────────────

@test "idempotent: same content twice produces byte-identical file" {
  echo "stable" | bash "$SCRIPT" inject "$FILE" iso
  H1=$(sha256sum "$FILE" | awk '{print $1}')
  echo "stable" | bash "$SCRIPT" inject "$FILE" iso
  H2=$(sha256sum "$FILE" | awk '{print $1}')
  [ "$H1" = "$H2" ]
}

# ── Negative cases ──────────────────────────────────────────────────────────

@test "neg: invalid section-id (uppercase) is rejected" {
  run bash -c "echo bad | bash $SCRIPT inject $FILE BadID"
  [ "$status" -ne 0 ]
}

@test "neg: nonexistent file fails fast" {
  run bash "$SCRIPT" extract "$TMPDIR_TEST/nope.md" foo
  [ "$status" -ne 0 ]
}

@test "neg: extract missing section-id errors" {
  echo "x" | bash "$SCRIPT" inject "$FILE" present
  run bash "$SCRIPT" extract "$FILE" absent
  [ "$status" -ne 0 ]
}

@test "neg: usage with no args exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: empty content injection works" {
  printf '' | bash "$SCRIPT" inject "$FILE" empty
  run bash "$SCRIPT" verify-hash "$FILE"
  [ "$status" -eq 0 ]
}

@test "edge: large content (200 lines) round-trips" {
  local big="$TMPDIR_TEST/big.txt"
  for i in $(seq 1 200); do echo "line-$i"; done > "$big"
  bash "$SCRIPT" inject "$FILE" big < "$big"
  run bash "$SCRIPT" extract "$FILE" big
  [ "$status" -eq 0 ]
  [[ "$output" == *"line-200"* ]]
  [[ "$output" == *"line-1"* ]]
}

@test "edge: two distinct sections in same file coexist" {
  echo "alpha" | bash "$SCRIPT" inject "$FILE" sec-a
  echo "beta"  | bash "$SCRIPT" inject "$FILE" sec-b
  run bash "$SCRIPT" verify-hash "$FILE"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" extract "$FILE" sec-a
  [[ "$output" == "alpha" ]]
  run bash "$SCRIPT" extract "$FILE" sec-b
  [[ "$output" == "beta" ]]
}

# ── Safety verification ─────────────────────────────────────────────────────

@test "safety: script uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

@test "safety: doc rule exists with marker contract" {
  [ -f "docs/rules/domain/sentinel-safe-regen.md" ]
  grep -q "@generated" "docs/rules/domain/sentinel-safe-regen.md"
  grep -q "@user" "docs/rules/domain/sentinel-safe-regen.md"
}

# ── Slice 3: AGENTS.md piloto integration ───────────────────────────────────

@test "piloto: agents-md-generate.sh with SENTINEL_MODE=1 preserves @user blocks" {
  cp AGENTS.md "$TMPDIR_TEST/AGENTS.md"
  SENTINEL_MODE=1 AGENTS_MD="$TMPDIR_TEST/AGENTS.md" bash scripts/agents-md-generate.sh --apply >/dev/null
  grep -q "@generated:agents-table START" "$TMPDIR_TEST/AGENTS.md"
  printf '\n<!-- @user:test-note -->\nMARKER_42\n' >> "$TMPDIR_TEST/AGENTS.md"
  SENTINEL_MODE=1 AGENTS_MD="$TMPDIR_TEST/AGENTS.md" bash scripts/agents-md-generate.sh --apply >/dev/null
  grep -q "MARKER_42" "$TMPDIR_TEST/AGENTS.md"
  run bash scripts/sentinel-regen.sh verify-hash "$TMPDIR_TEST/AGENTS.md"
  [ "$status" -eq 0 ]
}
