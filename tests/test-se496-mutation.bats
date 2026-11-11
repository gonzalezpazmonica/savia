#!/usr/bin/env bats

# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md (AC-4)
# Desactiva cada paso del kernel por turnos (parche en proceso) y exige que falle su caso de R5.

setup() { cd "$BATS_TEST_DIRNAME/.."; }

@test "AC-4: con cada una de las 18 comprobaciones desactivada falla al menos su caso de R5" {
  run python3 tests/helpers/se496_mutation.py
  [ "$status" -eq 0 ]
  [ "$(grep -c '^KILLED' <<<"$output")" -eq 18 ]
  [[ "$output" != *SURVIVED* ]]
}
