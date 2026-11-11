#!/usr/bin/env bats

# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md (AC-4)
# Desactiva cada paso del kernel por turnos (parche en proceso) y exige que falle su caso de R5.

setup() {
  set -o pipefail
  cd "$BATS_TEST_DIRNAME/.."
  TMP=$(mktemp -d -p "$BATS_TEST_TMPDIR")  # bats borra BATS_TEST_TMPDIR al terminar cada test
}

teardown() {
  unset TMP
}

@test "AC-4: sin parche, el caso de cada paso da el código esperado (el test puede fallar de verdad)" {
  run python3 tests/helpers/se496_mutation.py --baseline
  [ "$status" -eq 0 ]
  [ "$output" = "BASE-OK" ]
}

@test "AC-4: el informe completo mata los 18 pasos y ninguno sobrevive" {
  run python3 tests/helpers/se496_mutation.py
  [ "$status" -eq 0 ]
  [ "$(grep -c '^KILLED' <<<"$output")" -eq 18 ]
  [[ "$output" != *SURVIVED* ]]
}

@test "AC-4 boundary: el paso 0 no existe y se rechaza con exit 2" {
  run python3 tests/helpers/se496_mutation.py --step 0
  [ "$status" -eq 2 ]
  [[ "$output" == *inexistente* ]]
}

@test "AC-4 boundary: el paso 19 no existe y se rechaza con exit 2" {
  run python3 tests/helpers/se496_mutation.py --step 19
  [ "$status" -eq 2 ]
}

@test "AC-4: un paso no numérico se rechaza con exit 2" {
  run python3 tests/helpers/se496_mutation.py --step abc
  [ "$status" -eq 2 ]
}

@test "AC-4: paso 1 (contract) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 1
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 2 (self_issued) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 2
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 3 (signature) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 3
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 4 (principal) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 4
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 5 (revoked) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 5
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 6 (time) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 6
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 7 (capability) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 7
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 8 (ambiguous) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 8
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 9 (inferred) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 9
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 10 (scope) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 10
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 11 (uses) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 11
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 12 (readers) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 12
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 13 (preconditions) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 13
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 14 (effects) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 14
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 15 (level) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 15
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 16 (tier) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 16
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 17 (action_match) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 17
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

@test "AC-4: paso 18 (state_match) disabled -> su caso de R5 falla" {
  run python3 tests/helpers/se496_mutation.py --step 18
  [ "$status" -eq 0 ]
  [[ "$output" == KILLED* ]]
}

