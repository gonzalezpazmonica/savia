#!/usr/bin/env bats
# test-se-097-rules-index-regen.bats — SE-097: Rules INDEX.md regeneration
# Verifies the rules-index-generate.sh script and generated INDEX.md.
# Ref: SE-097. Since SE-501 (#1472) docs/rules/INDEX.md is a derived,
# gitignored file: the suite never reads the repo's copy. It copies the script
# into an isolated tree under $BATS_TEST_TMPDIR (bats creates and cleans it),
# with either the real rules or controlled fixtures, and checks what it writes.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/rules-index-generate.sh"

setup() {
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts" "$T/docs/rules/domain"
  cp "$SCRIPT" "$T/scripts/"
  GEN="$T/scripts/rules-index-generate.sh"
  D="$T/docs/rules/domain"
  INDEX="$T/docs/rules/INDEX.md"
}

real_rules() { cp "$REPO_ROOT"/docs/rules/domain/*.md "$D/"; }

@test "SE-097: rules-index-generate.sh script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "SE-097: INDEX.md has correct auto-generated header with date and rule count" {
  real_rules
  run bash "$GEN"
  [ "$status" -eq 0 ]
  # Header format: # Rules Index — auto-generated YYYY-MM-DD · N rules
  head -1 "$INDEX" | grep -qE "^# Rules Index — auto-generated $(TZ=UTC date +%Y-%m-%d) · [0-9]+ rules$"
  n=$(head -1 "$INDEX" | sed -E 's/.* · ([0-9]+) rules$/\1/')
  rows=$(grep -cE '^\| (L[0-9]|—) \| ' "$INDEX")
  [ "$n" -eq "$rows" ]
}

@test "SE-097: INDEX.md table has required columns (context_tier, file, title, spec)" {
  real_rules
  run bash "$GEN"
  [ "$status" -eq 0 ]
  grep -qE '^\| context_tier \| file \| title \| spec \|$' "$INDEX"
  row_count=$(grep -cE '^\| (L[0-9]|—) \| ' "$INDEX")
  [ "$row_count" -ge 50 ]
}

@test "SE-097: --check mode exits 0 when INDEX.md is up-to-date" {
  real_rules
  bash "$GEN"
  run bash "$GEN" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"up-to-date"* ]]
}

@test "SE-097: --check ignores only the date header line" {
  echo "# A" > "$D/a.md"
  bash "$GEN"
  sed -i '1s/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/2000-01-01/' "$INDEX"
  run bash "$GEN" --check
  [ "$status" -eq 0 ]
}

@test "SE-097: --check fails when a rule was added after generation" {
  echo "# A" > "$D/a.md"
  bash "$GEN"
  echo "# B" > "$D/b.md"
  run bash "$GEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"b.md"* ]]
}

@test "SE-097: --check fails when INDEX.md is missing and does not create it" {
  echo "# A" > "$D/a.md"
  run bash "$GEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist yet"* ]]
  [ ! -e "$INDEX" ]
}

@test "SE-097: --check fails when a row was edited by hand" {
  echo "# Alpha" > "$D/a.md"
  bash "$GEN"
  sed -i 's/| Alpha |/| Beta |/' "$INDEX"
  run bash "$GEN" --check
  [ "$status" -eq 1 ]
}

@test "SE-097: --check compares every line after the header, including line 2" {
  echo "# Alpha" > "$D/a.md"
  bash "$GEN"
  sed -i '2s/^$/hand edit/' "$INDEX"
  run bash "$GEN" --check
  [ "$status" -eq 1 ]
}

@test "SE-097: rows are ordered by context_tier (L1 first) then by file" {
  printf -- '---\ncontext_tier: L2\n---\n# Z2\n' > "$D/a.md"
  printf -- '---\ncontext_tier: L1\n---\n# Y1\n' > "$D/z.md"
  printf -- '---\ncontext_tier: L1\n---\n# X1\n' > "$D/m.md"
  echo "# No tier" > "$D/b.md"
  run bash "$GEN"
  [ "$status" -eq 0 ]
  run grep -oE '^\| [^|]+ \| \[[a-z]+\.md\]' "$INDEX"
  [ "${lines[0]}" = "| L1 | [m.md]" ]
  [ "${lines[1]}" = "| L1 | [z.md]" ]
  [ "${lines[2]}" = "| L2 | [a.md]" ]
  [ "${lines[3]}" = "| — | [b.md]" ]
}

@test "SE-097: archived rules and INDEX.md are excluded from the index" {
  printf -- '---\narchived: true\n---\n# Old\n' > "$D/old.md"
  echo "# stray" > "$D/INDEX.md"
  echo "# Live" > "$D/live.md"
  run bash "$GEN"
  [ "$status" -eq 0 ]
  head -1 "$INDEX" | grep -q ' · 1 rules$'
  grep -qF '[live.md](domain/live.md)' "$INDEX"
  run grep -cF 'old.md' "$INDEX"
  [ "$output" = "0" ]
}

@test "SE-097: title comes from frontmatter, then H1, and pipes are escaped" {
  printf -- '---\ntitle: "From | FM"\nspec_id: SE-1\n---\n# Ignored\n' > "$D/a.md"
  printf -- '# From H1\n' > "$D/b.md"
  printf -- 'no heading at all\n' > "$D/c.md"
  run bash "$GEN"
  [ "$status" -eq 0 ]
  grep -qF '| — | [a.md](domain/a.md) | From \| FM | SE-1 |' "$INDEX"
  grep -qF '| — | [b.md](domain/b.md) | From H1 | — |' "$INDEX"
  grep -qF '| — | [c.md](domain/c.md) | (no title) | — |' "$INDEX"
}

@test "SE-097: empty rules dir yields a zero-row index" {
  run bash "$GEN"
  [ "$status" -eq 0 ]
  head -1 "$INDEX" | grep -q ' · 0 rules$'
}

@test "SE-097: unknown arg is rejected with exit 2 and INDEX.md is not written" {
  # Antes: cualquier argumento distinto de --check (p. ej. «--chek») regeneraba
  # y sobrescribía INDEX.md con exit 0.
  echo "# A" > "$D/a.md"
  run bash "$GEN" --chek
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--chek'"* ]]
  [ ! -e "$INDEX" ]
}

@test "SE-097: undecodable rule fails closed and keeps the previous INDEX.md" {
  # Antes: la regla ilegible se omitía en silencio y el índice salía sin ella.
  echo "# A" > "$D/a.md"
  bash "$GEN"
  cp "$INDEX" "$BATS_TEST_TMPDIR/before.md"
  printf '# Bad \xff\xfe\n' > "$D/bad.md"
  run bash "$GEN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read rule bad.md"* ]]
  [[ "$output" == *"left untouched"* ]]
  cmp -s "$INDEX" "$BATS_TEST_TMPDIR/before.md"
  run bash "$GEN" --check
  [ "$status" -eq 2 ]
}

@test "SE-097: missing rules dir is an error with exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/bare/scripts"
  cp "$SCRIPT" "$BATS_TEST_TMPDIR/bare/scripts/"
  run bash "$BATS_TEST_TMPDIR/bare/scripts/rules-index-generate.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rules dir not found"* ]]
}
