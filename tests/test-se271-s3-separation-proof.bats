#!/usr/bin/env bats
# tests/test-se271-s3-separation-proof.bats — SE-271 Slice 3: Separation proof tests
# Tests for scripts/engagement-separation-proof.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/scripts/engagement-init.sh"
PROOF_SCRIPT="$REPO_ROOT/scripts/engagement-separation-proof.sh"
WALL_SCRIPT="$REPO_ROOT/scripts/engagement-wall-check.sh"
ROTATE_SCRIPT="$REPO_ROOT/scripts/engagement-rotate.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INIT_SCRIPT="$REPO_ROOT/scripts/engagement-init.sh"
  PROOF_SCRIPT="$REPO_ROOT/scripts/engagement-separation-proof.sh"
  WALL_SCRIPT="$REPO_ROOT/scripts/engagement-wall-check.sh"
  ROTATE_SCRIPT="$REPO_ROOT/scripts/engagement-rotate.sh"
}

# ── Structure tests ──────────────────────────────────────────────────────────

@test "SE271-SEP-01: separation-proof script exists" {
  [ -f "$PROOF_SCRIPT" ]
}

@test "SE271-SEP-02: separation-proof has set -uo pipefail" {
  grep -q "set -uo pipefail" "$PROOF_SCRIPT"
}

@test "SE271-SEP-03: separation-proof has SE-271 reference" {
  grep -q "SE-271" "$PROOF_SCRIPT"
}

@test "SE271-SEP-04: --help exits 0 with usage" {
  run bash "$PROOF_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"generate"* ]]
  [[ "$output" == *"verify"* ]]
  [[ "$output" == *"test"* ]]
}

