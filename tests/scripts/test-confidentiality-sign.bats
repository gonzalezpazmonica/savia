#!/usr/bin/env bats
# Tests for confidentiality-sign.sh — cryptographic audit signing
# Ref: pr-signing-protocol.md

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/confidentiality-sign.sh"

setup() {
  export TMPDIR_TEST=$(mktemp -d)
  export ORIG_HOME="$HOME"
  export HOME="$TMPDIR_TEST/home"
  mkdir -p "$HOME/.savia"
  # Isolation: signatures go to a temp file, never the committed .confidentiality-signature.
  export CONFIDENTIALITY_SIG_FILE="$TMPDIR_TEST/signature"
  unset CONFIDENTIALITY_HMAC_KEY CONFIDENTIALITY_REQUIRE_HMAC
  # Throwaway fixture keys, derived per run (never real material).
  KEY_A=$(printf 'fixture-a-%s' "$BATS_TEST_NUMBER" | sha256sum | cut -c1-64)
  KEY_B=$(printf 'fixture-b-%s' "$BATS_TEST_NUMBER" | sha256sum | cut -c1-64)
}

drop_local_key() { find "$HOME/.savia" -delete 2>/dev/null || true; }

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TMPDIR_TEST"
}

# ── Structure ──

@test "sign: script is valid bash" {
  bash -n "$SCRIPT"
}

@test "sign: uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

# ── Positive cases ──

@test "sign: status runs without crash" {
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
}

@test "sign: sign produces SIGNED output" {
  run bash "$SCRIPT" sign
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGNED"* ]]
}

@test "sign: secret key created on first sign" {
  bash "$SCRIPT" sign >/dev/null 2>&1
  [ -f "$HOME/.savia/confidentiality-key" ]
}

@test "sign: secret key has 600 permissions" {
  bash "$SCRIPT" sign >/dev/null 2>&1
  local perms
  perms=$(stat -c %a "$HOME/.savia/confidentiality-key" 2>/dev/null || stat -f %Lp "$HOME/.savia/confidentiality-key" 2>/dev/null)
  [ "$perms" = "600" ]
}

# ── Negative cases ──

@test "sign: unknown subcommand shows usage and exits 2" {
  run bash "$SCRIPT" foobar
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "sign: verify requires signature file existence check" {
  grep -q '! -f.*SIG_FILE' "$SCRIPT"
}

# ── Edge cases ──

@test "sign: secret dir created if missing" {
  rm -rf "$HOME/.savia"
  run bash "$SCRIPT" sign
  [ "$status" -eq 0 ]
  [ -d "$HOME/.savia" ]
}

@test "sign: handles empty diff gracefully" {
  run bash "$SCRIPT" sign
  [[ "$output" == *"hash="* ]] || [[ "$output" == *"SIGNED"* ]]
}

# ── Coverage breadth ──

@test "sign: uses sha256sum for hashing" {
  grep -q 'sha256sum' "$SCRIPT"
}

@test "sign: HMAC is HMAC-SHA256(key, diff_hash)" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  diff_hash=$(grep '^diff_hash=' "$CONFIDENTIALITY_SIG_FILE" | cut -d= -f2)
  sig=$(grep '^signature=' "$CONFIDENTIALITY_SIG_FILE" | cut -d= -f2)
  expected=$(python3 -c 'import hmac,hashlib,sys; print(hmac.new(sys.argv[1].encode(), sys.argv[2].encode(), hashlib.sha256).hexdigest())' "$KEY_A" "$diff_hash")
  [ "$sig" = "$expected" ]
}

@test "sign: the key never appears in a command line (ps-visible argv)" {
  ! grep -qE -- '-hmac "\$' "$SCRIPT"
}

# ── CI secret (CONFIDENTIALITY_HMAC_KEY) ──

@test "ci-key: sign with env key creates no local key file" {
  drop_local_key
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" run bash "$SCRIPT" sign
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "ci-key: verify with the same env key reports HMAC VERIFIED" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "ci-key: reject a signature made with another key" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_B" bash "$SCRIPT" sign >/dev/null
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"HMAC mismatch"* ]]
}

@test "ci-key: local key file and identical CI secret are interchangeable" {
  printf '%s\n' "$KEY_A" > "$HOME/.savia/confidentiality-key"
  chmod 600 "$HOME/.savia/confidentiality-key"
  bash "$SCRIPT" sign >/dev/null
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "require: verify without any key fails closed when HMAC is required" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  drop_local_key
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFIDENTIALITY_HMAC_KEY"* ]]
}

@test "require: empty env key counts as missing, not as a valid key" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  drop_local_key
  CONFIDENTIALITY_HMAC_KEY="" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
}

@test "require: sign refuses to mint an ephemeral key when HMAC is required" {
  drop_local_key
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" sign
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
  [ ! -s "$CONFIDENTIALITY_SIG_FILE" ]
}

