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

# ── Comportamiento: uso, estados, forma de la evidencia y formatos de merge ─

_run() { run env REPO_ROOT="$FIXTURE" "$@" bash "$SCRIPT" check SE-396; }

_ok_ev='{"criterion":"AC-01","file":"tests/ac.bats"}'

@test "uso: sin argumentos, sin id o con verbo distinto sale 1 con el uso" {
  for args in "" "check" "validate SE-396" "SE-396"; do
    run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" $args
    [ "$status" -eq 1 ]
    [[ "$output" == *"uso: planning-transition.sh check SE-NNN"* ]]
  done
}

@test "id inexistente: FAIL y exit 1" {
  write_state "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev]}"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" check SE-999
  [ "$status" -eq 1 ]
  [ "$output" = "FAIL: SE-999 no existe" ]
}

@test "estado distinto de IMPLEMENTING: NOT_READY citando el estado" {
  for st in APPROVED PROPOSED IMPLEMENTED; do
    cat > "$FIXTURE/docs/propuestas/planning-state.json" <<JSON
{"version":2,"initiatives":[{"id":"SE-396","status":"$st","completion":{"merge_pr":42,"acceptance_evidence":[$_ok_ev]}}]}
JSON
    _run
    [ "$status" -eq 1 ]
    [ "$output" = "NOT_READY: SE-396 está en estado $st, no IMPLEMENTING" ]
  done
}

@test "forma inválida: merge_pr no entero positivo es NOT_READY" {
  for pr in 0 -3 1.5 '"42"' null; do
    write_state "{\"merge_pr\":$pr,\"acceptance_evidence\":[$_ok_ev]}"
    _run
    [ "$status" -eq 1 ]
    [[ "$output" == *"falta completion.merge_pr o evidencia AC estructurada"* ]]
  done
}

@test "forma inválida: evidencia vacía, sin criterion, sin file o con campos vacíos" {
  for ev in '[]' '[{"file":"tests/ac.bats"}]' '[{"criterion":"AC-01"}]' \
            '[{"criterion":"","file":"tests/ac.bats"}]' '[{"criterion":"AC-01","file":""}]' \
            '[{"criterion":"AC-01","file":7}]' '["tests/ac.bats"]' '"tests/ac.bats"'; do
    write_state "{\"merge_pr\":42,\"acceptance_evidence\":$ev}"
    _run
    [ "$status" -eq 1 ]
    [[ "$output" == *"falta completion.merge_pr o evidencia AC estructurada"* ]]
  done
}

@test "forma inválida: un AC bueno no salva a uno malo" {
  write_state "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev,{\"criterion\":\"AC-02\"}]}"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"estructurada"* ]]
}

@test "completion ausente (null) o no objeto es NOT_READY" {
  write_state '"texto"'
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"estructurada"* ]]
}

@test "evidencia: un directorio no vale como fichero" {
  mkdir -p "$FIXTURE/tests/dir"
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/dir"}]}'
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidencia AC inválida"* ]]
}

@test "evidencia: ruta con .. en cualquier segmento se rechaza aunque exista" {
  write_state '{"merge_pr":42,"acceptance_evidence":[{"criterion":"AC-01","file":"tests/../tests/ac.bats"}]}'
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidencia AC inválida"* ]]
}

@test "evidencia: varios ficheros, uno ausente invalida el conjunto" {
  write_state "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev,{\"criterion\":\"AC-02\",\"file\":\"tests/nada.bats\"}]}"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"evidencia AC inválida"* ]]
}

@test "evidencia: varios ficheros válidos dan NEEDS_HUMAN_REVIEW con el número de PR" {
  printf 'x\n' > "$FIXTURE/tests/b.bats"
  write_state "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev,{\"criterion\":\"AC-02\",\"file\":\"tests/b.bats\"}]}"
  _run
  [ "$status" -eq 0 ]
  [[ "$output" == "NEEDS_HUMAN_REVIEW: PR #42 y evidencia AC verificados"* ]]
}

