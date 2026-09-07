#!/usr/bin/env bats
# BATS tests for scripts/spec-id-duplicates-check.sh (SE-044 Slice 1).
# Ref: SE-044, Rule #8
SCRIPT="scripts/spec-id-duplicates-check.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}
teardown() { cd /; }

@test "exists + executable" { [[ -x "$SCRIPT" ]]; }
@test "uses set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "passes bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "references SE-044" { run grep -c 'SE-044' "$SCRIPT"; [[ "$output" -ge 1 ]]; }

@test "--help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged"* ]]
}

@test "rejects unknown arg" { run bash "$SCRIPT" --bogus; [ "$status" -eq 2 ]; }

@test "runs against real docs/propuestas" {
  run bash "$SCRIPT"
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [[ "$output" == *"VERDICT"* ]]
}

@test "output reports Specs scanned" {
  run bash "$SCRIPT"
  [[ "$output" == *"Specs scanned:"* ]]
}

@test "output reports Duplicates count" {
  run bash "$SCRIPT"
  [[ "$output" == *"Duplicates:"* ]]
}

@test "--json produces valid JSON" {
  run bash -c 'bash scripts/spec-id-duplicates-check.sh --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k in [\"verdict\",\"total_specs\",\"duplicates_count\",\"mode\",\"duplicates\"]:
    assert k in d
assert isinstance(d[\"duplicates\"], list)
print(\"ok\")
"'
  [[ "$output" == *"ok"* ]]
}

@test "--json verdict is PASS or FAIL" {
  run bash "$SCRIPT" --json
  [[ "$output" == *'"verdict":"PASS"'* || "$output" == *'"verdict":"FAIL"'* ]]
}

@test "total_specs > 0" {
  run bash -c 'bash scripts/spec-id-duplicates-check.sh --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d[\"total_specs\"] > 0
print(\"ok\")
"'
  [[ "$output" == *"ok"* ]]
}

@test "--staged mode runs with empty diff" {
  run bash "$SCRIPT" --staged
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── Edge cases ────────────────────────────────────────────

@test "edge: empty docs/propuestas handled gracefully" {
  local root="$BATS_TEST_TMPDIR/fake-empty"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [[ "$status" -eq 0 ]]
}

@test "edge: nonexistent docs/propuestas exits 2" {
  local root="$BATS_TEST_TMPDIR/no-propuestas"
  mkdir -p "$root/scripts"
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 2 ]
}

@test "edge: zero specs (no md files) = PASS" {
  local root="$BATS_TEST_TMPDIR/zero-specs"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ]
}

@test "edge: single spec = no duplicate" {
  local root="$BATS_TEST_TMPDIR/single-spec"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cat > "$root/docs/propuestas/SPEC-999-test.md" <<EOF
---
id: SPEC-999
---
# Test
EOF
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ]
}

@test "edge: synthetic duplicate detected" {
  local root="$BATS_TEST_TMPDIR/dup-spec"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cat > "$root/docs/propuestas/SPEC-A.md" <<EOF
---
id: SPEC-777
---
EOF
  cat > "$root/docs/propuestas/SPEC-B.md" <<EOF
---
id: SPEC-777
---
EOF
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 1 ]
  [[ "$output" == *"SPEC-777"* ]]
}

@test "docs/specs: duplicate numeric SE ID in filenames is detected" {
  local root="$BATS_TEST_TMPDIR/dup-modern-spec"
  mkdir -p "$root/docs/propuestas" "$root/docs/specs" "$root/scripts"
  touch "$root/docs/specs/SE-777-alpha.spec.md"
  touch "$root/docs/specs/SE-777-beta.spec.md"
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 1 ]
  [[ "$output" == *"SE-777"* ]]
}

# ── Negative ────────────────────────────────────────────

@test "negative: spec without id field ignored" {
  local root="$BATS_TEST_TMPDIR/no-id"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cat > "$root/docs/propuestas/orphan.md" <<EOF
# No frontmatter
EOF
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ]
}

@test "negative: malformed frontmatter handled" {
  local root="$BATS_TEST_TMPDIR/bad-yaml"
  mkdir -p "$root/docs/propuestas" "$root/scripts"
  cat > "$root/docs/propuestas/bad.md" <<EOF
---
id: SPEC-X
unclosed
EOF
  cp "$SCRIPT" "$root/scripts/"
  cd "$root"
  run bash scripts/spec-id-duplicates-check.sh
  cd "$BATS_TEST_DIRNAME/.."
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── Coverage ────────────────────────────────────────────

@test "coverage: extract_id function exists" { run grep -c 'extract_id' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "coverage: ID_FILES associative array" { run grep -c 'ID_FILES' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "coverage: DUPES collection" { run grep -c 'DUPES' "$SCRIPT"; [[ "$output" -ge 1 ]]; }

# ── Isolation ────────────────────────────────────────────

@test "isolation: does not modify docs/propuestas" {
  local h_before
  h_before=$(find docs/propuestas -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash "$SCRIPT" >/dev/null 2>&1 || true
  local h_after
  h_after=$(find docs/propuestas -name "*.md" -exec md5sum {} + 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$h_before" == "$h_after" ]]
}

@test "isolation: exit codes 0/1/2" {
  run bash "$SCRIPT"; [[ "$status" -eq 0 || "$status" -eq 1 ]]
  run bash "$SCRIPT" --bogus; [ "$status" -eq 2 ]
}
