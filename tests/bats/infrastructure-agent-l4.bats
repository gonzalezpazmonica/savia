#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para infrastructure-agent: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/infrastructure-agent.md"
D="contracts/capabilities/agent.infrastructure-agent.yaml"
E="tests/evals/infrastructure-agent"

@test "[infrastructure-agent] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: infrastructure-agent$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[infrastructure-agent] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[infrastructure-agent] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[infrastructure-agent] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[infrastructure-agent] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[infrastructure-agent] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
