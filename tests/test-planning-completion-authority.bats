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

@test "la plantilla de spec trae la sección de autoridad como sección propia y la tabla de correspondencia sigue intacta" {
  T="$ROOT/.claude/skills/spec-driven-development/references/spec-template.md"
  grep -q '^## Criterios de aceptación con autoridad (SE-444)$' "$T"
  grep -q 'autoridad_requerida' "$T"
  # Cada fila de la tabla Spec-Kit Alignment empieza y termina en la misma línea.
  run awk '/^Correspondencia entre secciones/{t=1} t && /^\| `## /{ if ($0 !~ /\|[[:space:]]*$/) bad=1 } t && /^$/ && seen{exit} t && /^\|/{seen=1} END{exit bad}' "$T"
  [ "$status" -eq 0 ]
  grep -q '^| `## Acceptance Criteria` | `## 5. Test Scenarios` + `## 10. Checklist Pre-Entrega` |$' "$T"
}

gitc() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

@test "planning_pr_merged encuentra un merge antiguo, más allá de los últimos 200 commits" {
  R="$BATS_TEST_TMPDIR/hist"; git init -q -b main "$R"
  gitc commit -q --allow-empty -m "Merge pull request #1200 from x/y"
  for i in $(seq 1 210); do gitc commit -q --allow-empty -m "c$i"; done
  run planning_pr_merged "$R" main 1200
  [ "$status" -eq 0 ]
  run planning_pr_merged "$R" main 1201
  [ "$status" -ne 0 ]
}

@test "planning_pr_merged solo cuenta merges reales: squash sí; menciones y reverts no" {
  R="$BATS_TEST_TMPDIR/formas"; git init -q -b main "$R"
  gitc commit -q --allow-empty -m "feat(x): algo (#1300)"
  gitc commit -q --allow-empty -m "fix: sigue lo de refs #1301"
  gitc commit -q --allow-empty -m 'Revert "feat(y): otra cosa (#1302)"'
  gitc commit -q --allow-empty -m "Merge pull request #13031 from x/y"
  run planning_pr_merged "$R" main 1300; [ "$status" -eq 0 ]
  run planning_pr_merged "$R" main 1301; [ "$status" -ne 0 ]
  run planning_pr_merged "$R" main 1302; [ "$status" -ne 0 ]
  run planning_pr_merged "$R" main 1303; [ "$status" -ne 0 ]
}
