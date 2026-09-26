#!/usr/bin/env bats
# test-spec-166-configurator.bats — SPEC-166: configurator agent tests
#
# Tests:
# 1. configurator.md exists in .opencode/agents/
# 2. Agent has required frontmatter fields (name, model_tier, permission_level)
# 3. Agent body documents JSON output schema
# 4. Agent is under 100 lines (spec constraint)
# 5. Fallback behavior documented

# Ref: docs/rules/domain/model-alias-schema.md (provider-agnostic model tiers)
setup() {
  set -o pipefail
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel)"
  AGENT_FILE="$REPO_ROOT/.opencode/agents/configurator.md"
  A="$AGENT_FILE"
  TMP=$(mktemp -d)
  cd "$REPO_ROOT"
}

teardown() {
  rm -rf "$TMP"
}


@test "configurator.md exists in .opencode/agents/" {
  [ -f "$AGENT_FILE" ]
}

@test "agent has required frontmatter: name, model_tier, permission_level" {
  grep -q "^name:" "$AGENT_FILE"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$AGENT_FILE"
  grep -q "^permission_level:" "$AGENT_FILE"
}

@test "agent body documents JSON output schema" {
  grep -q '"agents_to_invoke"' "$AGENT_FILE"
  grep -q '"skills_to_load"' "$AGENT_FILE"
  grep -q '"rationale"' "$AGENT_FILE"
}

@test "agent file is under 100 lines" {
  line_count=$(wc -l < "$AGENT_FILE")
  [ "$line_count" -le 100 ]
}

@test "agent documents fallback behavior" {
  grep -qi "fallback" "$AGENT_FILE"
}

_fixture_agent() { # <frontmatter-line> -> PROJECT_ROOT tree with one agent
  mkdir -p "$TMP/.opencode/agents"
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/configurator.md"
}

@test "[configurator] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[configurator] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"configurator.md"* ]]
}

@test "[configurator] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[configurator] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[configurator] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"configurator-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[configurator] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/configurator.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"configurator\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}
