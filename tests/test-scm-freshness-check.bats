#!/usr/bin/env bats
# nightly: serial (ejecuta ci-extended-checks.sh entero, cuyo check #9 mide la latencia real de los hooks)
# BATS tests for ci-extended-checks.sh check #7 (SCM Freshness)
# Ref: docs/propuestas/SE-031-query-library-nl.md (freshness gate pattern)
# SPEC-055 quality gate (score >= 80)
#
# Check #7 delegates to `generate-capability-map.py --check`, which regenerates
# into a temp dir and compares byte for byte. It never writes to .scm/ nor
# restores it from git. Behaviour is tested against copies of .scm/ via
# SAVIA_SCM_DIR; the full ci-extended-checks.sh runs once per file (~20 s).

CHECK="scripts/ci-extended-checks.sh"
GEN="scripts/generate-capability-map.py"

setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  export CHECK_OUT="$BATS_FILE_TMPDIR/check.out"
  export SCM_BEFORE="$BATS_FILE_TMPDIR/scm.before"
  git status --porcelain -- .scm > "$SCM_BEFORE"
  # El código se guarda y lo afirma la prueba «all checks green»; si setup_file abortara aquí,
  # se perderían la salida del check y las otras 18 pruebas (nocturna 44621725564).
  local rc=0
  bash "$CHECK" > "$CHECK_OUT" 2>&1 || rc=$?
  echo "$rc" > "$BATS_FILE_TMPDIR/check.rc"
}

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
  COPY="$BATS_TEST_TMPDIR/scm-copy"
  cp -r .scm "$COPY"
}

teardown() {
  cd /
}

# ── Structure / safety ──────────────────────────────────────────────────────

@test "ci-extended-checks.sh exists and is executable" {
  [[ -x "$CHECK" ]]
}

@test "ci-extended-checks.sh uses set -uo pipefail" {
  run head -5 "$CHECK"
  [[ "$output" == *"set -uo pipefail"* ]]
}

@test "check #7 (SCM Freshness) is registered" {
  run grep -c '^# 7\. SCM Freshness' "$CHECK"
  [ "$output" = "1" ]
}

@test "check #7 uses the generator's read-only --check" {
  grep -q '"$scm_gen" --check' "$CHECK"
}

@test "check #7 never restores .scm from git (no destructive checkout)" {
  ! grep -qE 'checkout[[:space:]]+--[[:space:]]+\.scm' "$CHECK"
}

@test "check #7 mentions remediation command in error message" {
  # SE-501: .scm ya no se versiona; la remediación es regenerar con derived.sh, no commitear.
  run grep -c "stale — run 'bash scripts/derived.sh ensure'" "$CHECK"
  [[ "$output" -ge 1 ]]
  run grep -c "generate-capability-map.py.*commit" "$CHECK"
  [[ "$output" -eq 0 ]]
}

# ── Behaviour of the full check (single run in setup_file) ──────────────────

@test "check #7 passes when .scm is fresh" {
  grep -q "SCM Freshness" "$CHECK_OUT"
  grep -q "fresh vs tracked sources" "$CHECK_OUT"
}

@test "all checks green: passed equals total, 0 failed" {
  local rc; rc="$(cat "$BATS_FILE_TMPDIR/check.rc")"
  if [ "$rc" -ne 0 ]; then echo "ci-extended-checks.sh salió $rc:"; grep -nE "FAIL|failed|✗|❌" "$CHECK_OUT" | head -20; tail -15 "$CHECK_OUT"; false; fi
  run cat "$CHECK_OUT"
  [[ "$output" =~ Results:[[:space:]]+([0-9]+)[[:space:]]passed,[[:space:]]+0[[:space:]]failed[[:space:]]\(([0-9]+)[[:space:]]total ]]
  [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]
  [[ "${BASH_REMATCH[1]}" -ge 7 ]]
}

@test "the full check does not modify tracked .scm files" {
  [ "$(git status --porcelain -- .scm)" = "$(cat "$SCM_BEFORE")" ]
}

# ── Behaviour of the generator's --check (copies, never the repo) ───────────

@test "generator --check: FRESH on an exact copy" {
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCM: FRESH"* ]]
}

@test "negative: stale when a line is appended to INDEX.scm (body, not header)" {
  echo "# STALE_MARKER_FOR_TEST" >> "$COPY/INDEX.scm"
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"*"INDEX.scm"* ]]
}

@test "negative: stale when the header hash differs by one line (boundary)" {
  sed -i '2s/hash: [a-f0-9]*/hash: deadbeef1234/' "$COPY/INDEX.scm"
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 1 ]
}

@test "negative: stale when registry.json differs" {
  printf '{}\n' > "$COPY/registry.json"
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"registry.json"* ]]
}

@test "negative: missing INDEX.scm → exit 2 (MISSING)" {
  rm -f "$COPY/INDEX.scm"
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 2 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "negative: --check with an output path is rejected (exit 2)" {
  run python3 "$GEN" --check "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 2 ]
}

@test "negative: unknown flag rejected (exit 2)" {
  run python3 "$GEN" --bogus
  [ "$status" -eq 2 ]
}

@test "edge: --check is idempotent and leaves the copy untouched" {
  before=$(cd "$COPY" && find . -type f -exec sha256sum {} + | sort)
  SAVIA_SCM_DIR="$COPY" python3 "$GEN" --check >/dev/null
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 0 ]
  [ "$(cd "$COPY" && find . -type f -exec sha256sum {} + | sort)" = "$before" ]
}

@test "edge: empty INDEX.scm is stale, not fresh" {
  : > "$COPY/INDEX.scm"
  SAVIA_SCM_DIR="$COPY" run python3 "$GEN" --check
  [ "$status" -eq 1 ]
}

@test "edge: nonexistent check script triggers bash error" {
  run bash /tmp/nonexistent-ci-checks-12345.sh
  [ "$status" -ne 0 ]
}
