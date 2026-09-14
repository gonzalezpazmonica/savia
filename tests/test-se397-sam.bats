#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "SE-397 F2 CLI, schema and runtime declarations exist" {
  [ -x scripts/sam.py ]
  [ -f scripts/sam_model.py ]
  [ -f .scm/sam.schema.json ]
  [ -f .scm/sam-runtime-declarations.json ]
}

@test "SE-397 F2 committed projection is fresh" {
  run python3 scripts/sam.py check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAM: FRESH"* ]]
}

@test "SE-397 F2 model is valid and report-only" {
  run python3 -m unittest tests/test_sam.py -v
  [ "$status" -eq 0 ]
}

@test "SE-397 F2 capability map remains fresh" {
  run python3 scripts/generate-capability-map.py --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCM: FRESH"* ]]
}

@test "SE-397 remains implementing and F2 runtime views are present" {
  run grep -A8 '"id": "SE-397"' docs/propuestas/planning-state.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "APPROVED"'* || "$output" == *'"status": "IMPLEMENTING"'* ]]
  [ -f .scm/views/runtime.json ]
  [ -f .scm/views/authority.json ]
  [ -f .scm/views/failure.json ]
}

@test "SE-397 F2 external effects retain human decision authority" {
  run python3 scripts/sam.py query --node flow:external-effect
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"FOUND"'* ]]
  [[ "$output" == *'"relation":"REQUIRES_HUMAN"'* ]]
  [[ "$output" == *'"target":"authority:human-decision"'* ]]
}
