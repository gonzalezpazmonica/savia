#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "SE-397 F1 CLI and schema exist" {
  [ -x scripts/sam.py ]
  [ -f scripts/sam_model.py ]
  [ -f .scm/sam.schema.json ]
}

@test "SE-397 F1 committed projection is fresh" {
  run python3 scripts/sam.py check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAM: FRESH"* ]]
}

@test "SE-397 F1 model is valid and report-only" {
  run python3 -m unittest tests/test_sam.py -v
  [ "$status" -eq 0 ]
}

@test "SE-397 F1 capability map remains fresh" {
  run python3 scripts/generate-capability-map.py --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCM: FRESH"* ]]
}

@test "SE-397 remains implementing and F2 is absent" {
  run grep -A8 '"id": "SE-397"' docs/propuestas/planning-state.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "APPROVED"'* || "$output" == *'"status": "IMPLEMENTING"'* ]]
  [ ! -e .scm/runtime.json ]
  [ ! -e .scm/authority.json ]
}
