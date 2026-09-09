#!/usr/bin/env bats
# SE-378 planning-state coverage and status reconciliation tests.

SCRIPT="scripts/roadmap.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE/docs/propuestas" "$FIXTURE/docs/specs"
  cat > "$FIXTURE/docs/propuestas/planning-state.json" <<'JSON'
{"version":1,"tracked_spec_floor":375,"initiatives":[
  {"id":"SE-375","status":"APPROVED","approval":"human approval"}
]}
JSON
}

@test "roadmap validator exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "roadmap validator keeps strict pipefail safety" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "validate accepts complete tracked coverage" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "validate rejects an omitted tracked spec" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-376-omitted.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: specs omitidas de planning-state: SE-376"* ]]
}

@test "validate ignores legacy specs below the declared floor" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-100-legacy.spec.md"
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
}

@test "validate detects YAML status drift" {
  printf '%s\n' 'status: PROPOSED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-375 spec=PROPOSED vs state=APPROVED"* ]]
}

@test "validate detects Markdown status drift" {
  printf '%s\n' '**Estado:** REJECTED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-375 spec=REJECTED vs state=APPROVED"* ]]
}

@test "validate rejects duplicate initiative IDs" {
  jq '.initiatives += [.initiatives[0]]' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IDs duplicados: SE-375"* ]]
}

@test "validate rejects an invalid lifecycle status" {
  jq '.initiatives[0].status="UNKNOWN"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estados inválidos: UNKNOWN"* ]]
}

@test "validate rejects approved state without human approval" {
  jq 'del(.initiatives[0].approval)' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: APPROVED sin aprobación registrada: SE-375"* ]]
}
