#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para commit-guardian: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/commit-guardian.md"
D="contracts/capabilities/agent.commit-guardian.yaml"
E="tests/evals/commit-guardian"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/commit-guardian.md"
}

@test "[commit-guardian] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[commit-guardian] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit-guardian.md"* ]]
}

@test "[commit-guardian] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[commit-guardian] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[commit-guardian] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"commit-guardian-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[commit-guardian] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/commit-guardian.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"commit-guardian\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

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

# --- Comportamiento (aggregate): se ejecuta el hook del agente (.claude/hooks/block-force-push.sh) ---
# Ejecutor: tests/bats/l4-script-cases-lib.bash. Sin modelo: el hook recibe el payload PreToolUse real.
load l4-script-cases-lib
S_BEHAVIOR=".claude/hooks/block-force-push.sh"

@test "[commit-guardian] behavior: entre 3 y 5 casos ejecutables y al menos uno negativo" {
  l4_script_cases_shape "$E"
}

@test "[commit-guardian] behavior: el hook ejecutado es el que declara el frontmatter del agente" {
  grep -qF "command: \"$S_BEHAVIOR\"" .claude/agents/commit-guardian.md
}

@test "[commit-guardian] behavior golden: push a rama agent/* pasa; push --force se bloquea" {
  l4_script_cases "$E/golden.json" "$S_BEHAVIOR" "$TMP"
}

@test "[commit-guardian] behavior edge: --force-with-lease a rama no-main pasa" {
  l4_script_cases "$E/edge.json" "$S_BEHAVIOR" "$TMP"
}

@test "[commit-guardian] behavior adversarial: ruta absoluta, -C y -f combinado siguen bloqueados" {
  l4_script_cases "$E/adversarial.json" "$S_BEHAVIOR" "$TMP"
}

@test "[commit-guardian] behavior bypass: reset --hard dentro de bash -c se bloquea" {
  l4_script_cases "$E/bypass.json" "$S_BEHAVIOR" "$TMP"
}

@test "[commit-guardian] mutante: el force push deja de bloquear, golden falla" {
  l4_hook_copy "$S_BEHAVIOR" "$TMP/hooks"
  sed -i 's/^  IS_BARE_FORCE=yes$/  IS_BARE_FORCE=no/' "$TMP/hooks/block-force-push.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/hooks/block-force-push.sh"
  run l4_script_cases "$E/golden.json" "$TMP/hooks/block-force-push.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-force-push-blocked"* ]]
}

@test "[commit-guardian] mutante: el lease se trata como force, edge falla" {
  l4_hook_copy "$S_BEHAVIOR" "$TMP/hooks"
  sed -i 's/^  IS_FORCE_WITH_LEASE=yes$/  IS_BARE_FORCE=yes/' "$TMP/hooks/block-force-push.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/hooks/block-force-push.sh"
  run l4_script_cases "$E/edge.json" "$TMP/hooks/block-force-push.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-lease-feature-allowed"* ]]
}

@test "[commit-guardian] mutante: git solo al principio de linea, adversarial falla" {
  l4_hook_copy "$S_BEHAVIOR" "$TMP/hooks"
  sed -i 's|(\\\\\|\[^\[:space:\]\]\*/)?git(|git(|' "$TMP/hooks/block-force-push.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/hooks/block-force-push.sh"
  run l4_script_cases "$E/adversarial.json" "$TMP/hooks/block-force-push.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-absolute-git-dash-c-force"* ]]
}

@test "[commit-guardian] mutante: sin el bloqueo de reset --hard, bypass falla" {
  l4_hook_copy "$S_BEHAVIOR" "$TMP/hooks"
  sed -i 's/reset\[\[:space:\]\]+--hard/reset[[:space:]]+--hardx/' "$TMP/hooks/block-force-push.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/hooks/block-force-push.sh"
  run l4_script_cases "$E/bypass.json" "$TMP/hooks/block-force-push.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-reset-hard-in-bash-c"* ]]
}
