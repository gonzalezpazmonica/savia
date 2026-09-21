#!/usr/bin/env bats
# SE-396 P01 — merge evidence is necessary but never sufficient for graduation.

SCRIPT="scripts/planning-transition.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE/docs/propuestas" "$FIXTURE/tests"
  printf '%s\n' '# acceptance evidence' > "$FIXTURE/tests/ac.bats"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email test@example.invalid
  git -C "$FIXTURE" config user.name "Planning Test"
  git -C "$FIXTURE" add .
  git -C "$FIXTURE" commit -qm 'baseline'
  git -C "$FIXTURE" commit --allow-empty -qm 'feat: implementation (#42)'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
}

write_state() {
  local completion="${1:-}"
  if [[ -n "$completion" ]]; then
    cat > "$FIXTURE/docs/propuestas/planning-state.json" <<JSON
{"version":2,"completion_contract_floor":396,"initiatives":[
  {"id":"SE-396","status":"IMPLEMENTING","completion":$completion}
]}
JSON
  else
    cat > "$FIXTURE/docs/propuestas/planning-state.json" <<'JSON'
{"version":2,"completion_contract_floor":396,"initiatives":[
  {"id":"SE-396","status":"IMPLEMENTING","evidence":"PR #42"}
]}
JSON
  fi
}

@test "merged PR without structured acceptance evidence is not ready" {
  write_state

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: falta completion.merge_pr o evidencia AC estructurada"* ]]
}

@test "missing acceptance evidence file fails closed" {
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/missing.bats"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: evidencia AC inválida"* ]]
}

@test "unsafe acceptance evidence path fails closed" {
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"../outside"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: evidencia AC inválida"* ]]
}

@test "absolute acceptance evidence path fails closed" {
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"/tmp/ac.bats"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: evidencia AC inválida"* ]]
}

@test "symlinked acceptance evidence cannot escape the repository" {
  printf '%s\n' 'outside' > "$BATS_TEST_TMPDIR/outside-evidence"
  ln -s "$BATS_TEST_TMPDIR/outside-evidence" "$FIXTURE/tests/escaped"
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/escaped"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: evidencia AC inválida"* ]]
}

@test "merged PR plus valid acceptance evidence only requests human review" {
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}]}'
  before="$(sha256sum "$FIXTURE/docs/propuestas/planning-state.json")"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 0 ]
  [[ "$output" == *"NEEDS_HUMAN_REVIEW"* ]]
  [ "$before" = "$(sha256sum "$FIXTURE/docs/propuestas/planning-state.json")" ]
}

@test "unmerged structured PR is not ready" {
  write_state '{"merge_pr":99,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/ac.bats"}]}'

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-396

  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT_READY: PR #99 no está mergeado"* ]]
}
