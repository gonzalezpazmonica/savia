#!/usr/bin/env bats
# test-se-096-orphan-rules-archive.bats — SE-096: Archive 9 orphan rules
# Verifies that the 9 rules listed in SE-096 are marked archived and excluded
# from the orphan detector.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
RULES_DIR="$REPO_ROOT/docs/rules/domain"
ARCHIVE_DIR="$REPO_ROOT/docs/archive/rules"

# All 9 rules that SE-096 archives
SE096_ORPHANS=(
  "hook-event-equivalence.md"
  "image-relevance-filter.md"
  "portfolio-as-graph.en.md"
  "receipts-protocol.en.md"
  "savia-memory-architecture.md"
  "session-state-location.md"
  "slm-consolidation-pattern.md"
  "slm-training-pipeline.en.md"
  "vault-frontmatter.md"
)

@test "SE-096: all 9 orphan rules have archived:true in frontmatter" {
  for fname in "${SE096_ORPHANS[@]}"; do
    rule="$RULES_DIR/$fname"
    [ -f "$rule" ] || fail "Rule file missing: $rule"
    grep -qE '^archived: true' "$rule" || fail "Missing 'archived: true' in: $fname"
  done
}

@test "SE-096: all 9 orphan rules are copied to docs/archive/rules/" {
  [ -d "$ARCHIVE_DIR" ] || fail "Archive directory missing: $ARCHIVE_DIR"
  for fname in "${SE096_ORPHANS[@]}"; do
    # At least one archive copy matching the filename must exist
    count=$(ls "$ARCHIVE_DIR" 2>/dev/null | grep "$fname" | wc -l)
    [ "$count" -ge 1 ] || fail "No archive copy found for: $fname"
  done
}

@test "SE-096: rule-orphan-detector.sh excludes archived rules from orphan list" {
  run bash "$REPO_ROOT/scripts/rule-orphan-detector.sh" 2>/dev/null
  # Each of the 9 archived rules must NOT appear in detector output
  for fname in "${SE096_ORPHANS[@]}"; do
    echo "$output" | grep -qF "$fname" && fail "Archived rule still listed as orphan: $fname"
  done
  # Script should not report these 9 in its orphan list
  :
}

# ── Comportamiento del detector sobre un árbol aislado (S03r) ────────────────
# Ref: SE-048 (detector), SE-096 (archivado). El script calcula PROJECT_ROOT
# desde su propio directorio, así que se copia a un árbol temporal con reglas
# y referencias controladas: cada test sabe exactamente qué debe salir.
# El árbol vive en $BATS_TEST_TMPDIR, que bats crea y limpia en cada test.

setup() {
  TMP="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TMP/scripts" "$TMP/docs/rules/domain" "$TMP/tests"
  cp "$REPO_ROOT/scripts/rule-orphan-detector.sh" "$TMP/scripts/"
  DET="$TMP/scripts/rule-orphan-detector.sh"
  D="$TMP/docs/rules/domain"
}

@test "detector: script declares set -uo pipefail" {
  grep -q '^set -uo pipefail' "$REPO_ROOT/scripts/rule-orphan-detector.sh"
}

@test "detector: referenced rule passes with exit 0 and VERDICT PASS" {
  echo "# Used" > "$D/used.md"
  echo "see docs/rules/domain/used.md" > "$TMP/tests/ref.sh"
  run bash "$DET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total rules:    1"* ]]
  [[ "$output" == *"VERDICT: PASS"* ]]
}

@test "detector: rule with zero references fails with exit 1 and is listed" {
  echo "# Lonely" > "$D/lonely.md"
  run bash "$DET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: FAIL"* ]]
  [[ "$output" == *"0 refs  docs/rules/domain/lonely.md"* ]]
}

@test "detector: self-reference inside the rule file does not count" {
  echo "This rule is lonely.md and cites lonely.md" > "$D/lonely.md"
  run bash "$DET" --json
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["orphans"]==1 and d["orphan_list"][0]=={"refs":0,"rule":"docs/rules/domain/lonely.md"}, d' "$output"
}

@test "detector: rule mentioned only as suffix of a longer name is still an orphan" {
  # Antes: grep por subcadena contaba «data-privacy.md» como referencia a «privacy.md».
  echo "# Privacy" > "$D/privacy.md"
  echo "# Data privacy" > "$D/data-privacy.md"
  echo "see data-privacy.md" > "$TMP/tests/a.sh"
  run bash "$DET" --json
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert [o["rule"] for o in d["orphan_list"]]==["docs/rules/domain/privacy.md"], d' "$output"
}

