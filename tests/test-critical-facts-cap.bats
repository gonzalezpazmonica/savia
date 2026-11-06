#!/usr/bin/env bats
# Ref: SPEC-185 / docs/propuestas/SPEC-185-critical-facts-150tok-cap.md
# Verifies docs/critical-facts.md respects the 150-token cap, has the
# canonical fields (SE-487: no personal data), integrates into CLAUDE.md, and is regenerable.

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

# SE-487: la persona activa no se escribe en el fichero versionado; el campo
# solo remite al arranque (perfil local gitignored).
@test "AC5: contains Persona activa field pointing to the local profile" {
  grep -q "Persona activa" "$FACTS"
  grep -q "/profile-setup" "$FACTS"
}

@test "SE-487: versioned facts carry no profile slug nor activation date" {
  run grep -E 'profile slug|perfil `|activated [0-9]{4}-' "$FACTS"
  [ "$status" -eq 1 ]
}

@test "SE-487: generator --check passes on any machine (no local inputs)" {
  run bash "$GENERATOR" --check
  [ "$status" -eq 0 ]
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

# ── S03r: tope y marcadores por comportamiento ───────────────────────────────

facts_with_words() {  # facts_with_words N FILE — bloque con N palabras entre marcadores
  { echo "# T"; echo "<!-- CRITICAL_FACTS_START -->"; for i in $(seq 1 "$1"); do echo -n "w$i "; done; echo; echo "<!-- CRITICAL_FACTS_END -->"; } > "$2"
}

@test "boundary: 115 words (~150 tokens, rounded up) passes, 116 (~151) fails" {
  facts_with_words 115 "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"~150 tokens (115 words), cap=150"* ]]
  facts_with_words 116 "$TMPDIR_TEST/b.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/b.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"~151 tokens (116 words), cap=150"* ]]
}

@test "edge: CRITICAL_FACTS_TOKEN_CAP overrides the cap, zero cap fails any word" {
  facts_with_words 10 "$TMPDIR_TEST/a.md"
  CRITICAL_FACTS_TOKEN_CAP=13 run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 0 ]
  CRITICAL_FACTS_TOKEN_CAP=12 run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
  CRITICAL_FACTS_TOKEN_CAP=0 run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
}

@test "fail-closed: non-numeric cap is an error, not a pass" {
  # Antes: «150x» rompía la comparación aritmética y el validador decía OK.
  facts_with_words 300 "$TMPDIR_TEST/a.md"
  CRITICAL_FACTS_TOKEN_CAP=150x run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a non-negative integer"* ]]
}

@test "fail-closed: marker names mentioned in prose are not markers" {
  # Antes: grep por subcadena aceptaba la mención; awk extraía 0 palabras → OK.
  { echo "Ver CRITICAL_FACTS_START y CRITICAL_FACTS_END."; for i in $(seq 1 300); do echo -n "w$i "; done; echo; } > "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"markers"*"not found"* ]]
}

@test "fail-closed: END marker before START is an error" {
  { echo "<!-- CRITICAL_FACTS_END -->"; for i in $(seq 1 300); do echo -n "w$i "; done; echo; echo "<!-- CRITICAL_FACTS_START -->"; } > "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"START before END"* ]]
}

@test "fail-closed: duplicated START marker is an error" {
  facts_with_words 10 "$TMPDIR_TEST/a.md"
  echo "<!-- CRITICAL_FACTS_START -->" >> "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
}

@test "edge: words outside the markers do not count" {
  facts_with_words 10 "$TMPDIR_TEST/a.md"
  for i in $(seq 1 300); do echo -n "out$i "; done >> "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(10 words)"* ]]
}

@test "fail-closed: START and END markers on the same line are an error" {
  { echo "<!-- CRITICAL_FACTS_START --> x <!-- CRITICAL_FACTS_END -->"; for i in $(seq 1 300); do echo -n "w$i "; done; echo; } > "$TMPDIR_TEST/a.md"
  run bash "$VALIDATOR" "$TMPDIR_TEST/a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"START before END"* ]]
}
