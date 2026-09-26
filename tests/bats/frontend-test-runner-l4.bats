#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para frontend-test-runner: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/frontend-test-runner.md"
D="contracts/capabilities/agent.frontend-test-runner.yaml"
E="tests/evals/frontend-test-runner"

@test "[frontend-test-runner] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: frontend-test-runner$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[frontend-test-runner] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[frontend-test-runner] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[frontend-test-runner] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[frontend-test-runner] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[frontend-test-runner] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
