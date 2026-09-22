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
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-396-example.spec.md"
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

@test "validate rejects governed implemented state whose PR is not on main" {
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
