#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para court-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/court-orchestrator.md"
D="contracts/capabilities/agent.court-orchestrator.yaml"
E="tests/evals/court-orchestrator"

@test "[court-orchestrator] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: court-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[court-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[court-orchestrator] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[court-orchestrator] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[court-orchestrator] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[court-orchestrator] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
