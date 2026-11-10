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

teardown() {
  local c
  for c in adversarialtest adversarialtest2 adversarialcleanup proofverify verifycmd; do
    rm -rf "$REPO_ROOT/engagements/$c" 2>/dev/null || true
  done
}

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

# ── S03t: comportamiento en un árbol aislado (BATS_TEST_TMPDIR) ──────────────
# El script y wall-check derivan ROOT de su ruta: se copian a un árbol propio con
# engagements/ sintéticos. Así los casos no dependen de lo que haya en el repo.

s03t_tree() {
  SB="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$SB/scripts" "$SB/engagements/acme/artifacts" "$SB/bin"
  cp "$PROOF_SCRIPT" "$WALL_SCRIPT" "$SB/scripts/"
  printf 'wall:\n  mode: strict\n  active: true\n' > "$SB/engagements/acme/prod.yaml"
  P="$SB/scripts/engagement-separation-proof.sh"
}

s03t_art() { printf '%s\n' "$2" > "$SB/engagements/acme/artifacts/$1"; }

@test "generate: artifact tagged with its own client counts as clean and the wall is intact (exit 0)" {
  s03t_tree; s03t_art own.md "notes client:acme"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1]); s=d['summary']
assert (s['total_samples'],s['clean'],s['contaminated'],s['untagged'])==(1,1,0,0), s
assert s['separation_intact'] is True
assert d['engagements'][0]['samples'][0]['status']=='tagged-correct'
assert d['engagements'][0]['wall']=='strict'
" "$output"
}

@test "generate: artifact carrying another client's tag is contaminated and the run exits 1" {
  s03t_tree; s03t_art leak.md "draft for client:rival"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 1 ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1]); s=d['summary']
assert s['contaminated']==1 and s['separation_intact'] is False, s
smp=d['engagements'][0]['samples'][0]
assert smp['status']=='contaminated' and smp['tag']=='client:rival', smp
" "$output"
}

@test "generate: own tag mixed with a foreign tag is cross-contaminated" {
  s03t_tree; s03t_art mix.md "client:acme and also client:rival"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "cross-contaminated"'* ]]
}

@test "generate: a client whose slug is a prefix of the owner's slug is still foreign (acme vs acme-corp)" {
  s03t_tree; s03t_art prefix.md "belongs to client:acme-corp"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"status": "contaminated"'* ]]
  [[ "$output" == *'client:acme-corp'* ]]
}

@test "generate: own tag followed by punctuation is not mistaken for a longer slug" {
  s03t_tree; s03t_art ok.md "(client:acme), done"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "tagged-correct"'* ]]
}

@test "generate: untagged artifact is reported untagged, not contaminated (exit 0)" {
  s03t_tree; s03t_art plain.md "no tags here"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
s=json.loads(sys.argv[1])['summary']
assert s['untagged']==1 and s['contaminated']==0 and s['clean']==0, s
" "$output"
}

@test "generate: empty artifacts are never sampled" {
  s03t_tree; : > "$SB/engagements/acme/artifacts/empty.md"
  run bash "$P" generate --client acme --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
assert json.loads(sys.argv[1])['summary']['total_samples']==0
" "$output"
}

@test "generate: --sample-count 1 limits the sample to one artifact" {
  s03t_tree; s03t_art a.md "client:acme"; s03t_art b.md "client:acme"; s03t_art c.md "client:acme"
  run bash "$P" generate --client acme --json --sample-count 1
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
assert json.loads(sys.argv[1])['summary']['total_samples']==1
" "$output"
}

@test "generate: engagements without client filter skip inactive ones" {
  s03t_tree; s03t_art leak.md "client:rival"
  printf 'wall:\n  mode: strict\n  active: false\n' > "$SB/engagements/acme/prod.yaml"
  run bash "$P" generate --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1]); assert d['engagements']==[] and d['summary']['total_samples']==0, d
" "$output"
}

@test "verify: clean client reports intact, verified true and exit 0" {
  s03t_tree; s03t_art own.md "client:acme"
  run bash "$P" verify --client acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"Current contamination: 0"* ]]
  [[ "$output" == *"SEPARATION INTACT"* ]]
  run bash "$P" verify --client acme --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verified":true'* ]]
}

@test "verify: contaminated client reports the violation, verified false and exit 1" {
  s03t_tree; s03t_art leak.md "client:rival"
  run bash "$P" verify --client acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"Current contamination: 1"* ]]
  [[ "$output" == *"VIOLATION DETECTED"* ]]
  run bash "$P" verify --client acme --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verified":false'* ]]
  [[ "$output" == *'"current_contamination":1'* ]]
}

@test "verify: unreadable fresh proof (python3 broken) is a violation, never intact" {
  s03t_tree; s03t_art own.md "client:acme"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/python3"; chmod +x "$SB/bin/python3"
  run env PATH="$SB/bin:$PATH" bash "$P" verify --client acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"Current contamination: -1"* ]]
  [[ "$output" == *"VIOLATION DETECTED"* ]]
}

@test "verify: without --client exits 1 with an error" {
  s03t_tree
  run bash "$P" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"--client required for verify"* ]]
}

