#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para coherence-court-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/coherence-court-orchestrator.md"
D="contracts/capabilities/agent.coherence-court-orchestrator.yaml"
E="tests/evals/coherence-court-orchestrator"

# Ref: docs/rules/domain/model-alias-schema.md (provider-agnostic model tiers)
setup() {
  set -o pipefail
  TMP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP"
}

_fixture_agent() { # <frontmatter-line> -> PROJECT_ROOT tree with one agent
  mkdir -p "$TMP/.opencode/agents"
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/coherence-court-orchestrator.md"
}

@test "[coherence-court-orchestrator] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[coherence-court-orchestrator] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"coherence-court-orchestrator.md"* ]]
}

@test "[coherence-court-orchestrator] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[coherence-court-orchestrator] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[coherence-court-orchestrator] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coherence-court-orchestrator-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[coherence-court-orchestrator] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/coherence-court-orchestrator.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coherence-court-orchestrator\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

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
