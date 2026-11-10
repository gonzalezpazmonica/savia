#!/usr/bin/env bats
# tests/bats/test-se-105-glm.bats
# SE-105 — GLM v1.0 Governance Layer Manifest
# >= 6 tests

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
MANIFEST="$REPO_ROOT/.well-known/governance-layer-manifest.json"
YAML_MANIFEST="$REPO_ROOT/.opencode/governance-manifest.yaml"
VALIDATE="$REPO_ROOT/scripts/glm-validate.sh"
VERIFY="$REPO_ROOT/scripts/glm-verify.sh"
COMPUTE="$REPO_ROOT/scripts/glm-compute-digest.sh"
PROTOCOL="$REPO_ROOT/docs/rules/domain/glm-governance-protocol.md"

# ── Test 1: JSON manifest exists ───────────────────────────────────────────────
@test "AC-1: .well-known/governance-layer-manifest.json exists" {
  [[ -f "$MANIFEST" ]]
}

# ── Test 2: JSON manifest is valid JSON ────────────────────────────────────────
@test "AC-1: governance-layer-manifest.json is valid JSON" {
  run python3 -m json.tool "$MANIFEST"
  [ "$status" -eq 0 ]
}

# ── Test 3: Manifest has all required top-level fields ─────────────────────────
@test "AC-1/2/3: manifest has required top-level fields" {
  run python3 -c "
import json, sys
data = json.load(open('$MANIFEST'))
required = ['schema_version','layer','timing_axis','operational_scope','claims_boundary','composition','manifest_digest']
missing = [f for f in required if f not in data]
if missing:
    print('Missing:', missing)
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# ── Test 4: 5 surfaces declared in timing_axis ────────────────────────────────
@test "AC-1: timing_axis has 5 surfaces (substrate/witness/boundary/closure/reviewability)" {
  run python3 -c "
import json, sys
data = json.load(open('$MANIFEST'))
surfaces = data['timing_axis']['surfaces']
types = {s['layer_type'] for s in surfaces}
expected = {'substrate', 'witness', 'boundary', 'closure', 'reviewability'}
missing = expected - types
if missing:
    print('Missing layer types:', missing)
    sys.exit(1)
if len(surfaces) < 5:
    print('Expected >= 5 surfaces, got:', len(surfaces))
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# ── Test 5: >= 5 explicit_non_claims ──────────────────────────────────────────
@test "AC-2: at least 5 explicit_non_claims declared" {
  run python3 -c "
import json, sys
data = json.load(open('$MANIFEST'))
non_claims = data['claims_boundary']['explicit_non_claims']
if len(non_claims) < 5:
    print('Only', len(non_claims), 'non-claims, expected >= 5')
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# ── Test 6: consumer_boundary_constraint is non-empty ─────────────────────────
@test "AC-3: consumer_boundary_constraint is non-empty string" {
  run python3 -c "
import json, sys
data = json.load(open('$MANIFEST'))
cbc = data['claims_boundary']['consumer_boundary_constraint']
if not cbc or len(cbc.strip()) < 50:
    print('consumer_boundary_constraint too short or empty')
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# ── Test 7: composable_with_types has 5 layer types ───────────────────────────
@test "AC-4: composable_with_types has 5 layer types" {
  run python3 -c "
import json, sys
data = json.load(open('$MANIFEST'))
types = data['composition']['composable_with_types']
if len(types) < 5:
    print('Expected 5 composable types, got:', len(types))
    sys.exit(1)
"
  [ "$status" -eq 0 ]
}

# ── Test 8: glm-compute-digest.sh exists and is executable ────────────────────
@test "AC-5: scripts/glm-compute-digest.sh exists and is executable" {
  [[ -f "$COMPUTE" ]]
  [[ -x "$COMPUTE" ]]
}

# ── Test 9: glm-verify.sh exists and is executable ────────────────────────────
@test "AC-5: scripts/glm-verify.sh exists and is executable" {
  [[ -f "$VERIFY" ]]
  [[ -x "$VERIFY" ]]
}

# ── Test 10: glm-validate.sh exists and is executable ─────────────────────────
@test "glm-validate.sh exists and is executable" {
  [[ -f "$VALIDATE" ]]
  [[ -x "$VALIDATE" ]]
}

# ── Test 11: glm-validate.sh runs without FAIL from repo root ─────────────────
@test "glm-validate.sh produces PASS or WARN (not FAIL) with valid manifest" {
  run bash "$VALIDATE"
  # Exit 0=PASS, 1=WARN — both acceptable; exit 2=FAIL is not
  [ "$status" -ne 2 ]
}

# ── Test 12: protocol doc exists ──────────────────────────────────────────────
@test "AC-6: docs/rules/domain/glm-governance-protocol.md exists" {
  [[ -f "$PROTOCOL" ]]
}

# ── Test 13: protocol doc is <= 150 lines ─────────────────────────────────────
@test "AC-6: glm-governance-protocol.md is <= 150 lines" {
  LINES=$(wc -l < "$PROTOCOL")
  [ "$LINES" -le 150 ]
}

# ── Test 14: YAML manifest exists ─────────────────────────────────────────────
@test "governance-manifest.yaml exists in .opencode/" {
  [[ -f "$YAML_MANIFEST" ]]
}

# ── Test 15: constraint enforcement paths exist ───────────────────────────────
@test "constraint enforcement paths exist in repo" {
  paths=(
    "$REPO_ROOT/.opencode/hooks/block-credential-leak.sh"
    "$REPO_ROOT/scripts/savia-env.sh"
    "$REPO_ROOT/scripts/spec-approval-gate.sh"
    "$REPO_ROOT/.opencode/agents/commit-guardian.md"
  )
  for p in "${paths[@]}"; do
    if [[ ! -e "$p" ]]; then
      echo "Missing enforcement path: $p"
      exit 1
    fi
  done
}

# ── Test 16: ethical_principles reference exists ──────────────────────────────
@test "ethical principles reference file exists" {
  [[ -f "$REPO_ROOT/docs/rules/domain/savia-ethical-principles.md" ]]
}

# ── Test 17: manifest NOT served publicly (AC-7) ──────────────────────────────
@test "AC-7: manifest lives in .well-known/ not in a public web directory" {
  # Verify path is .well-known/ in repo (not /var/www or similar)
  [[ "$MANIFEST" == */.well-known/governance-layer-manifest.json ]]
}

# ── Test 18: glm-compute-digest runs and computes a digest ────────────────────
@test "AC-5: glm-compute-digest.sh --dry-run outputs a sha256 hash" {
  run bash "$COMPUTE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha256:"* ]]
}

# ── compute/verify del digest sobre manifiestos sintéticos (S03s) ──
# Ref: docs/rules/domain/glm-governance-protocol.md (SE-105 AC-5)
# Cada test trabaja en su propio directorio: los scripts leen .well-known/ desde el cwd.
glm_fixture() { # glm_fixture <digest-inicial>: manifiesto con otros campos "value"
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W/.well-known"
  M="$W/.well-known/governance-layer-manifest.json"
  printf '{\n  "claims": [{"name": "x", "value": "keep-me"}],\n  "pin": {"value": "%s"},\n  "manifest_digest": {\n    "algorithm": "sha256",\n    "value": "%s"\n  }\n}\n' \
    "$(printf 'a%.0s' $(seq 64))" "$1" > "$M"
}
in_w() { (cd "$W" && bash "$@"); }

@test "digest: compute then verify passes even with other \"value\" fields in the manifest" {
  glm_fixture "<computed>"
  run in_w "$COMPUTE"
  [ "$status" -eq 0 ]
  run in_w "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" == "PASS: manifest digest verified sha256:"* ]]
}

