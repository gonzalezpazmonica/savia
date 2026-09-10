#!/usr/bin/env bats
# Ref: docs/propuestas/SE-315-scope-creep-gate.md (AC-S3.5..AC-S3.7)

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/spec-resolve.sh"

setup() {
  ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$ROOT/docs/propuestas" "$ROOT/docs/specs" \
    "$ROOT/projects/demo/specs"
}

@test "safety: resolver enables nounset and pipefail" {
  run grep -q '^set -uo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
}

make_spec() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' '---' 'status: IMPLEMENTED' '---' > "$path"
}

@test "AC-S3.5: resolves a unique spec from docs/specs" {
  make_spec "$ROOT/docs/specs/SE-999-example.spec.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-999
  [ "$status" -eq 0 ]
  [ "$output" = "$ROOT/docs/specs/SE-999-example.spec.md" ]
}

@test "AC-S3.5: resolves a unique spec from docs/propuestas" {
  make_spec "$ROOT/docs/propuestas/SE-998-example.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-998
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs/propuestas/SE-998-example.md" ]]
}

@test "AC-S3.5: resolves a unique project spec" {
  make_spec "$ROOT/projects/demo/specs/SE-997-example.spec.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-997
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/demo/specs/SE-997-example.spec.md" ]]
}

@test "AC-S3.6: duplicate ID fails closed as AMBIGUOUS" {
  make_spec "$ROOT/docs/specs/SE-999-first.spec.md"
  make_spec "$ROOT/docs/propuestas/SE-999-second.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-999
  [ "$status" -eq 3 ]
  [[ "$output" == AMBIGUOUS:* ]]
}

@test "AC-S3.7: exact in-repo reference disambiguates duplicate ID" {
  make_spec "$ROOT/docs/specs/SE-999-first.spec.md"
  make_spec "$ROOT/docs/propuestas/SE-999-second.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-999 \
    --reference docs/specs/SE-999-first.spec.md
  [ "$status" -eq 0 ]
  [ "$output" = "$ROOT/docs/specs/SE-999-first.spec.md" ]
}

@test "zero matches reports NOT_FOUND" {
  run bash "$SCRIPT" --root "$ROOT" --id SE-404
  [ "$status" -eq 1 ]
  [ "$output" = "NOT_FOUND: SE-404" ]
}

@test "boundary ID does not match a longer numeric ID" {
  make_spec "$ROOT/docs/specs/SE-9999-example.spec.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-999
  [ "$status" -eq 1 ]
  [ "$output" = "NOT_FOUND: SE-999" ]
}

@test "invalid absolute reference is rejected" {
  run bash "$SCRIPT" --root "$ROOT" --id SE-999 --reference /tmp/SE-999.md
  [ "$status" -eq 2 ]
  [[ "$output" == INVALID_REFERENCE:* ]]
}

@test "invalid mismatched reference ID is rejected" {
  make_spec "$ROOT/docs/specs/SE-998-example.spec.md"
  run bash "$SCRIPT" --root "$ROOT" --id SE-999 \
    --reference docs/specs/SE-998-example.spec.md
  [ "$status" -eq 2 ]
  [[ "$output" == REFERENCE_ID_MISMATCH:* ]]
}

@test "empty ID is a usage error" {
  run bash "$SCRIPT" --root "$ROOT" --id ""
  [ "$status" -eq 2 ]
  [[ "$output" == Usage:* ]]
}

@test "G17 and CI consume the shared resolver" {
  run grep -c 'spec-resolve.sh' scripts/pr-plan-gates.sh
  [ "$output" -ge 1 ]
  run grep -c 'scripts/spec-resolve.sh' .github/workflows/ci.yml
  [ "$output" -ge 1 ]
}
