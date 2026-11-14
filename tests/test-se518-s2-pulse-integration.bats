#!/usr/bin/env bats

# Ref: docs/specs/SE-518-pulse-latido.spec.md (S2: AC-10, AC-11)
# Envuelve la suite unittest para que la ejecute el selector de bats sin tocar workflows.
setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
}

@test "SE-518 S2: el script existe y es ejecutable" {
  [ -x scripts/pulse_integration.py ]
}

@test "SE-518 S2: suite unittest completa (AC-10 y AC-11, con negativos)" {
  run python3 -m unittest tests/python/test_pulse_integration.py
  [ "$status" -eq 0 ]
}

@test "SE-518 S2 negativo: política desconocida sale con 2 y sin salida" {
  run bash -c 'echo "[]" | python3 scripts/pulse_integration.py plan --policy siempre 2>/dev/null'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "SE-518 S2 negativo: entrada no JSON sale con 2 y sin salida" {
  run bash -c 'echo "no json" | python3 scripts/pulse_integration.py plan 2>/dev/null'
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}
