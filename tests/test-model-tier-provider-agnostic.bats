#!/usr/bin/env bats
# BATS tests for provider-agnostic model tiers (SPEC-127 / PV-06).
# Covers: scripts/model-tier-lint.sh, .claude/hooks/model-tier-inject.sh,
# savia_resolve_model per-frontend lookup and the retired sync-model-tiers.sh.
# Ref: docs/rules/domain/model-alias-schema.md

LINT="scripts/model-tier-lint.sh"
HOOK=".claude/hooks/model-tier-inject.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$(pwd)"
  TMP="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  PREFS="$TMP/preferences.yaml"
  cat > "$PREFS" <<'EOF'
version: 1
model_heavy: legacy/heavy
model_mid:   legacy/mid
tiers:
  opencode:
    heavy: oc/heavy
  claude-code:
    heavy: opus
    mid: sonnet   # inline comment
    fast: not-a-selector
EOF
  export SAVIA_PREFS_FILE="$PREFS"
  export CLAUDE_PROJECT_DIR="$REPO"
}

teardown() {
  rm -rf "$TMP/r" "$TMP/home"
}

hook() { printf '%s' "$1" | bash "$HOOK"; }

@test "lint and hook exist, are executable and parse" {
  [[ -x "$LINT" && -x "$HOOK" ]]
  run bash -n "$LINT"; [ "$status" -eq 0 ]
  run bash -n "$HOOK"; [ "$status" -eq 0 ]
}

@test "lint passes on the repository sources" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
}

@test "lint rejects a vendor model in agent frontmatter" {
  mkdir -p "$TMP/r/.claude/agents"
  printf -- '---\nname: x\nmodel: vendor/model-1\n---\nbody\n' > "$TMP/r/.claude/agents/x.md"
  PROJECT_ROOT="$TMP/r" run bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x.md"*"model_tier"* ]]
}

@test "lint rejects an invalid model_tier and opencode.json agent model" {
  mkdir -p "$TMP/r/.claude/commands"
  printf -- '---\nname: c\nmodel_tier: ultra\n---\n' > "$TMP/r/.claude/commands/c.md"
  printf '{"agent":{"build":{"model":"vendor/m"}}}' > "$TMP/r/opencode.json"
  PROJECT_ROOT="$TMP/r" run bash "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
  [[ "$output" == *"agent.build.model"* ]]
}

@test "hook injects the local claude-code selector for a heavy agent" {
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"architect","prompt":"p"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"model": "opus"'* ]]
  [[ "$output" == *'"prompt": "p"'* ]]
}

@test "hook strips inline comments from the selector" {
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"test-runner"}}'
  [[ "$output" == *'"model": "sonnet"'* ]]
}

@test "hook keeps an explicit per-invocation model" {
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"architect","model":"haiku"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook replaces invalid selectors with the default; ignores unknown agents and other tools" {
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"tech-writer"}}'
  [ "$status" -eq 0 ]; [[ "$output" == *'"model": "haiku"'* ]]
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"no-such-agent"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "hook rejects path traversal in subagent_type and malformed input" {
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"../../etc/passwd"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run hook 'not json'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "hook defaults to opus/sonnet/haiku and never to legacy provider models" {
  printf 'model_heavy: legacy/heavy\n' > "$PREFS"
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"architect"}}'
  [ "$status" -eq 0 ]; [[ "$output" == *'"model": "opus"'* ]]
  SAVIA_PREFS_FILE=/nonexistent run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"test-runner"}}'
  [[ "$output" == *'"model": "sonnet"'* ]]
}

@test "hook master switch disables injection" {
  SAVIA_MODEL_TIER_INJECT=off run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"architect"}}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "savia_resolve_model prefers tiers.<frontend> and falls back to legacy" {
  mkdir -p "$TMP/home/.savia"; cp "$PREFS" "$TMP/home/.savia/preferences.yaml"
  run env HOME="$TMP/home" bash -c 'source scripts/savia-env.sh >/dev/null 2>&1
    unset SAVIA_MODEL_HEAVY SAVIA_MODEL_MID
    SAVIA_FRONTEND=opencode; echo "$(savia_resolve_model heavy) $(savia_resolve_model mid)"
    SAVIA_FRONTEND=claude;   echo "$(savia_resolve_model heavy) $(savia_resolve_model fast)"'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "oc/heavy legacy/mid" ]
  [ "${lines[1]}" = "opus haiku" ]
}

@test "retired sync-model-tiers.sh refuses to rewrite sources" {
  run bash scripts/sync-model-tiers.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"retirado"* ]]
}

@test "safety: lint and hook run under set -uo pipefail" {
  grep -q '^set -uo pipefail' "$LINT"
  grep -q '^set -uo pipefail' "$HOOK"
}

@test "edge: empty stdin and null tool_input are ignored" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run hook '{"tool_name":"Agent","tool_input":null}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "edge: nonexistent prefs and empty tiers block fall back to defaults" {
  printf 'tiers:\n' > "$PREFS"
  run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"tech-writer"}}'
  [[ "$output" == *'"model": "haiku"'* ]]
  SAVIA_PREFS_FILE="$TMP/nonexistent.yaml" run hook '{"tool_name":"Agent","tool_input":{"subagent_type":"architect"}}'
  [[ "$output" == *'"model": "opus"'* ]]
}

@test "edge: lint on an empty project root passes (zero sources)" {
  mkdir -p "$TMP/r"
  PROJECT_ROOT="$TMP/r" run bash "$LINT"
  [ "$status" -eq 0 ]
}
