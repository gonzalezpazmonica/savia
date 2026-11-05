#!/usr/bin/env bats
# Tests for confidentiality-sign.sh — cryptographic audit signing
# Ref: pr-signing-protocol.md · SE-501 (la firma se retira de las PR: sign/resign ya no escriben nada;
# verify sigue validando firmas históricas; la prueba de main es «verify-main», cubierta en
# tests/test-se501-derived.bats AC-7).

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/confidentiality-sign.sh"
ROOT="$BATS_TEST_DIRNAME/../.."

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

# SE-501: sign ya no escribe firmas. Las firmas históricas que verify debe seguir aceptando se fabrican aquí
# con el formato y el algoritmo del contrato: diff_hash = sha256 del ls-tree de HEAD sin los dos ficheros
# autorreferentes; signature = HMAC-SHA256(clave, diff_hash).
fixture_diff_hash() {
  git -C "$ROOT" ls-tree -r HEAD \
    | awk -F'\t' '$2 != ".confidentiality-signature" && $2 != ".github/workflows/confidentiality-gate.yml"' \
    | sha256sum | awk '{print $1}'
}
hmac_of() { python3 -c 'import hmac,hashlib,sys; print(hmac.new(sys.argv[1].encode(), sys.argv[2].encode(), hashlib.sha256).hexdigest())' "$1" "$2"; }
mk_sig() {  # mk_sig <clave> [<signature>] → firma histórica en CONFIDENTIALITY_SIG_FILE
  local h; h=$(fixture_diff_hash)
  printf '# Confidentiality audit signature — DO NOT EDIT\ndiff_hash=%s\ntimestamp=2026-01-01T00:00:00Z\nbranch=fixture\nhead_commit=0000000\nsignature=%s\n' \
    "$h" "${2:-$(hmac_of "$1" "$h")}" > "$CONFIDENTIALITY_SIG_FILE"
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

@test "retired (SE-501): sign exits 2, names both replacements and writes no signature" {
  run bash "$SCRIPT" sign
  [ "$status" -eq 2 ]
  [[ "$output" == *"retirado (SE-501)"* ]]
  [[ "$output" == *"confidentiality-scan.sh --pr"* ]]
  [[ "$output" == *"verify-main"* ]]
  [ ! -e "$CONFIDENTIALITY_SIG_FILE" ]
}

@test "retired (SE-501): sign creates no secret key" {
  bash "$SCRIPT" sign >/dev/null 2>&1 || true
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "key: no action alters an existing key file or its 600 permissions" {
  printf '%s\n' "$KEY_A" > "$HOME/.savia/confidentiality-key"
  chmod 600 "$HOME/.savia/confidentiality-key"
  before=$(sha256sum "$HOME/.savia/confidentiality-key")
  for a in sign resign verify status; do bash "$SCRIPT" "$a" >/dev/null 2>&1 || true; done
  [ "$(sha256sum "$HOME/.savia/confidentiality-key")" = "$before" ]
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

@test "retired (SE-501): sign without ~/.savia does not create it (no side effects)" {
  rm -rf "$HOME/.savia"
  run bash "$SCRIPT" sign
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.savia" ]
}

@test "retired (SE-501): resign exits 2 with the same replacements" {
  run bash "$SCRIPT" resign
  [ "$status" -eq 2 ]
  [[ "$output" == *"retirado (SE-501)"* ]]
  [[ "$output" == *"verify-main"* ]]
}

# ── Coverage breadth ──

@test "sign: uses sha256sum for hashing" {
  grep -q 'sha256sum' "$SCRIPT"
}

@test "verify: accepts HMAC-SHA256(key, diff_hash) and rejects any other construction" {
  mk_sig "$KEY_A"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
  # sha256(key + diff_hash) no es un HMAC: debe rechazarse.
  mk_sig "$KEY_A" "$(printf '%s%s' "$KEY_A" "$(fixture_diff_hash)" | sha256sum | awk '{print $1}')"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"HMAC mismatch"* ]]
}

@test "sign: the key never appears in a command line (ps-visible argv)" {
  ! grep -qE -- '-hmac "\$' "$SCRIPT"
}

# ── CI secret (CONFIDENTIALITY_HMAC_KEY) ──

@test "ci-key (SE-501): sign with the CI key is still retired — no signature, no local key" {
  drop_local_key
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" run bash "$SCRIPT" sign
  [ "$status" -eq 2 ]
  [ ! -e "$CONFIDENTIALITY_SIG_FILE" ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "ci-key: verify with the same env key reports HMAC VERIFIED" {
  mk_sig "$KEY_A"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "ci-key: reject a signature made with another key" {
  mk_sig "$KEY_B"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"HMAC mismatch"* ]]
}

@test "ci-key: local key file and identical CI secret are interchangeable" {
  printf '%s\n' "$KEY_A" > "$HOME/.savia/confidentiality-key"
  chmod 600 "$HOME/.savia/confidentiality-key"
  mk_sig "$KEY_A"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "require: verify without any key fails closed when HMAC is required" {
  mk_sig "$KEY_A"
  drop_local_key
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFIDENTIALITY_HMAC_KEY"* ]]
}

@test "require: empty env key counts as missing, not as a valid key" {
  mk_sig "$KEY_A"
  drop_local_key
  CONFIDENTIALITY_HMAC_KEY="" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
}

@test "require: sign refuses to mint an ephemeral key when HMAC is required" {
  drop_local_key
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" sign
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
  [ ! -s "$CONFIDENTIALITY_SIG_FILE" ]
}

@test "require: without the flag, verify with no key still skips (local default)" {
  mk_sig "$KEY_A"
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

@test "isolation (SE-501): no action writes the repo signature or CONFIDENTIALITY_SIG_FILE" {
  repo_sig="$ROOT/.confidentiality-signature"
  before=$(sha256sum "$repo_sig" 2>/dev/null || echo absent)
  for a in sign resign status; do bash "$SCRIPT" "$a" >/dev/null 2>&1 || true; done
  [ ! -e "$CONFIDENTIALITY_SIG_FILE" ]
  [ "$(sha256sum "$repo_sig" 2>/dev/null || echo absent)" = "$before" ]
}

@test "compat (SE-426 AC4): a signature made the old way (openssl -hmac) still verifies" {
  command -v openssl >/dev/null || skip "openssl not available"
  diff_hash=$(fixture_diff_hash)
  old=$(printf '%s' "$diff_hash" | openssl dgst -sha256 -hmac "$KEY_A" | awk '{print $NF}')
  mk_sig "$KEY_A" "$old"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "ci (SE-501 I3): no PR-triggered workflow receives the CI key, and none signs or re-signs" {
  wf="$ROOT/.github/workflows"
  for f in "$wf"/*.yml; do
    run python3 -c 'import sys,yaml
d=yaml.safe_load(open(sys.argv[1])); on=d.get("on", d.get(True)) or {}
ev=set(on) if isinstance(on,(dict,list)) else {on}
pr=bool(ev & {"pull_request","pull_request_target"})
sys.exit(1 if pr and "secrets.CONFIDENTIALITY_HMAC_KEY" in open(sys.argv[1]).read() else 0)' "$f"
    [ "$status" -eq 0 ] || { echo "workflow de PR con la clave HMAC: $f"; false; }
    ! grep -qE 'confidentiality-sign\.sh +(re)?sign' "$f" || { echo "workflow que firma: $f"; false; }
  done
}

# ── SE-426 paso 4 → SE-501: nadie re-firma ni deja firmas obsoletas ──

@test "resign (SE-501): retired with or without a key; creates no key" {
  run bash "$SCRIPT" resign
  [ "$status" -eq 2 ]
  [[ "$output" == *"verify-main"* ]]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
}

@test "resign: does not leave a forged-valid signature when the key is missing" {
  printf 'diff_hash=x\nsignature=y\n' > "$CONFIDENTIALITY_SIG_FILE"
  run bash "$SCRIPT" resign
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" verify
  [ "$status" -ne 0 ]
}

@test "resign (SE-501): with the CI key it still writes nothing; an existing valid signature stays byte-identical" {
  mk_sig "$KEY_A"
  before=$(sha256sum "$CONFIDENTIALITY_SIG_FILE")
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" run bash "$SCRIPT" resign
  [ "$status" -eq 2 ]
  [ "$(sha256sum "$CONFIDENTIALITY_SIG_FILE")" = "$before" ]
  CONFIDENTIALITY_HMAC_KEY="$KEY_A" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  CONFIDENTIALITY_HMAC_KEY="$KEY_B" CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"HMAC mismatch"* ]]
}

@test "key: CI secret with trailing newline is equivalent to the same key without it" {
  mk_sig "$KEY_A"
  CONFIDENTIALITY_HMAC_KEY="$KEY_A"$'\n' CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}

@test "key: newline-only CI secret counts as missing under strict mode" {
  CONFIDENTIALITY_HMAC_KEY=$'\n' CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" sign
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.savia/confidentiality-key" ]
  mk_sig "$KEY_A"
  CONFIDENTIALITY_HMAC_KEY=$'\n' CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 1 ]
}

@test "bots (SE-501): no script, hook or workflow calls sign/resign, and none swallows a confidentiality failure" {
  run grep -rnE 'confidentiality-sign\.sh +(re)?sign' "$ROOT/scripts" "$ROOT/.claude/hooks" "$ROOT/.github/workflows"
  [ "$status" -eq 1 ]
  ! grep -E 'confidentiality-(sign|scan)\.sh[^|]*\|\| *true' "$ROOT/.github/workflows/changelog-consolidate.yml"
  ! grep -E 'confidentiality-(sign|scan)\.sh[^|]*\|\| *true' "$ROOT/scripts/resolve-pr-conflicts.sh"
}

@test "key: local key file alone verifies (no CI env var set)" {
  printf '%s\n' "$KEY_A" > "$HOME/.savia/confidentiality-key"
  mk_sig "$KEY_A"
  grep -Eq '^signature=[0-9a-f]{64}$' "$CONFIDENTIALITY_SIG_FILE"
  CONFIDENTIALITY_REQUIRE_HMAC=1 run bash "$SCRIPT" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"HMAC: VERIFIED"* ]]
}