@test "detector: dot in rule name is literal, not a regex wildcard" {
  # Antes: «a.md» como regex casaba con «a-md» y la regla salía referenciada.
  echo "# A" > "$D/a.md"
  echo "token a-md and xamd" > "$TMP/tests/a.sh"
  run bash "$DET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0 refs  docs/rules/domain/a.md"* ]]
}

@test "detector: longer extension like rule.mdx is not a reference to rule.md" {
  echo "# R" > "$D/rule.md"
  echo "see rule.mdx" > "$TMP/tests/a.md"
  run bash "$DET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0 refs  docs/rules/domain/rule.md"* ]]
}

@test "detector: path-qualified and punctuated references count" {
  echo "# R" > "$D/r1.md"
  echo "# R" > "$D/r2.md"
  echo "[x](domain/r1.md)" > "$TMP/tests/a.md"
  echo "end of sentence r2.md." > "$TMP/tests/b.md"
  run bash "$DET" --json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["verdict"]=="PASS" and d["total_rules"]==2 and d["orphans"]==0, d' "$output"
}

@test "detector: references only count in scanned extensions" {
  echo "# R" > "$D/r.md"
  echo "r.md" > "$TMP/tests/notes.txt"
  run bash "$DET"
  [ "$status" -eq 1 ]
  echo "r.md" > "$TMP/tests/notes.yml"
  run bash "$DET"
  [ "$status" -eq 0 ]
}

@test "detector: archived rule is skipped and INDEX.md only with --include-index" {
  printf -- '---\narchived: true\n---\n# Old\n' > "$D/old.md"
  echo "# Index" > "$D/INDEX.md"
  echo "# Live" > "$D/live.md"
  echo "live.md" > "$TMP/tests/a.md"
  run bash "$DET" --json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["total_rules"]==1, d' "$output"
  # Con --include-index cuenta INDEX.md (el propio detector copiado en scripts/
  # lo menciona, así que no queda huérfano); la regla archivada sigue fuera.
  run bash "$DET" --json --include-index
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["total_rules"]==2, d' "$output"
}

@test "detector: --min-refs boundary counts refs below N, not at N" {
  echo "# R" > "$D/r.md"
  echo "r.md" > "$TMP/tests/a.md"
  echo "r.md" > "$TMP/tests/b.md"
  run bash "$DET" --min-refs 2
  [ "$status" -eq 0 ]
  run bash "$DET" --min-refs 3 --json
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["min_refs"]==3 and d["orphan_list"]==[{"refs":2,"rule":"docs/rules/domain/r.md"}], d' "$output"
}

@test "detector: --min-refs zero never reports orphans" {
  echo "# R" > "$D/r.md"
  run bash "$DET" --min-refs 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"Orphans:        0 (refs < 0)"* ]]
}

@test "detector: invalid --min-refs is a usage error (exit 2)" {
  echo "# R" > "$D/r.md"
  run bash "$DET" --min-refs abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-negative integer"* ]]
}

@test "detector: empty --min-refs value is a usage error (exit 2)" {
  echo "# R" > "$D/r.md"
  run bash "$DET" --min-refs ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-negative integer"* ]]
}

@test "detector: --min-refs with no arg is a usage error, not an orphan verdict" {
  # Antes: set -u abortaba con exit 1, el mismo código que «hay huérfanas».
  echo "# R" > "$D/r.md"
  echo "r.md" > "$TMP/tests/a.md"
  run bash "$DET" --min-refs
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs a value"* ]]
}

@test "detector: unknown option is rejected with exit 2" {
  echo "# R" > "$D/r.md"
  run bash "$DET" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--bogus'"* ]]
}

@test "detector: empty rules dir fails closed with exit 2, not PASS" {
  # Antes: 0 reglas daba «VERDICT: PASS» y exit 0.
  run bash "$DET"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no rules found"* ]]
}

@test "detector: missing rules dir is an error with exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/bare/scripts"
  cp "$DET" "$BATS_TEST_TMPDIR/bare/scripts/"
  run bash "$BATS_TEST_TMPDIR/bare/scripts/rule-orphan-detector.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"rules dir not found"* ]]
}

@test "detector: --help exits 0 and documents options" {
  run bash "$DET" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--min-refs N"* ]]
  [[ "$output" == *"--include-index"* ]]
}
