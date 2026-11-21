#!/usr/bin/env bats
# SE-387 Slice D — eval L4 de recommendation-tribunal-orchestrator.
# Dos capas: (1) checks estaticos sobre la definicion del agente y sus jueces;
# (2) ejecucion REAL del agregador determinista scripts/recommendation-tribunal/aggregate.sh
# con veredictos sinteticos. Cada capa tiene un mutante que debe hacer fallar la eval.
# Ejecucion con modelo: ver tests/evals/README.md ("Evals L4 de agentes").
A=".claude/agents/recommendation-tribunal-orchestrator.md"
D="contracts/capabilities/agent.recommendation-tribunal-orchestrator.yaml"
E="tests/evals/recommendation-tribunal-orchestrator"
AGG="scripts/recommendation-tribunal/aggregate.sh"

load l4-eval-lib

setup() {
  set -o pipefail
  TMP="$BATS_TEST_TMPDIR"
}

@test "[recommendation-tribunal-orchestrator] smoke: agente L4 con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: recommendation-tribunal-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[recommendation-tribunal-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "^id: agent.recommendation-tribunal-orchestrator$" "$D"
  grep -qE "^laws:" "$D"
  grep -qE "^enforcement:" "$D"
  grep -qE "^negative_tests:" "$D"
  grep -qE "^receipt:" "$D"
  grep -qE "^  - LAW-" "$D"
}

@test "[recommendation-tribunal-orchestrator] golden: la definicion cumple los checks declarados" {
  [ "$(l4_check_count "$E/golden.json")" -ge 10 ]
  l4_run_checks "$E/golden.json" "$A"
}

@test "[recommendation-tribunal-orchestrator] edge: umbrales y timeout declarados en la definicion" {
  [ "$(l4_check_count "$E/edge.json")" -ge 5 ]
  l4_run_checks "$E/edge.json" "$A"
}

@test "[recommendation-tribunal-orchestrator] adversarial: salida solo JSON y evidencia obligatoria" {
  l4_run_checks "$E/adversarial.json" "$A"
}

@test "[recommendation-tribunal-orchestrator] bypass: veto, no secuencial y no invocable por usuario" {
  l4_run_checks "$E/bypass.json" "$A"
}

@test "[recommendation-tribunal-orchestrator] golden: agregador ejecutado da PASS y VETO esperados" {
  l4_aggregate_cases "$E/golden.json" "$AGG" "$TMP"
}

@test "[recommendation-tribunal-orchestrator] edge: bordes 0.8/0.79 de confianza y 79/80 de consenso" {
  l4_aggregate_cases "$E/edge.json" "$AGG" "$TMP"
}

@test "[recommendation-tribunal-orchestrator] adversarial: texto del juez es dato; juez sin nombre o no JSON => exit 4" {
  l4_aggregate_cases "$E/adversarial.json" "$AGG" "$TMP"
}

@test "[recommendation-tribunal-orchestrator] bypass: puntuacion alta no compensa veto; faltan jueces => exit 2/3" {
  l4_aggregate_cases "$E/bypass.json" "$AGG" "$TMP"
}

@test "[recommendation-tribunal-orchestrator] regression: un fixture es golden y declara agente" {
  jq -e '.scenario == "golden" and .agent == "recommendation-tribunal-orchestrator"' "$E/golden.json" >/dev/null
  for s in edge adversarial bypass; do
    jq -e --arg s "$s" '.scenario == $s and (.cases | length) >= 3' "$E/$s.json" >/dev/null
  done
}

# --- Mutantes: la eval DEBE fallar si el comportamiento deja de estar garantizado ---

@test "[recommendation-tribunal-orchestrator] mutante: sin la regla de skip, edge.json falla" {
  l4_mutate_remove "$A" "Skip\\*\\* if risk_class" "$TMP/agent.md"
  run l4_run_checks "$E/edge.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skip-below-medium"* ]]
}

@test "[recommendation-tribunal-orchestrator] mutante: sin la regla de confianza del veto, bypass.json falla" {
  l4_mutate_remove "$A" "Any judge with .confidence" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"veto-rule-confidence"* ]]
}

@test "[recommendation-tribunal-orchestrator] mutante: sin uno de los 4 jueces, golden.json falla" {
  l4_mutate_remove "$A" "^   - hallucination-fast-judge$" "$TMP/agent.md"
  run l4_run_checks "$E/golden.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"judge-hallucination-fast"* ]]
}

@test "[recommendation-tribunal-orchestrator] mutante: umbral de veto 0.8 -> 0.9 en el agregador, edge.json falla" {
  sed 's/exit !(c >= 0.8)/exit !(c >= 0.9)/' "$AGG" > "$TMP/aggregate.sh"
  ! cmp -s "$AGG" "$TMP/aggregate.sh"
  run l4_aggregate_cases "$E/edge.json" "$TMP/aggregate.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-veto-confidence-boundary-inclusive"* ]]
}

@test "[recommendation-tribunal-orchestrator] mutante: veto ignorado en el agregador, bypass.json falla" {
  sed 's/veto_triggered=true$/veto_triggered=false/' "$AGG" > "$TMP/aggregate.sh"
  ! cmp -s "$AGG" "$TMP/aggregate.sh"
  run l4_aggregate_cases "$E/bypass.json" "$TMP/aggregate.sh" "$TMP"
  [ "$status" -eq 1 ]
}
