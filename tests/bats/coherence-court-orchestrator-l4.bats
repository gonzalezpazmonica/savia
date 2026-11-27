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

# --- Comportamiento (aggregate): se ejecuta scripts/coherence-court.sh y se compara su salida ---
# Ejecutor: tests/bats/l4-script-cases-lib.bash. Sin modelo: solo el script determinista.
load l4-script-cases-lib
S_BEHAVIOR="scripts/coherence-court.sh"

@test "[coherence-court-orchestrator] behavior: entre 3 y 5 casos ejecutables y al menos uno negativo" {
  l4_script_cases_shape "$E"
}

@test "[coherence-court-orchestrator] behavior golden: score 90 es pass; gate 69 cierra la puerta humana" {
  l4_script_cases "$E/golden.json" "$S_BEHAVIOR" "$TMP"
}

@test "[coherence-court-orchestrator] behavior edge: score 70 es conditional (exit 2), no fail" {
  l4_script_cases "$E/edge.json" "$S_BEHAVIOR" "$TMP"
}

@test "[coherence-court-orchestrator] behavior adversarial: un contador con subindice no ejecuta codigo" {
  l4_script_cases "$E/adversarial.json" "$S_BEHAVIOR" "$TMP"
}

@test "[coherence-court-orchestrator] behavior bypass: sin premisas el check falla y para el flujo" {
  l4_script_cases "$E/bypass.json" "$S_BEHAVIOR" "$TMP"
}

@test "[coherence-court-orchestrator] mutante: umbral conditional 70 -> 71, edge falla" {
  sed 's/COHERENCE_SCORE_CONDITIONAL:-70/COHERENCE_SCORE_CONDITIONAL:-71/' "$S_BEHAVIOR" > "$TMP/cc.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cc.sh"
  run l4_script_cases "$E/edge.json" "$TMP/cc.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-gate-70-conditional"* ]]
}

@test "[coherence-court-orchestrator] mutante: sin validar C, adversarial falla" {
  sed 's/_require_uint C "\$c"; //' "$S_BEHAVIOR" > "$TMP/cc.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cc.sh"
  run l4_script_cases "$E/adversarial.json" "$TMP/cc.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-score-subscript-injection"* ]]
}

@test "[coherence-court-orchestrator] mutante: check acepta 0 premisas, bypass falla" {
  sed 's/if \[\[ "\$n" -lt 1 \]\]/if [[ "$n" -lt 0 ]]/' "$S_BEHAVIOR" > "$TMP/cc.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cc.sh"
  run l4_script_cases "$E/bypass.json" "$TMP/cc.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-check-without-premises"* ]]
}
