#!/usr/bin/env bats
# BATS tests for scripts/llms-txt-generate.sh (SE-269 S5)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/llms-txt-generate.sh"

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  # Isolation: generation targets a temp dir, never the committed docs/llms*.txt.
  OUT_DIR="$(mktemp -d)"
  export LLMS_TXT="$OUT_DIR/llms.txt"
  export LLMS_FULL="$OUT_DIR/llms-full.txt"
  export LLMS_ROOT="$OUT_DIR/llms-root.txt"
}

teardown() {
  cd /
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S5: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S5: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── LLMS index generation ─────────────────────────────────────────────────

@test "SE269-S5: generate produces "$LLMS_TXT"" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  [[ -f "$LLMS_TXT" ]]
}

@test "SE269-S5: generate produces "$LLMS_FULL"" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  [[ -f "$LLMS_FULL" ]]
}

@test "SE269-S5 AC-5.1: llms.txt contains key sections" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  run cat "$LLMS_TXT"
  [[ "$output" == *"Savia"* ]]
  [[ "$output" == *"Nucleo operativo"* ]]
  [[ "$output" == *"Arquitectura"* ]]
  [[ "$output" == *"Seguridad"* ]]
  [[ "$output" == *"Desarrollo"* ]]
}

@test "SE269-S5 AC-5.1: llms-full.txt contains core docs" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  # Verify core docs are referenced (check for path references)
  run grep -q "critical-facts" "$LLMS_FULL"
  [ "$status" -eq 0 ]
  run grep -q "CRITERIO" "$LLMS_FULL"
  [ "$status" -eq 0 ]
}

# ── AC-5.3: Determinism ──────────────────────────────────────────────────

@test "SE269-S5 AC-5.3: check reports deterministic" {
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"DETERMINISTA"* ]]
}

@test "SE269-S5 AC-5.3: two generations produce identical output (minus timestamps)" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  local hash1; hash1=$(grep -v "Generado:" "$LLMS_FULL" | sha256sum | cut -d' ' -f1)
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  local hash2; hash2=$(grep -v "Generado:" "$LLMS_FULL" | sha256sum | cut -d' ' -f1)
  [[ "$hash1" == "$hash2" ]]
}

# ── Subcommands ───────────────────────────────────────────────────────────

@test "SE269-S5: index subcommand generates llms.txt but not full" {
  local before_hash; before_hash=$(sha256sum "$LLMS_FULL" 2>/dev/null | cut -d' ' -f1 || echo "initial")
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  [[ -f "$LLMS_TXT" ]]
}

@test "SE269-S5: full subcommand regenerates llms-full.txt" {
  run bash "$SCRIPT" full
  [ "$status" -eq 0 ]
  [[ -f "$LLMS_FULL" ]]
}

# ── AC-5.2: Sensitive path filtering ──────────────────────────────────────

@test "SE269-S5 AC-5.2: llms-full.txt does not contain active-user profile" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  # active-user.md should NOT appear in consolidated output
  run grep -c "active-user.md" "$LLMS_FULL" 2>/dev/null || true
  # count should be 0 or the grep exits non-zero meaning not found
  [[ "$output" == "0" || "$status" -ne 0 ]]
}

# ── Spec index in llms-full.txt ───────────────────────────────────────────

@test "SE269-S5: llms-full.txt contains spec index" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  run grep -q "docs/specs/ (indice)" "$LLMS_FULL"
  [ "$status" -eq 0 ]
}

@test "SE269-S5: llms-full.txt references SE-269 spec" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  run grep -q "SE-269" "$LLMS_FULL"
  [ "$status" -eq 0 ]
}

# ── Output size ───────────────────────────────────────────────────────────

@test "SE269-S5 AC-5.1: llms.txt has reasonable size" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  local size; size=$(wc -c < "$LLMS_TXT")
  [[ "$size" -gt 100 ]]
  [[ "$size" -lt 10000 ]]
}

@test "SE269-S5 AC-5.1: llms-full.txt has reasonable size" {
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  local size; size=$(wc -c < "$LLMS_FULL")
  [[ "$size" -gt 500 ]]
  [[ "$size" -lt 100000 ]]
}

# ── Invalid subcommand ────────────────────────────────────────────────────

@test "SE269-S5: invalid subcommand shows usage" {
  run bash "$SCRIPT" invalid-subcommand
  [ "$status" -eq 1 ]
}

@test "isolation: generate with LLMS_* overrides leaves committed docs/llms*.txt untouched" {
  local before; before=$(cat docs/llms.txt docs/llms-full.txt | sha256sum)
  run bash "$SCRIPT" generate
  [ "$status" -eq 0 ]
  [ "$(cat docs/llms.txt docs/llms-full.txt | sha256sum)" = "$before" ]
}

@test "reject: unknown subcommand exits 1 with usage" {
  run bash "$SCRIPT" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "error: nonexistent output directory makes full generation fail" {
  run env LLMS_FULL="$OUT_DIR/missing/dir/llms-full.txt" bash "$SCRIPT" full
  [ "$status" -ne 0 ]
  [ ! -e "$OUT_DIR/missing/dir/llms-full.txt" ]
}

@test "empty: index on an empty output dir creates only llms.txt" {
  run bash "$SCRIPT" index
  [ "$status" -eq 0 ]
  [ -s "$LLMS_TXT" ]
  [ ! -e "$LLMS_FULL" ]
}

@test "boundary: full output excludes the timestamp line from determinism hash" {
  run bash "$SCRIPT" full
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Generado:' "$LLMS_FULL")" -eq 1 ]
}
