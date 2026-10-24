#!/usr/bin/env bats
# test-skill-manifest.bats — Tests for build-skill-manifest.sh (SPEC-140)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/build-skill-manifest.sh"

setup() {
  TMPDIR_SM=$(mktemp -d)
  export TMPDIR_SKILLS="$TMPDIR_SM/skills"
  export TMPDIR_OUTPUT="$TMPDIR_SM/skill-manifests.json"
  mkdir -p "$TMPDIR_SKILLS/test-skill-alpha"
  cat > "$TMPDIR_SKILLS/test-skill-alpha/SKILL.md" << 'EOF'
---
name: test-skill-alpha
description: "Test skill alpha para unit tests"
category: pm-operations
maturity: stable
---
Contenido del skill.
EOF
}

teardown() { rm -rf "$TMPDIR_SM"; }

@test "build-skill-manifest: script es bash valido" {
  bash -n "$SCRIPT"
}

@test "build-skill-manifest: uses set -uo pipefail" {
  head -10 "$SCRIPT" | grep -q "set -[euo]*o pipefail"
}

@test "build-skill-manifest: genera JSON valido" {
  run bash "$SCRIPT" "$TMPDIR_SKILLS" "$TMPDIR_OUTPUT"
  [ "$status" -eq 0 ]
  [[ -f "$TMPDIR_OUTPUT" ]]
  python3 -c "import json; json.load(open('$TMPDIR_OUTPUT')); print('JSON valido')"
}

@test "build-skill-manifest: incluye campos obligatorios" {
  bash "$SCRIPT" "$TMPDIR_SKILLS" "$TMPDIR_OUTPUT"
  run python3 -c "
import json
m = json.load(open('$TMPDIR_OUTPUT'))
s = m['skills'][0]
assert 'name' in s, 'falta name'
assert 'description' in s, 'falta description'
assert 'path' in s, 'falta path'
assert 'tokens_est' in s, 'falta tokens_est'
print('OK')
"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK" ]]
}

@test "build-skill-manifest: multiple skills all included" {
  mkdir -p "$TMPDIR_SKILLS/test-skill-beta"
  cat > "$TMPDIR_SKILLS/test-skill-beta/SKILL.md" << 'EOF'
---
name: test-skill-beta
description: "Beta skill"
---
Content.
EOF
  bash "$SCRIPT" "$TMPDIR_SKILLS" "$TMPDIR_OUTPUT"
  run python3 -c "
import json
m = json.load(open('$TMPDIR_OUTPUT'))
assert len(m['skills']) == 2, f'Expected 2 skills, got {len(m[\"skills\"])}'
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "error: missing directory argument fails" {
  [[ -n "${CI:-}" ]] && skip "needs local skill directory"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "error: nonexistent skills directory fails gracefully" {
  run bash "$SCRIPT" "$TMPDIR_SM/nonexistent" "$TMPDIR_OUTPUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILLS_DIR no encontrado"* ]]
  [ ! -e "$TMPDIR_OUTPUT" ]
}

@test "edge: empty skills directory produces empty manifest" {
  local empty_dir="$TMPDIR_SM/empty-skills"
  mkdir -p "$empty_dir"
  run bash "$SCRIPT" "$empty_dir" "$TMPDIR_OUTPUT"
  [ "$status" -eq 0 ]
  python3 -c "
import json
m = json.load(open('$TMPDIR_OUTPUT'))
assert len(m['skills']) == 0, f'Expected 0 skills, got {len(m[\"skills\"])}'
print('OK')
"
}
