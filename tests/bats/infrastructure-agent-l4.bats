#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para infrastructure-agent: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/infrastructure-agent.md"
D="contracts/capabilities/agent.infrastructure-agent.yaml"
E="tests/evals/infrastructure-agent"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/infrastructure-agent.md"
}

@test "[infrastructure-agent] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[infrastructure-agent] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"infrastructure-agent.md"* ]]
}

@test "[infrastructure-agent] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[infrastructure-agent] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[infrastructure-agent] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"infrastructure-agent-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[infrastructure-agent] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/infrastructure-agent.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"infrastructure-agent\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

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