@test "require: without the flag, verify with no key still skips (local default)" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  drop_local_key
  run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: SKIPPED"* ]]
}

@test "sign: signature format has 4 required fields" {
  grep -q 'diff_hash=' "$SCRIPT"
  grep -q 'timestamp=' "$SCRIPT"
  grep -q 'signature=' "$SCRIPT"
  grep -q 'branch=' "$SCRIPT"
}

@test "sign: excludes self-referencing files from diff" {
  grep -q 'confidentiality-signature' "$SCRIPT"
}

@test "sign: get_diff_hash function exists" {
  grep -q 'get_diff_hash' "$SCRIPT"
}

@test "sign: ensure_secret function exists" {
  grep -q 'ensure_secret' "$SCRIPT"
}

@test "sign: compute_hmac function exists" {
  grep -q 'compute_hmac' "$SCRIPT"
}

@test "isolation: sign writes CONFIDENTIALITY_SIG_FILE and leaves the repo signature untouched" {
  repo_sig="$BATS_TEST_DIRNAME/../../.confidentiality-signature"
  before=$(sha256sum "$repo_sig")
  run bash "$SCRIPT" sign
  [ "$status" -eq 0 ]
  [ -s "$CONFIDENTIALITY_SIG_FILE" ]
  [ "$(sha256sum "$repo_sig")" = "$before" ]
}

@test "compat (SE-426 AC4): a signature made the old way (openssl -hmac) still verifies" {
  command -v openssl >/dev/null || skip "openssl not available"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  diff_hash=$(grep '^diff_hash=' "$CONFIDENTIALITY_SIG_FILE" | cut -d= -f2)
  old=$(printf '%s' "$diff_hash" | openssl dgst -sha256 -hmac "$KEY_A" | awk '{print $NF}')
  sed -i "s/^signature=.*/signature=$old/" "$CONFIDENTIALITY_SIG_FILE"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "ci (SE-426 AC5): the three workflows that sign or verify use the CI key and require HMAC" {
  wf="$BATS_TEST_DIRNAME/../../.github/workflows"
  for f in confidentiality-gate.yml auto-rebase-open-prs.yml changelog-consolidate.yml; do
    run python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); envs=[j.get("env",{}) for j in d["jobs"].values()]; ok=[e for e in envs if e.get("CONFIDENTIALITY_REQUIRE_HMAC")=="1" and "secrets.CONFIDENTIALITY_HMAC_KEY" in str(e.get("CONFIDENTIALITY_HMAC_KEY",""))]; sys.exit(0 if ok else 1)' "$wf/$f"
    [ "$status" -eq 0 ] || { echo "sin clave de CI o sin modo exigente: $f"; false; }
  done
}

# ── SE-426 paso 4: los firmantes automáticos no empujan firmas obsoletas en silencio ──

@test "resign: without any key fails, names CONFIDENTIALITY_HMAC_KEY and creates no key" {
  run bash "$SCRIPT" resign
  [ "$status" -ne 0 ]
  [[ "$output" == *"CONFIDENTIALITY_HMAC_KEY"* ]]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "resign: does not leave a forged-valid signature when the key is missing" {
  printf 'diff_hash=x\nsignature=y\n' > "$CONFIDENTIALITY_SIG_FILE"
  run bash "$SCRIPT" resign
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" verify
  [ "$status" -ne 0 ]
}

@test "resign: with the CI key signs and the result verifies in strict mode; other key is rejected" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" run bash "$SCRIPT" resign
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESIGNED"* ]]
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  CONFIDENTIALITY_HMAC_KEY="$KEY_B" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"HMAC mismatch"* ]]
}

@test "key: CI secret with trailing newline is equivalent to the same key without it" {
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" bash "$SCRIPT" sign >/dev/null
  CONFIDENTIALITY_HMAC_KEY="$KEY_A"$'\n' CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "key: newline-only CI secret counts as missing under strict mode" {
  CONFIDENTIALITY_HMAC_KEY=$'\n' CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" sign
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "bots (SE-426 paso 4): both re-signers call resign and never swallow its failure" {
  root="$BATS_TEST_DIRNAME/../.."
  grep -q 'confidentiality-sign.sh resign' "$root/scripts/resolve-pr-conflicts.sh"
  grep -q 'confidentiality-sign.sh resign' "$root/.github/workflows/changelog-consolidate.yml"
  ! grep -E 'confidentiality-sign.sh (re)?sign[^|]*(>/dev/null 2>&1)?[^|]*\|\| *true' "$root/.github/workflows/changelog-consolidate.yml"
  ! grep -E 'confidentiality-sign.sh sign >/dev/null 2>&1$' "$root/scripts/resolve-pr-conflicts.sh"
}
