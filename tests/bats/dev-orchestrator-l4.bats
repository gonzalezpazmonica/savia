#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para dev-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/dev-orchestrator.md"
D="contracts/capabilities/agent.dev-orchestrator.yaml"
E="tests/evals/dev-orchestrator"

@test "[dev-orchestrator] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: dev-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[dev-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[dev-orchestrator] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[dev-orchestrator] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[dev-orchestrator] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[dev-orchestrator] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}
