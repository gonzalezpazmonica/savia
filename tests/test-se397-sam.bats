#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "SE-397 F2 CLI, schema and runtime declarations exist" {
  [ -x scripts/sam.py ]
  [ -f scripts/sam_model.py ]
  [ -f .scm/sam.schema.json ]
  [ -f .scm/sam-runtime-declarations.json ]
  [ -f .scm/sam-verification-declarations.json ]
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
  [ -f .scm/reports/drift.json ]
  [ -f .scm/reports/claim-evidence.json ]
  [ -f .scm/reports/impact.json ]
}

@test "SE-397 F2 external effects retain human decision authority" {
  run python3 scripts/sam.py query --node flow:external-effect
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "FOUND"'* ]]
  [[ "$output" == *'"relation": "REQUIRES_HUMAN"'* ]]
  [[ "$output" == *'"target": "authority:human-decision"'* ]]
}

@test "SE-397 F3 impact query is report-only" {
  run python3 scripts/sam.py impact --node flow:external-effect --depth 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'"depth": 1'* ]]
  [[ "$output" == *'"limitations"'* ]]
}

@test "SE-397 F4 controlled corpus executes READ, SAFE_BASH and a registered hook" {
  events="output/.test-se397-f4-${BATS_TEST_NUMBER}.jsonl"
  rm -f "$events"
  before=$(git diff --no-ext-diff -- . ':!output' | sha256sum)

  run bash scripts/se397-f4-corpus.sh --events "$events"

  [ "$status" -eq 0 ]
  [[ "$output" == *"READ_COMMAND_EXECUTED=1"* ]]
  [[ "$output" == *"SAFE_BASH_COMMAND_EXECUTED=1"* ]]
  [[ "$output" == *"REGISTERED_HOOK_EXECUTED=1"* ]]
  [ -s "$events" ]
  run python3 scripts/sam.py trace --events "$events"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"operations":2'* ]]
  [[ "$output" == *'"complete":2'* ]]
  [[ "$output" == *'"flow_id":"flow:read"'* ]]
  [[ "$output" == *'"flow_id":"flow:bash"'* ]]
  after=$(git diff --no-ext-diff -- . ':!output' | sha256sum)
  [ "$before" = "$after" ]
  rm -f "$events"
}

@test "SE-397 F4 controlled corpus is semantically repeatable" {
  first="output/.test-se397-f4-repeat-a-${BATS_TEST_NUMBER}.jsonl"
  second="output/.test-se397-f4-repeat-b-${BATS_TEST_NUMBER}.jsonl"
  rm -f "$first" "$second"
  bash scripts/se397-f4-corpus.sh --events "$first" >/dev/null
  bash scripts/se397-f4-corpus.sh --events "$second" >/dev/null

  first_trace=$(python3 scripts/sam.py trace --events "$first" | \
    jq -S '(.operations[] | .duration_ms) = 0 | (.operations[].segments[] | .duration_ms) = 0')
  second_trace=$(python3 scripts/sam.py trace --events "$second" | \
    jq -S '(.operations[] | .duration_ms) = 0 | (.operations[].segments[] | .duration_ms) = 0')
  [ "$first_trace" = "$second_trace" ]
  first_revision=$(python3 scripts/sam.py baseline --events "$first" | jq -r .corpus_revision)
  second_revision=$(python3 scripts/sam.py baseline --events "$second" | jq -r .corpus_revision)
  [ "$first_revision" = "$second_revision" ]
  rm -f "$first" "$second"
}
