#!/usr/bin/env bats

# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md (F1: R7, AC-10)
# Adaptador en sombra SE-343 -> kernel: cada grant vigente del ledger de prueba se proyecta a su
# contrato equivalente, el kernel lo evalúa (pasos 4-16) y la discrepancia queda en el audit.
# operator-grant.sh no cambia: tests/test-operator-grant.bats sigue en verde sin tocarlo.
# Mundo hermético por caso (repo con origin/main, claves ficticias, gh falso, HOME temporal).

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  X="python3 tests/fixtures/se496/shadow_se343.py"
}

@test "AC-10: grant vigente que el kernel también permite -> ALLOW sin discrepancia; no consume el grant ni usos; audit íntegro" {
  run $X allow
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-10: grant vigente sobre un PR en borrador -> DENY PRECONDITION_FAILED:not_draft en el paso 13, discrepancia en el audit, exit 0 (la sombra no decide) y report la cuenta" {
  run $X draft
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-10: nonce proyectado revocado en origin/main -> REVOKED en el paso 5, discrepancia" {
  run $X revoked
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-10 negativo: grant firmado con una clave ajena no es vigente para SE-343 -> no se proyecta ni llega al audit" {
  run $X not-vigente
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-10 negativo: autonomy:* y merge sobre task:<id> no tienen capacidad equivalente -> UNMAPPED" {
  run $X unmapped
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "AC-10: delegado por defecto (savia) sin nivel declarado -> UNKNOWN_STATE en el paso 15" {
  run $X default-delegate
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "fail-closed: ledger ilegible, argumentos no válidos o delegado con ../ -> exit 2, nunca 0" {
  run $X fail-closed
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "kernel: los campos extra del audit no pisan los del kernel ni prev_sha256" {
  run $X reserved-extra
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}
