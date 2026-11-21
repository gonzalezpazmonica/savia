#!/usr/bin/env bats
# SE-387 Slice D — eval L4 de truth-tribunal-orchestrator.
# (1) checks estaticos sobre la definicion (7 jueces, bandas de veredicto, vetos
# absolutos, antipatrones) y sobre los 7 ficheros de juez; (2) comprobacion
# ejecutada de que cada perfil de pesos suma 1.00; (3) mutantes que deben fallar.
# Ejecucion con modelo: ver tests/evals/README.md ("Evals L4 de agentes").
A=".claude/agents/truth-tribunal-orchestrator.md"
D="contracts/capabilities/agent.truth-tribunal-orchestrator.yaml"
E="tests/evals/truth-tribunal-orchestrator"
W="docs/rules/domain/truth-tribunal-weights.md"

load l4-eval-lib

setup() {
  set -o pipefail
  TMP="$BATS_TEST_TMPDIR"
}

@test "[truth-tribunal-orchestrator] smoke: agente L4 con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: truth-tribunal-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
  grep -qE "^tools:.*Task" "$A"
}

@test "[truth-tribunal-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "^id: agent.truth-tribunal-orchestrator$" "$D"
  grep -qE "^laws:" "$D"
  grep -qE "^enforcement:" "$D"
  grep -qE "^negative_tests:" "$D"
  grep -qE "^receipt:" "$D"
  grep -qE "^  - LAW-" "$D"
}

@test "[truth-tribunal-orchestrator] golden: 7 jueces, bandas de veredicto y artefacto .truth.crc" {
  [ "$(l4_check_count "$E/golden.json")" -ge 20 ]
  l4_run_checks "$E/golden.json" "$A"
}

@test "[truth-tribunal-orchestrator] golden: cada perfil de pesos suma 1.00 y cubre las 7 dimensiones" {
  l4_weights_check "$E/golden.json"
}

@test "[truth-tribunal-orchestrator] edge: abstencion, tope de iteraciones y timeout" {
  [ "$(l4_check_count "$E/edge.json")" -ge 7 ]
  l4_run_checks "$E/edge.json" "$A"
}

@test "[truth-tribunal-orchestrator] adversarial: no puntua, no cachea, vetos de compliance/hallucination/factuality/coherence" {
  l4_run_checks "$E/adversarial.json" "$A"
}

@test "[truth-tribunal-orchestrator] bypass: un veto no se compensa, no se omite juez, no se entrega ITERATE" {
  l4_run_checks "$E/bypass.json" "$A"
  l4_weights_check "$E/bypass.json"
}

@test "[truth-tribunal-orchestrator] regression: forma de los fixtures" {
  jq -e '.scenario == "golden" and .agent == "truth-tribunal-orchestrator"' "$E/golden.json" >/dev/null
  for s in edge adversarial bypass; do
    jq -e --arg s "$s" '.scenario == $s and (.cases | length) >= 3' "$E/$s.json" >/dev/null
  done
}

# --- Mutantes: la eval DEBE fallar si el comportamiento deja de estar garantizado ---

@test "[truth-tribunal-orchestrator] mutante: sin 'NEVER override a veto', bypass.json falla" {
  l4_mutate_remove "$A" "NEVER override a veto" "$TMP/agent.md"
  run l4_run_checks "$E/bypass.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"veto-absolute"* ]]
}

@test "[truth-tribunal-orchestrator] mutante: sin la regla de abstencion, edge.json falla" {
  l4_mutate_remove "$A" "judges abstain, emit" "$TMP/agent.md"
  run l4_run_checks "$E/edge.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"abstain-threshold"* ]]
}

@test "[truth-tribunal-orchestrator] mutante: sin el juez compliance en la tabla, golden.json falla" {
  l4_mutate_remove "$A" "^\\| compliance-judge \\|" "$TMP/agent.md"
  run l4_run_checks "$E/golden.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"table-compliance"* ]]
}

@test "[truth-tribunal-orchestrator] mutante: sin el veto de PII de compliance, adversarial.json falla" {
  l4_mutate_remove "$A" "compliance-judge: PII leak" "$TMP/agent.md"
  run l4_run_checks "$E/adversarial.json" "$TMP/agent.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"compliance-veto"* ]]
}

@test "[truth-tribunal-orchestrator] mutante: perfil de pesos que suma 1.10, la comprobacion falla" {
  sed '0,/| compliance | 0.15 |/s//| compliance | 0.25 |/' "$W" > "$TMP/weights.md"
  ! cmp -s "$W" "$TMP/weights.md"
  run l4_weights_check "$E/golden.json" "$TMP/weights.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"perfil 'default'"* ]]
}

@test "[truth-tribunal-orchestrator] mutante: dimension duplicada en un perfil, la comprobacion falla" {
  sed '0,/| coherence | 0.10 |/s//| factuality | 0.10 |/' "$W" > "$TMP/weights.md"
  ! cmp -s "$W" "$TMP/weights.md"
  run l4_weights_check "$E/golden.json" "$TMP/weights.md"
  [ "$status" -eq 1 ]
}
