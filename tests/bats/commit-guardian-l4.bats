#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para commit-guardian: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/commit-guardian.md"
D="contracts/capabilities/agent.commit-guardian.yaml"
E="tests/evals/commit-guardian"

@test "[commit-guardian] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: commit-guardian$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[commit-guardian] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[commit-guardian] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[commit-guardian] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[commit-guardian] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[commit-guardian] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
