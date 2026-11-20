#!/usr/bin/env bats
# SE-396 P01 — completion contract enforced by roadmap validation.

SCRIPT="scripts/roadmap.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE/docs/propuestas" "$FIXTURE/docs/specs" "$FIXTURE/tests"
  printf '%s\n' '# evidence' > "$FIXTURE/tests/ac.bats"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email test@example.invalid
  git -C "$FIXTURE" config user.name "Planning Test"
  git -C "$FIXTURE" add .
  git -C "$FIXTURE" commit -qm 'baseline'
  git -C "$FIXTURE" commit --allow-empty -qm 'feat: implementation (#42)'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
}

write_implemented_state() {
  local completion="$1"
  cat > "$FIXTURE/docs/propuestas/planning-state.json" <<JSON
{"version":2,"tracked_spec_floor":396,"completion_contract_floor":396,"initiatives":[
  {"id":"SE-396","status":"IMPLEMENTED","evidence":"PR #42","completion":$completion}
]}
JSON
  printf '%s\n' 'status: IMPLEMENTED' > "$FIXTURE/docs/specs/SE-396-example.spec.md"
  printf '## 2026-09-26 SE-396 IMPLEMENTED\n' > "$FIXTURE/docs/propuestas/LOG.md"
}

@test "validate rejects governed implemented state without human review" {
  write_implemented_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IMPLEMENTED sin revisión humana aprobada: SE-396"* ]]
}

@test "validate rejects governed implemented state with missing AC file" {
  write_implemented_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/missing.bats"}],"human_review":{"status":"APPROVED","evidence":"review-1"}}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: evidencia AC inválida para SE-396"* ]]
}

@test "validate rejects governed implemented state citing a nonexistent merge PR on main" {
  write_implemented_state '{"merge_pr":99,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}],"human_review":{"status":"APPROVED","evidence":"review-1"}}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IMPLEMENTED sin PR mergeado verificable: SE-396"* ]]
}

@test "validate accepts governed implemented state with AC evidence and human review" {
  write_implemented_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}],"human_review":{"status":"APPROVED","evidence":"review-1"}}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "safety: roadmap validator runs under set -uo pipefail" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "boundary: initiative below the completion floor is exempt from the completion contract" {
  write_implemented_state '{}'
  jq '.completion_contract_floor=397' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "empty: governed implemented state with empty completion object is rejected" {
  write_implemented_state '{}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IMPLEMENTED sin PR mergeado verificable: SE-396"* ]]
  [[ "$output" == *"FAIL: IMPLEMENTED sin revisión humana aprobada: SE-396"* ]]
}

@test "missing: implemented state without LOG entry fails even with full evidence" {
  write_implemented_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}],"human_review":{"status":"APPROVED","evidence":"review-1"}}'
  printf '## 2026-09-26 SE-396 IMPLEMENTING\n' > "$FIXTURE/docs/propuestas/LOG.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estado vigente sin registro en LOG.md: SE-396"* ]]
}

@test "current view lists IMPLEMENTING initiatives with their evidence" {
  write_implemented_state '{}'
  jq '.initiatives[0].status="IMPLEMENTING"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" current

  [ "$status" -eq 0 ]
  [[ "$output" == *"- SE-396 [IMPLEMENTING]"*"evidencia: PR #42"* ]]
}
