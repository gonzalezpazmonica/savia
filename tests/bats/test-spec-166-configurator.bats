#!/usr/bin/env bats
# test-spec-166-configurator.bats — SPEC-166: configurator agent tests
#
# Tests:
# 1. configurator.md exists in .opencode/agents/
# 2. Agent has required frontmatter fields (name, model_tier, permission_level)
# 3. Agent body documents JSON output schema
# 4. Agent is under 100 lines (spec constraint)
# 5. Fallback behavior documented

setup() {
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel)"
  AGENT_FILE="$REPO_ROOT/.opencode/agents/configurator.md"
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