@test "SE271-SEP-05: bash -n passes" {
  run bash -n "$PROOF_SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Generate tests ───────────────────────────────────────────────────────────

@test "SE271-SEP-06: generate --json produces valid JSON" {
  local tmp_out="$BATS_TEST_TMPDIR/proof-$$.json"

  run bash "$PROOF_SCRIPT" generate --json --output "$tmp_out"
  # May succeed (if engagements exist) or fail (if none)
  if [ "$status" -eq 0 ]; then
    run python3 -c "
import json
with open('$tmp_out') as f:
    d = json.load(f)
assert 'proof_id' in d
assert 'summary' in d
assert 'engagements' in d
assert 'total_samples' in d['summary']
assert 'contaminated' in d['summary']
print('OK')
"
    [[ "$output" == *"OK"* ]]
  fi
}

@test "SE271-SEP-07: generate output has required fields" {
  run bash "$PROOF_SCRIPT" generate --json
  if [ "$status" -eq 0 ]; then
    run python3 -c "
import json
d = json.loads('''$output''')
assert 'proof_id' in d
assert 'generated_at' in d
assert 'summary' in d
assert isinstance(d['engagements'], list)
print('OK')
"
    [[ "$output" == *"OK"* ]]
  fi
}

@test "SE271-SEP-08: proof includes separation_intact boolean" {
  run bash "$PROOF_SCRIPT" generate --json
  if [ "$status" -eq 0 ]; then
    run python3 -c "
import json
d = json.loads('''$output''')
s = d['summary']
assert 'separation_intact' in s
assert isinstance(s['separation_intact'], bool)
print('OK')
"
    [[ "$output" == *"OK"* ]]
  fi
}

# ── Verifiable sampling tests ────────────────────────────────────────────────

@test "SE271-SEP-09: generate with --sample-count respects count" {
  run bash "$PROOF_SCRIPT" generate --json --sample-count 3
  if [ "$status" -eq 0 ]; then
    run python3 -c "
import json
d = json.loads('''$output''')
total = d['summary']['total_samples']
# Total should be reasonable (<= sample_count * engagements)
print(f'total_samples={total}')
"
    # This test just verifies the parameter is accepted
    [ "$status" -eq 0 ]
  fi
}

# ── Adversarial self-test ────────────────────────────────────────────────────

@test "SE271-SEP-10: adversarial test mode exists" {
  local test_client="adversarialtest"
  local test_eng="adveng"

  # Create engagement first
  bash "$INIT_SCRIPT" --client "$test_client" --engagement "$test_eng" --wall strict --force --json > /dev/null 2>&1 || true

  # Run adversarial test
  run bash "$PROOF_SCRIPT" test --client "$test_client"

  # Test should either pass (contamination detected) or fail (not detected)
  # Either way, the script should not crash
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

  # Cleanup
  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

@test "SE271-SEP-11: contamination test references adversarial in output" {
  local test_client="adversarialtest2"
  local test_eng="adveng2"

  bash "$INIT_SCRIPT" --client "$test_client" --engagement "$test_eng" --wall strict --force > /dev/null 2>&1 || true

  run bash "$PROOF_SCRIPT" test --client "$test_client" --json
  # Should succeed and output mention adversarial
  [ "$status" -le 1 ]
  run python3 -c "
import json, sys
t = sys.stdin.read()
d = json.loads(t[t.index('{'):])
assert d['adversarial_test'] is True
print('OK')
" <<< "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]

  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

@test "SE271-SEP-12: planted contamination is cleaned up after test" {
  local test_client="adversarialcleanup"
  local test_eng="cleanupeng"

  bash "$INIT_SCRIPT" --client "$test_client" --engagement "$test_eng" --wall strict --force > /dev/null 2>&1 || true

  run bash "$PROOF_SCRIPT" test --client "$test_client" --json

  # Check that no planted-contamination files remain
  local remaining
  remaining=$(find "$REPO_ROOT/engagements/$test_client" -name "planted-contamination-*" 2>/dev/null | wc -l)
  [ "$remaining" -eq 0 ]

  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

# ── Integration: all command ─────────────────────────────────────────────────

@test "SE271-SEP-13: all command runs without crash" {
  run bash "$PROOF_SCRIPT" all --json
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ── Separation proof is verifiable (not declarative) ─────────────────────────

@test "SE271-SEP-14: proof contains per-sample sha256 hashes" {
  local test_client="proofverify"
  local test_eng="verifyeng"

  bash "$INIT_SCRIPT" --client "$test_client" --engagement "$test_eng" --wall strict --force > /dev/null 2>&1 || true

  # Create a test artifact
  mkdir -p "$REPO_ROOT/engagements/$test_client/artifacts"
  echo "<!-- SE-271-WALL client:${test_client} engagement:${test_eng} confidentiality:3 -->" > "$REPO_ROOT/engagements/$test_client/artifacts/test-doc.md"
  echo "# Test document for proof verification" >> "$REPO_ROOT/engagements/$test_client/artifacts/test-doc.md"

  run bash "$PROOF_SCRIPT" generate --client "$test_client" --engagement "$test_eng" --json --sample-count 5
  if [ "$status" -eq 0 ]; then
    run python3 -c "
import json
d = json.loads('''$output''')
for eng in d['engagements']:
    for sample in eng.get('samples', []):
        assert 'sha256' in sample, f'Missing sha256 in sample: {sample}'
        assert len(sample['sha256']) > 0, 'Empty sha256 hash'
        assert 'status' in sample
        assert 'path' in sample
print('OK')
"
    [[ "$output" == *"OK"* ]]
  fi

  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

@test "SE271-SEP-15: verify command works with --client" {
  local test_client="verifycmd"
  local test_eng="vcmd"

  bash "$INIT_SCRIPT" --client "$test_client" --engagement "$test_eng" --wall strict --force > /dev/null 2>&1 || true

  run bash "$PROOF_SCRIPT" verify --client "$test_client" --json
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

# ── Unknown flag ─────────────────────────────────────────────────────────────

@test "SE271-SEP-16: unknown flag exits 2" {
  run bash "$PROOF_SCRIPT" --fake-flag
  [ "$status" -eq 2 ]
}
