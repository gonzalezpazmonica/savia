#!/usr/bin/env bats
# Ref: SPEC-185 / docs/propuestas/SPEC-185-critical-facts-150tok-cap.md
# Verifies docs/critical-facts.md respects the 150-token cap, has the
# canonical fields, integrates into CLAUDE.md, and is regenerable.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FACTS="docs/critical-facts.md"
  VALIDATOR="scripts/validate-critical-facts-cap.sh"
  GENERATOR="scripts/generate-critical-facts.sh"
  RULE="docs/rules/domain/critical-facts-anchor.md"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── AC1: file exists with markers ────────────────────────────────────────────

@test "AC1: docs/critical-facts.md exists" {
  [[ -f "$FACTS" ]]
}

@test "AC1: contains CRITICAL_FACTS_START marker" {
  grep -q "CRITICAL_FACTS_START" "$FACTS"
}

@test "AC1: contains CRITICAL_FACTS_END marker" {
  grep -q "CRITICAL_FACTS_END" "$FACTS"
}

# ── AC2: validator enforces 150-token cap ────────────────────────────────────

@test "AC2: validator passes on real critical-facts.md (under cap)" {
  run bash "$VALIDATOR" "$FACTS"
  [ "$status" -eq 0 ]
}

@test "AC2: validator rejects fixture exceeding cap (200-token file fails)" {
  local big="$TMPDIR_TEST/big.md"
  {
    echo "<!-- CRITICAL_FACTS_START -->"
    # Generate ~200 words to exceed 150 tokens
    for i in $(seq 1 220); do echo -n "word$i "; done
    echo ""
    echo "<!-- CRITICAL_FACTS_END -->"
  } > "$big"
  run bash "$VALIDATOR" "$big"
  [ "$status" -ne 0 ]
}

@test "AC2: validator passes fixture under cap (50-word file passes)" {
  local small="$TMPDIR_TEST/small.md"
  {
    echo "<!-- CRITICAL_FACTS_START -->"
    for i in $(seq 1 50); do echo -n "w$i "; done
    echo ""
    echo "<!-- CRITICAL_FACTS_END -->"
  } > "$small"
  run bash "$VALIDATOR" "$small"
  [ "$status" -eq 0 ]
}

@test "AC2: validator detects missing markers as error" {
  local nomarks="$TMPDIR_TEST/nomarks.md"
  echo "no markers here" > "$nomarks"
  run bash "$VALIDATOR" "$nomarks"
  [ "$status" -ne 0 ]
}

# ── AC3: CLAUDE.md integration ───────────────────────────────────────────────

@test "AC3: CLAUDE.md imports docs/critical-facts.md" {
  grep -q "@docs/critical-facts.md" CLAUDE.md
}

# ── AC4: generator is deterministic ──────────────────────────────────────────

@test "AC4: generator produces deterministic output (same input → same output)" {
  local copy="$TMPDIR_TEST/copy.md"
  cp "$FACTS" "$copy"
  bash "$GENERATOR" >/dev/null
  local first_hash
  first_hash=$(sha256sum "$FACTS" | awk '{print $1}')
  bash "$GENERATOR" >/dev/null
  local second_hash
  second_hash=$(sha256sum "$FACTS" | awk '{print $1}')
  [ "$first_hash" = "$second_hash" ]
  cp "$copy" "$FACTS"
}

# ── AC5: 6 canonical fields present ──────────────────────────────────────────

@test "AC5: contains Idioma activo field" {
  grep -q "Idioma activo" "$FACTS"
}

@test "AC5: contains Usuario activo field" {
  grep -q "Usuario activo" "$FACTS"
}

@test "AC5: contains Frontend field" {
  grep -q "Frontend" "$FACTS"
}

@test "AC5: contains Identidad field (SE-483, replaces Sprint)" {
  grep -q "^- \*\*Identidad\*\*: " "$FACTS"
  # SE-483: el hecho legado de sprint ya no está en el anchor
  run grep -c "^- \*\*Sprint\*\*" "$FACTS"
  [ "$output" = "0" ]
}

@test "AC5: contains Gates inmutables field" {
  grep -q "Gates inmutables" "$FACTS"
}

@test "AC5: contains Tono field" {
  grep -q "Tono" "$FACTS"
}

# ── AC7: validator suggests removals on failure ──────────────────────────────

@test "AC7: validator output contains removal suggestions when cap exceeded" {
  local big="$TMPDIR_TEST/big2.md"
  {
    echo "<!-- CRITICAL_FACTS_START -->"
    for i in $(seq 1 220); do echo -n "word$i "; done
    echo ""
    echo "<!-- CRITICAL_FACTS_END -->"
  } > "$big"
  run bash "$VALIDATOR" "$big"
  [[ "$output" == *"Suggested removals"* ]]
}

# ── Edge cases ───────────────────────────────────────────────────────────────

@test "edge: validator handles nonexistent file with error" {
  run bash "$VALIDATOR" "$TMPDIR_TEST/nonexistent.md"
  [ "$status" -ne 0 ]
}

@test "edge: validator with empty markers section returns 0 (zero tokens)" {
  local empty="$TMPDIR_TEST/empty.md"
  printf "<!-- CRITICAL_FACTS_START -->\n<!-- CRITICAL_FACTS_END -->\n" > "$empty"
  run bash "$VALIDATOR" "$empty"
  [ "$status" -eq 0 ]
}

@test "edge: rule doc exists" {
  [[ -f "$RULE" ]]
}

# ── Safety verification ──────────────────────────────────────────────────────

@test "safety: validator script uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$VALIDATOR"
}

@test "safety: generator script uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$GENERATOR"
}
