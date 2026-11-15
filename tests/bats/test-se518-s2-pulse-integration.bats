#!/usr/bin/env bats
# tests/bats/test-se518-s2-pulse-integration.bats — SE-518 S2
# Ref: docs/specs/SE-518-pulse-latido.spec.md (S2: AC-10, AC-11)
# Vive en tests/bats/ para que ci-select-bats lo elija cuando cambian el script o su
# suite (las rutas citadas abajo alimentan el mapa de dependencias del selector).
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PULSE="$REPO_ROOT/scripts/pulse_integration.py"
  SUITE="$REPO_ROOT/tests/python/test_pulse_integration.py"
}

@test "SE-518 S2: el script existe y es ejecutable" {
  [ -x "$PULSE" ]
}

@test "SE-518 S2: suite unittest completa (AC-10 y AC-11, con negativos)" {
  run python3 -m unittest "$SUITE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "SE-518 S2 negativo: política desconocida sale con 2 y sin salida" {
  run bash -c 'echo "[]" | python3 "$1" plan --policy siempre 2>/dev/null' _ "$PULSE"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "SE-518 S2 negativo: entrada no JSON sale con 2 y sin salida" {
  run bash -c 'echo "no json" | python3 "$1" plan 2>/dev/null' _ "$PULSE"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "SE-518 S2 negativo: reviewers con --head que no es SHA sale con 2" {
  run python3 "$PULSE" reviewers --pr 1 --base origin/main --head mi-rama --ledger "$BATS_TEST_TMPDIR/l.jsonl"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/l.jsonl" ]
}
