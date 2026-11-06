#!/usr/bin/env bats
# tests/bats/test-se253-specs-archive.bats
# SE-253 Slice 6 -- Specs archive structure + changelog spec-field check
# ACs: 6.1 (archive dir), 6.2 (script), 6.3 (README gap doc), 6.4 (backfill >= 5), 6.5 (procedure section)
# Ref: docs/propuestas/SE-253 · S03p (SE-376): pruebas de comportamiento del checker.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ARCHIVE_DIR="$REPO_ROOT/docs/specs-archive"
ARCHIVE_2026="$REPO_ROOT/docs/specs-archive/2026"
README="$REPO_ROOT/docs/specs-archive/README.md"
SCRIPT="$REPO_ROOT/scripts/changelog-spec-field-check.sh"

# -- AC-6.1: docs/specs-archive/2026/ exists with at least 1 file ----------------
@test "SE-253 AC-6.1: docs/specs-archive/2026/ exists" {
  [[ -d "$ARCHIVE_2026" ]]
}

@test "SE-253 AC-6.1: docs/specs-archive/2026/ has at least 1 archived spec" {
  count=$(find "$ARCHIVE_2026" -maxdepth 1 -name "SE-*.md" | wc -l)
  [[ "$count" -ge 1 ]]
}

# -- AC-6.2: changelog-spec-field-check.sh exists and is executable ---------------
@test "SE-253 AC-6.2: changelog-spec-field-check.sh exists" {
  [[ -f "$SCRIPT" ]]
}

@test "SE-253 AC-6.2: changelog-spec-field-check.sh is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE-253 AC-6.2: changelog-spec-field-check.sh exits 0 in --warn mode" {
  run bash "$SCRIPT" --warn
  [ "$status" -eq 0 ]
}

@test "SE-253 AC-6.2: changelog-spec-field-check.sh exits 2 with unknown mode" {
  run bash "$SCRIPT" --invalid-mode
  [ "$status" -eq 2 ]
}

# -- AC-6.3: README documents gap (contains "SE-143" and "SE-252") ----------------
@test "SE-253 AC-6.3: specs-archive/README.md exists" {
  [[ -f "$README" ]]
}

@test "SE-253 AC-6.3: README.md mentions SE-143 (gap start)" {
  grep -q "SE-143" "$README"
}

@test "SE-253 AC-6.3: README.md mentions SE-252 (gap end)" {
  grep -q "SE-252" "$README"
}

# -- AC-6.4: At least 5 specs from last 30 days are in the archive ---------------
@test "SE-253 AC-6.4: at least 5 specs archived in 2026/" {
  count=$(find "$ARCHIVE_2026" -maxdepth 1 -name "SE-*.md" | wc -l)
  [[ "$count" -ge 5 ]]
}

@test "SE-253 AC-6.4: archived specs have closed_date frontmatter" {
  found=0
  while IFS= read -r -d '' f; do
    if grep -q "closed_date:" "$f" 2>/dev/null; then
      found=$((found + 1))
    fi
  done < <(find "$ARCHIVE_2026" -maxdepth 1 -name "SE-*.md" -print0)
  [[ "$found" -ge 5 ]]
}

@test "SE-253 AC-6.4: archived specs have closed_by_pr frontmatter" {
  found=0
  while IFS= read -r -d '' f; do
    if grep -q "closed_by_pr:" "$f" 2>/dev/null; then
      found=$((found + 1))
    fi
  done < <(find "$ARCHIVE_2026" -maxdepth 1 -name "SE-*.md" -print0)
  [[ "$found" -ge 5 ]]
}

# -- Extra AC-6.5: README has Procedimiento section -------------------------------
@test "SE-253 AC-6.5: README.md has Procedimiento section" {
  grep -qi "Procedimiento" "$README"
}

@test "SE-253 AC-6.5: README.md documents mv step in Procedimiento" {
  grep -q "mv docs/propuestas" "$README"
}

# -- S03p: comportamiento de changelog-spec-field-check.sh en un árbol aislado ---
# El script deduce el repo de su propia ruta: se copia a un repo sintético
# dentro de BATS_TEST_TMPDIR (bats lo limpia al terminar cada test).

setup() {
  FAKE="$(mktemp -d "$BATS_TEST_TMPDIR/csf.XXXXXX")"
  mkdir -p "$FAKE/scripts" "$FAKE/CHANGELOG.d" "$FAKE/docs/specs" \
    "$FAKE/docs/propuestas/sub" "$FAKE/docs/specs-archive/2026"
  cp "$SCRIPT" "$FAKE/scripts/changelog-spec-field-check.sh"
  CHK="$FAKE/scripts/changelog-spec-field-check.sh"
}

