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

@test "planning_pr_merged rechaza un número de PR que no es numérico (no entra en la regex)" {
  R="$BATS_TEST_TMPDIR/validar"; git init -q -b main "$R"
  gitc commit -q --allow-empty -m "Merge pull request #1400 from x/y"
  run planning_pr_merged "$R" main '[0-9]+'; [ "$status" -ne 0 ]
  run planning_pr_merged "$R" main '1|'; [ "$status" -ne 0 ]
  run planning_pr_merged "$R" main ''; [ "$status" -ne 0 ]
  run planning_pr_merged "$R" main 1400; [ "$status" -eq 0 ]
}

@test "planning_pr_merged avisa si el clon es superficial" {
  R="$BATS_TEST_TMPDIR/origen"; git init -q -b main "$R"
  for i in 1 2 3; do gitc commit -q --allow-empty -m "c$i (#15$i)"; done
  C="$BATS_TEST_TMPDIR/superficial"; git clone -q --depth 1 "file://$R" "$C"
  run planning_pr_merged "$C" main 151
  [ "$status" -ne 0 ]
  [[ "$output" == *"superficial"* ]]
}

# ── Predicado de cierre: forma, rutas de evidencia y revisión humana (S03s) ──
# Ref: docs/specs/SE-396 P01 y SE-444; consumidores: planning-transition.sh y roadmap.sh.
ev_ok='[{"criterion":"AC1","file":"docs/ev.md"}]'

@test "forma: merge_pr debe ser entero positivo (0, negativo, decimal o texto no valen)" {
  for pr in 0 -1 1.5 '"12"' null; do
    c=$(jq -nc --argjson pr "$pr" --argjson ev "$ev_ok" '{merge_pr: $pr, acceptance_evidence: $ev}')
    run planning_completion_shape_valid "$c"
    [ "$status" -ne 0 ]
  done
  run planning_completion_shape_valid "$(completion "$ev_ok")"
  [ "$status" -eq 0 ]
}

@test "forma: evidencia vacía, criterio vacío, elemento que no es objeto o JSON roto no valen" {
  for ev in '[]' '[{"criterion":"","file":"docs/ev.md"}]' '["docs/ev.md"]' '[{"criterion":"AC1","file":""}]'; do
    run planning_completion_shape_valid "$(completion "$ev")"
    [ "$status" -ne 0 ]
  done
  run planning_completion_shape_valid '{merge_pr: 12'
  [ "$status" -ne 0 ]
}

@test "ruta: absoluta, con .. aunque caiga dentro, directorio o inexistente no son evidencia" {
  mkdir -p "$FIX/docs/sub"
  # "/docs/ev.md" existe también como $FIX//docs/ev.md: solo la regla de ruta absoluta lo rechaza.
  for ref in /etc/hostname /docs/ev.md "docs/../docs/ev.md" docs/sub docs/missing.md ""; do
    run planning_evidence_file_valid "$FIX" "$ref"
    [ "$status" -ne 0 ]
  done
  run planning_evidence_file_valid "$FIX" "./docs/ev.md"
  [ "$status" -eq 0 ]
}

@test "ruta: un enlace simbólico dentro del repo que apunta fuera no es evidencia (seguridad)" {
  echo secreto > "$BATS_TEST_TMPDIR/fuera.md"
  ln -s "$BATS_TEST_TMPDIR/fuera.md" "$FIX/docs/enlace.md"
  run planning_evidence_file_valid "$FIX" docs/enlace.md
  [ "$status" -ne 0 ]
  ln -s ev.md "$FIX/docs/interno.md"
  run planning_evidence_file_valid "$FIX" docs/interno.md
  [ "$status" -eq 0 ]
}

@test "ruta: un nombre con salto de línea no se parte en dos rutas existentes (seguridad)" {
  echo ok > "$FIX/docs/otro.md"
  c=$(jq -nc '{merge_pr: 12, acceptance_evidence: [{criterion: "AC1", file: "docs/ev.md\ndocs/otro.md"}]}')
  [ ! -e "$FIX/docs/ev.md"$'\n'"docs/otro.md" ]
  run planning_acceptance_evidence_valid "$FIX" "$c"
  [ "$status" -ne 0 ]
}

@test "cierre: basta una evidencia inválida entre varias válidas para rechazar" {
  c=$(completion '[{"criterion":"AC1","file":"docs/ev.md"},{"criterion":"AC2","file":"docs/missing.md"},{"criterion":"AC3","file":"docs/ev.md"}]')
  run planning_acceptance_evidence_valid "$FIX" "$c"
  [ "$status" -ne 0 ]
}

@test "revisión humana: solo APPROVED exacto con evidencia no vacía vale" {
  base=$(completion "$ev_ok")
  ok=$(jq -c '.human_review = {status: "APPROVED", evidence: "PR #12 review"}' <<<"$base")
  run planning_human_review_approved "$ok"
  [ "$status" -eq 0 ]
  for hr in '{"status":"approved","evidence":"x"}' '{"status":"APPROVED"}' '{"status":"APPROVED","evidence":""}' '"APPROVED"' 'null'; do
    c=$(jq -c --argjson hr "$hr" '.human_review = $hr' <<<"$base")
    run planning_human_review_approved "$c"
    [ "$status" -ne 0 ]
  done
  run planning_human_review_approved "$base"
  [ "$status" -ne 0 ]
}

@test "autoridad: un valor desconocido cuenta como inferior a la requerida; elementos no objeto se ignoran" {
  c=$(jq -nc '{merge_pr: 1, acceptance_evidence: ["suelto", {criterion: "AC7", file: "docs/ev.md", authority: "experta", authority_required: "estatica"}]}')
  run planning_unverified_authority_list "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == $'AC7\tinsuficiente\texperta\testatica' ]]
}