@test "merge: el commit 'Merge pull request #N' cuenta" {
  git -C "$FIXTURE" commit --allow-empty -qm 'Merge pull request #77 from x/y'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
  write_state "{\"merge_pr\":77,\"acceptance_evidence\":[$_ok_ev]}"
  _run
  [ "$status" -eq 0 ]
}

@test "merge: un asunto que solo menciona #N en medio no cuenta" {
  git -C "$FIXTURE" commit --allow-empty -qm 'docs: ver (#88) para contexto adicional'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
  write_state "{\"merge_pr\":88,\"acceptance_evidence\":[$_ok_ev]}"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"PR #88 no está mergeado"* ]]
}

@test "merge: #4 no se confunde con #42 (coincidencia exacta del número)" {
  write_state "{\"merge_pr\":4,\"acceptance_evidence\":[$_ok_ev]}"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"PR #4 no está mergeado"* ]]
}

@test "merge: PLANNING_MAIN_REF apunta a otra referencia" {
  git -C "$FIXTURE" branch otra
  git -C "$FIXTURE" checkout -q otra
  git -C "$FIXTURE" commit --allow-empty -qm 'feat: solo en otra (#55)'
  write_state "{\"merge_pr\":55,\"acceptance_evidence\":[$_ok_ev]}"
  _run
  [ "$status" -eq 1 ]
  _run PLANNING_MAIN_REF=otra
  [ "$status" -eq 0 ]
}

@test "merge: referencia inexistente da NOT_READY, no error de shell" {
  write_state "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev]}"
  _run PLANNING_MAIN_REF=no/existe
  [ "$status" -eq 1 ]
  [[ "$output" == *"no está mergeado en no/existe"* ]]
}

@test "lib: planning_pr_merged rechaza números no numéricos (regex inyectada)" {
  source scripts/lib/planning-completion.sh
  run planning_pr_merged "$FIXTURE" origin/main '.*'
  [ "$status" -eq 1 ]
  run planning_pr_merged "$FIXTURE" origin/main ''
  [ "$status" -eq 1 ]
  run planning_pr_merged "$FIXTURE" origin/main 42
  [ "$status" -eq 0 ]
}

@test "lib: aviso de clon superficial en stderr sin cambiar el resultado" {
  source scripts/lib/planning-completion.sh
  git clone -q --depth 1 "file://$FIXTURE" "$BATS_TEST_TMPDIR/shallow"
  run planning_pr_merged "$BATS_TEST_TMPDIR/shallow" origin/HEAD 42
  [[ "$output" == *"AVISO planning_pr_merged: clon superficial"* ]]
  [ "$status" -eq 0 ]
  run planning_pr_merged "$FIXTURE" origin/main 42
  [[ "$output" != *"AVISO"* ]]
}

@test "lib: planning_human_review_approved exige APPROVED y evidencia no vacía" {
  source scripts/lib/planning-completion.sh
  run planning_human_review_approved '{"human_review":{"status":"APPROVED","evidence":"PR #1"}}'
  [ "$status" -eq 0 ]
  for c in '{}' '{"human_review":{"status":"PENDING","evidence":"x"}}' \
           '{"human_review":{"status":"APPROVED","evidence":""}}' \
           '{"human_review":{"status":"APPROVED"}}' '{"human_review":"APPROVED"}'; do
    run planning_human_review_approved "$c"
    [ "$status" -ne 0 ]
  done
}

@test "lib: planning_evidence_file_valid rechaza vacío y absoluto, acepta relativo existente" {
  source scripts/lib/planning-completion.sh
  run planning_evidence_file_valid "$FIXTURE" ""
  [ "$status" -ne 0 ]
  run planning_evidence_file_valid "$FIXTURE" "/etc/hostname"
  [ "$status" -ne 0 ]
  run planning_evidence_file_valid "$FIXTURE" "tests/ac.bats"
  [ "$status" -eq 0 ]
  run planning_evidence_file_valid "$FIXTURE/no-existe" "tests/ac.bats"
  [ "$status" -ne 0 ]
}

