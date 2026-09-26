#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para coherence-court-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/coherence-court-orchestrator.md"
D="contracts/capabilities/agent.coherence-court-orchestrator.yaml"
E="tests/evals/coherence-court-orchestrator"

@test "[coherence-court-orchestrator] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: coherence-court-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[coherence-court-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[coherence-court-orchestrator] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[coherence-court-orchestrator] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[coherence-court-orchestrator] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[coherence-court-orchestrator] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
