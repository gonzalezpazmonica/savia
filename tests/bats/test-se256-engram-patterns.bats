#!/usr/bin/env bats
# tests/bats/test-se256-engram-patterns.bats — SE-256
# Ref: SE-256 Engram Patterns (S1 y S2 archivados; queda S3)
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VERIFY_PRINCIPAL="$REPO_ROOT/scripts/verify-principal.sh"
}

# ── Slice 3: Principal verification ────────────────────────────────────

@test "AC-3.1: verify-principal existe y es ejecutable" {
  [ -f "$VERIFY_PRINCIPAL" ]
  [ -x "$VERIFY_PRINCIPAL" ]
}

@test "AC-3.2: verify-principal menciona ART-16" {
  run bash "$VERIFY_PRINCIPAL"
  [[ "$output" == *"ART-16"* ]]
}

@test "AC-3.3: verify-principal rechaza sin principal registrado" {
  rm -f "$HOME/.savia/principal"
  run bash "$VERIFY_PRINCIPAL"
  [ "$status" -ne 0 ]
}

@test "AC-3.4: verify-principal rejects null principal path" {
  run env PRINCIPAL_FILE="" bash "$VERIFY_PRINCIPAL"
  [ "$status" -ne 0 ]
}

@test "AC-3.5: verify-principal handles missing file without timeout" {
  run timeout 5 bash "$VERIFY_PRINCIPAL" /nonexistent/principal
  [ "$status" -ne 0 ]
}