@test "solo lee: el estado y el repositorio quedan intactos tras cualquier veredicto" {
  write_state "{\"merge_pr\":99,\"acceptance_evidence\":[$_ok_ev]}"
  before="$(git -C "$FIXTURE" status --porcelain; sha256sum "$FIXTURE/docs/propuestas/planning-state.json")"
  _run
  after="$(git -C "$FIXTURE" status --porcelain; sha256sum "$FIXTURE/docs/propuestas/planning-state.json")"
  [ "$before" = "$after" ]
}

@test "lib: referencia absoluta no se reinterpreta como relativa al repo" {
  source scripts/lib/planning-completion.sh
  run planning_evidence_file_valid "$FIXTURE" "/tests/ac.bats"
  [ "$status" -ne 0 ]
  run planning_evidence_file_valid "$FIXTURE" "tests/ac.bats"
  [ "$status" -eq 0 ]
}

@test "lib: enlace simbólico a un directorio hermano con el mismo prefijo no escapa" {
  source scripts/lib/planning-completion.sh
  mkdir -p "$BATS_TEST_TMPDIR/repo-evil"
  echo x > "$BATS_TEST_TMPDIR/repo-evil/ac"
  ln -s "$BATS_TEST_TMPDIR/repo-evil/ac" "$FIXTURE/tests/hermano"
  run planning_evidence_file_valid "$FIXTURE" "tests/hermano"
  [ "$status" -ne 0 ]
}

@test "lib: planning_acceptance_evidence_valid exige forma válida por sí misma" {
  source scripts/lib/planning-completion.sh
  run planning_acceptance_evidence_valid "$FIXTURE" '{"merge_pr":42}'
  [ "$status" -ne 0 ]
  run planning_acceptance_evidence_valid "$FIXTURE" '{"merge_pr":42,"acceptance_evidence":[]}'
  [ "$status" -ne 0 ]
  run planning_acceptance_evidence_valid "$FIXTURE" "{\"merge_pr\":42,\"acceptance_evidence\":[$_ok_ev]}"
  [ "$status" -eq 0 ]
}

@test "lib: planning_pr_merged solo acepta dígitos (no '1.*' ni '4x')" {
  source scripts/lib/planning-completion.sh
  git -C "$FIXTURE" commit --allow-empty -qm 'feat: grande (#1234)'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
  run planning_pr_merged "$FIXTURE" origin/main 1234
  [ "$status" -eq 0 ]
  run planning_pr_merged "$FIXTURE" origin/main '12.*'
  [ "$status" -ne 0 ]
  run planning_pr_merged "$FIXTURE" origin/main '1234x'
  [ "$status" -ne 0 ]
}

@test "merge: 'Merge pull request' solo cuenta al inicio del asunto y con número completo" {
  source scripts/lib/planning-completion.sh
  git -C "$FIXTURE" commit --allow-empty -qm 'revert: Merge pull request #66 de nuevo'
  git -C "$FIXTURE" commit --allow-empty -qm 'Merge pull request #12345 from x/y'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
  run planning_pr_merged "$FIXTURE" origin/main 66
  [ "$status" -ne 0 ]
  run planning_pr_merged "$FIXTURE" origin/main 123
  [ "$status" -ne 0 ]
  run planning_pr_merged "$FIXTURE" origin/main 12345
  [ "$status" -eq 0 ]
}

@test "merge: recorre todo el historial, no solo el último commit" {
  source scripts/lib/planning-completion.sh
  git -C "$FIXTURE" commit --allow-empty -qm 'chore: posterior 1'
  git -C "$FIXTURE" commit --allow-empty -qm 'chore: posterior 2'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
  run planning_pr_merged "$FIXTURE" origin/main 42
  [ "$status" -eq 0 ]
}
