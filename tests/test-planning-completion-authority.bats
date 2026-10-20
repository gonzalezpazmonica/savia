#!/usr/bin/env bats
# SE-444: autoridad del verificador en la evidencia de AC (informe; el predicado de cierre no cambia).

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  . "$ROOT/scripts/lib/planning-completion.sh"
  FIX="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FIX/docs"; echo ok > "$FIX/docs/ev.md"
}

completion() { # $1 = acceptance_evidence JSON
  jq -nc --argjson ev "$1" '{merge_pr: 12, acceptance_evidence: $ev}'
}

@test "un AC cerrado con doble donde se exige real aparece marcado" {
  c=$(completion '[{"criterion":"AC1","file":"docs/ev.md","authority":"simulada","authority_required":"real"}]')
  run planning_unverified_authority_list "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == $'AC1\tinsuficiente\tsimulada\treal' ]]
}

@test "un AC con autoridad real no se lista" {
  c=$(completion '[{"criterion":"AC1","file":"docs/ev.md","authority":"real","authority_required":"real"}]')
  run planning_unverified_authority_list "$c"
  [ -z "$output" ]
}

@test "autoridad ausente se lista como ausente" {
  c=$(completion '[{"criterion":"AC2","file":"docs/ev.md"}]')
  run planning_unverified_authority_list "$c"
  [[ "$output" == $'AC2\tausente\t-\t-' ]]
}

@test "estatica frente a simulada requerida es insuficiente; simulada sin requisito no se lista" {
  c=$(completion '[{"criterion":"A","file":"docs/ev.md","authority":"estatica","authority_required":"simulada"},{"criterion":"B","file":"docs/ev.md","authority":"simulada"}]')
  run planning_unverified_authority_list "$c"
  [[ "$output" == $'A\tinsuficiente\testatica\tsimulada' ]]
}

@test "el predicado de cierre da el mismo resultado con y sin los campos nuevos" {
  legacy=$(completion '[{"criterion":"AC1","file":"docs/ev.md"}]')
  weak=$(completion '[{"criterion":"AC1","file":"docs/ev.md","authority":"simulada","authority_required":"real"}]')
  run planning_acceptance_evidence_valid "$FIX" "$legacy"; [ "$status" -eq 0 ]
  run planning_acceptance_evidence_valid "$FIX" "$weak";   [ "$status" -eq 0 ]
  bad=$(completion '[{"criterion":"AC1","file":"docs/missing.md","authority":"real","authority_required":"real"}]')
  run planning_acceptance_evidence_valid "$FIX" "$bad";    [ "$status" -ne 0 ]
  nofile=$(completion '[{"criterion":"AC1"}]')
  run planning_acceptance_evidence_valid "$FIX" "$nofile"; [ "$status" -ne 0 ]
}

@test "validate-ci-local imprime la seccion sin cambiar el codigo de salida" {
  cd "$ROOT"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' bash scripts/validate-ci-local.sh --quick
  [[ "$output" == *"Cobertura no verificada"* ]]
  code_with=$status
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash scripts/validate-ci-local.sh --quick
  [[ "$output" != *"Cobertura no verificada"* ]]
  [ "$status" -eq "$code_with" ]
}

@test "el informe de validate-ci-local marca un cierre con doble y no cambia la salida" {
  cd "$ROOT"
  jq -nc '{initiatives:[{id:"SE-X",completion:{merge_pr:1,acceptance_evidence:[{criterion:"AC9",file:"docs/ev.md",authority:"simulada",authority_required:"real"}]}}]}' > "$BATS_TEST_TMPDIR/state.json"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' bash scripts/validate-ci-local.sh --quick
  base=$status
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_PLANNING_STATE_FOR_TESTS="$BATS_TEST_TMPDIR/state.json" bash scripts/validate-ci-local.sh --quick
  [[ "$output" == *"SE-X · AC9: autoridad simulada < requerida real"* ]]
  [ "$status" -eq "$base" ]
}