frag() { # frag NAME SPEC-LINE
  printf -- '---\n%s\nsection: Added\n---\n\n- algo\n' "$2" > "$FAKE/CHANGELOG.d/$1.md"
}

@test "checker: spec in docs/specs passes --check with OK" {
  touch "$FAKE/docs/specs/SE-900-x.spec.md"
  frag se900-a "spec: SE-900"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: all CHANGELOG.d entries"* ]]
}

@test "checker: spec found under docs/propuestas subdirectory" {
  touch "$FAKE/docs/propuestas/sub/SE-901-y.md"
  frag se901-a "spec: SE-901"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: spec found in docs/specs-archive" {
  touch "$FAKE/docs/specs-archive/2026/SE-902-z.md"
  frag se902-a "spec: SE-902"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: SPEC-prefixed file name counts as the spec" {
  touch "$FAKE/docs/propuestas/sub/SPEC-SE-903-w.md"
  frag se903-a "spec: SE-903"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: quoted spec value with CRLF is normalized" {
  touch "$FAKE/docs/specs/SE-904-q.md"
  printf -- '---\r\nspec: "SE-904"\r\n---\r\n' > "$FAKE/CHANGELOG.d/se904-a.md"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: missing spec file fails --check with ISSUE and count" {
  frag se905-a "spec: SE-905"
  run bash "$CHK" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ISSUE: SE-905 referenced in CHANGELOG.d/se905-a"* ]]
  [[ "$output" == *"Total issues: 1"* ]]
}

@test "checker: prefix of an existing id is rejected (boundary SE-25 vs SE-253)" {
  touch "$FAKE/docs/specs/SE-253-archive.md"
  frag se25-a "spec: SE-25"
  run bash "$CHK" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ISSUE: SE-25 referenced"* ]]
}

@test "checker: invalid spec id with path traversal is rejected" {
  touch "$FAKE/docs/specs/SE-906-x.md"
  frag se906-a "spec: ../../etc/SE-906"
  run bash "$CHK" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid spec id"* ]]
}

@test "checker: SE-named fragment without spec field is an ISSUE (hyphen and case)" {
  printf -- '---\nsection: Added\n---\n' > "$FAKE/CHANGELOG.d/SE-907-x.md"
  printf -- '---\nsection: Added\n---\n' > "$FAKE/CHANGELOG.d/agent-se908.md"
  run bash "$CHK" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-907-x missing 'spec:'"* ]]
  [[ "$output" == *"agent-se908 missing 'spec:'"* ]]
  [[ "$output" == *"Total issues: 2"* ]]
}

@test "checker: non-SE fragment without spec field is not flagged (release-2 boundary)" {
  printf -- '---\nsection: Added\n---\n' > "$FAKE/CHANGELOG.d/release-2.md"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" != *"ISSUE"* ]]
}

@test "checker: --warn reports issues but exits 0" {
  frag se909-a "spec: SE-909"
  run bash "$CHK" --warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: 1 issue(s) found"* ]]
}

@test "checker: empty CHANGELOG.d passes with OK" {
  run bash "$CHK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: nonexistent CHANGELOG.d exits 0 silently" {
  rmdir "$FAKE/CHANGELOG.d"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "checker: bare ID.spec.md and ID.md file names count as the spec" {
  touch "$FAKE/docs/specs/SCL-910.spec.md" "$FAKE/docs/specs/SCL-911.md"
  frag scl910-a "spec: SCL-910"
  frag scl911-a "spec: SCL-911"
  run bash "$CHK" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK:"* ]]
}

@test "checker: invalid mode prints usage for both modes on stderr" {
  run bash -c "bash '$CHK' --nope 2>&1 >/dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--check  exit 1 if issues found"* ]]
  [[ "$output" == *"--warn   exit 0 but print issues"* ]]
}

@test "checker: repo without any spec directory flags referenced spec as missing" {
  rmdir "$FAKE/docs/specs" "$FAKE/docs/propuestas/sub" "$FAKE/docs/propuestas" \
    "$FAKE/docs/specs-archive/2026" "$FAKE/docs/specs-archive"
  frag se912-a "spec: SE-912"
  run bash "$CHK" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ISSUE: SE-912 referenced"* ]]
}