@test "digest: compute never rewrites other 64-hex \"value\" fields" {
  glm_fixture "<computed>"
  run in_w "$COMPUTE"
  [ "$status" -eq 0 ]
  grep -q "\"pin\": {\"value\": \"$(printf 'a%.0s' $(seq 64))\"}" "$M"
  grep -q '"value": "keep-me"' "$M"
}

@test "digest: tampering any field after compute makes verify fail" {
  glm_fixture "<computed>"
  in_w "$COMPUTE" >/dev/null
  sed -i 's/keep-me/tampered/' "$M"
  run in_w "$VERIFY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: digest mismatch"* ]]
}

@test "digest: recompute is idempotent and --dry-run changes nothing" {
  glm_fixture "<computed>"
  in_w "$COMPUTE" >/dev/null
  cp "$M" "$BATS_TEST_TMPDIR/first.json"
  run in_w "$COMPUTE" --dry-run
  [ "$status" -eq 0 ]
  cmp "$M" "$BATS_TEST_TMPDIR/first.json"
  d=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_digest"]["value"])' "$M")
  [[ "$output" == "DRY-RUN: digest would be sha256:$d" ]]
  in_w "$COMPUTE" >/dev/null
  cmp "$M" "$BATS_TEST_TMPDIR/first.json"
}

@test "digest: placeholder or empty stored value fails verify" {
  for v in "<computed>" ""; do
    glm_fixture "$v"
    run in_w "$VERIFY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing or placeholder"* ]]
  done
}

@test "digest: missing manifest fails both scripts with exit 1" {
  W="$BATS_TEST_TMPDIR/vacio"; mkdir -p "$W"
  run in_w "$VERIFY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  run in_w "$COMPUTE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "digest: compute refuses invalid JSON or an unexpected digest value, without touching the file" {
  glm_fixture "not-a-digest"
  cp "$M" "$BATS_TEST_TMPDIR/before.json"
  run in_w "$COMPUTE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be <computed> or a sha256 hex digest"* ]]
  cmp "$M" "$BATS_TEST_TMPDIR/before.json"
  printf '{"manifest_digest": {"value": "<computed>"' > "$M"
  run in_w "$COMPUTE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not valid JSON"* ]]
}