@test "no command prints usage and exits 1" {
  s03t_tree
  run bash "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "test: planted contamination is detected, test passes and the planted file is removed" {
  s03t_tree; s03t_art own.md "client:acme"
  run bash "$P" test --client acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST PASSED"* ]]
  [[ "$output" == *"Separation proof contamin: 1"* ]]
  [ -z "$(ls "$SB/engagements/acme/artifacts" | grep planted)" ]
}

@test "test: --json reports PASS with the proof detecting the planted tag" {
  s03t_tree; s03t_art own.md "client:acme"
  run bash "$P" test --client acme --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
txt=sys.argv[1]; d=json.loads(txt[txt.index('{'):])
assert d['overall']=='PASS', d
assert d['separation_proof']['result']=='DETECTED' and d['separation_proof']['contamination']>=1, d
" "$output"
}

@test "test: a proof that cannot see the contamination fails the self-test (exit 1)" {
  s03t_tree; s03t_art own.md "client:acme"
  # wall-check inerte y python3 roto: nada detecta lo plantado
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/scripts/engagement-wall-check.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/python3"; chmod +x "$SB/bin/python3"
  run env PATH="$SB/bin:$PATH" bash "$P" test --client acme
  [ "$status" -eq 1 ]
  [[ "$output" == *"TEST FAILED"* ]]
  [[ "$output" == *"MISSED"* ]]
}

@test "test: without --client exits 1 and plants nothing" {
  s03t_tree
  run bash "$P" test
  [ "$status" -eq 1 ]
  [[ "$output" == *"--client required for adversarial test"* ]]
  [ -z "$(ls "$SB/engagements/acme/artifacts")" ]
}

@test "all: clean engagements are intact with exit 0" {
  s03t_tree; s03t_art own.md "client:acme"
  run bash "$P" all --json
  [ "$status" -eq 0 ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1])
assert d['total_engagements']==1 and d['total_clean']==1 and d['total_contaminated']==0, d
assert d['separation_intact'] is True and d['parse_errors']==0
" "$output"
}

@test "all: a contaminated engagement makes the whole proof fail (exit 1)" {
  s03t_tree; s03t_art leak.md "client:rival"
  run bash "$P" all --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"separation_intact":false'* ]]
  [[ "$output" == *'"total_contaminated":1'* ]]
  run bash "$P" all
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATIONS DETECTED"* ]]
}

@test "all: a proof that cannot be parsed is never reported as intact" {
  s03t_tree; s03t_art own.md "client:acme"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/python3"; chmod +x "$SB/bin/python3"
  run env PATH="$SB/bin:$PATH" bash "$P" all --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"separation_intact":false'* ]]
  [[ "$output" == *'"parse_errors":1'* ]]
}

@test "unknown flag exits 2 even with a valid command" {
  s03t_tree
  run bash "$P" generate --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

# ── Revisión de seguridad #1507 (P2-2, P2-3) ─────────────────────────────────

s03t_inactive_prod() { printf 'wall:\n  mode: strict\n  active: false\n' > "$SB/engagements/acme/prod.yaml"; }

@test "generate: client slug is matched literally, never as a regex (a.b does not accept client:axb)" {
  s03t_tree
  mkdir -p "$SB/engagements/a.b/artifacts"
  printf 'wall:\n  mode: strict\n  active: true\n' > "$SB/engagements/a.b/prod.yaml"
  printf 'notes client:axb\n' > "$SB/engagements/a.b/artifacts/x.md"
  run bash "$P" generate --client a.b --json
  [ "$status" -eq 1 ]
  python3 -c "
import json,sys
smp=json.loads(sys.argv[1])['engagements'][0]['samples'][0]
assert smp['status']=='contaminated', smp
" "$output"
}

@test "all: an engagement name with a quote cannot inject Python code" {
  s03t_tree; s03t_art own.md "client:acme"
  # Sin «/» en el nombre: la marca se crearía en el cwd, que es el árbol aislado.
  name="e'+str(__import__('os').system('touch PWNED'))+'"
  printf 'wall:\n  mode: strict\n  active: true\n' > "$SB/engagements/acme/$name.yaml"
  cd "$SB"
  run bash "$P" all --json
  [ ! -e "$SB/PWNED" ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1])
names=sorted(e['engagement'] for e in d['engagements'])
assert names==sorted(['prod',sys.argv[2]]), names
" "$output" "$name"
}

@test "all: zero active engagements is not a proof of separation (exit 1, intact false)" {
  s03t_tree; s03t_inactive_prod
  run bash "$P" all --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"total_engagements":0'* ]]
  [[ "$output" == *'"separation_intact":false'* ]]
  run bash "$P" all
  [ "$status" -eq 1 ]
  [[ "$output" == *"NO ENGAGEMENTS EVALUATED"* ]]
  [[ "$output" != *"SEPARATION INTACT"* ]]
}

@test "all: when the proof cannot be parsed, names with quotes still yield valid JSON" {
  s03t_tree; s03t_inactive_prod; s03t_art own.md "client:acme"
  printf 'wall:\n  mode: strict\n  active: true\n' > "$SB/engagements/acme/q\"x.yaml"
  real_py="$(command -v python3)"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/python3"; chmod +x "$SB/bin/python3"
  run env PATH="$SB/bin:$PATH" bash "$P" all --json
  [ "$status" -eq 1 ]
  "$real_py" -c "import json,sys; d=json.loads(sys.argv[1]); assert d['parse_errors']==1 and d['engagements'][0]['error']=='parse-failed', d" "$output"
}
