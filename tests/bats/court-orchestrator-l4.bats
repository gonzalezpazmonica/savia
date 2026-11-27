#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para court-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/court-orchestrator.md"
D="contracts/capabilities/agent.court-orchestrator.yaml"
E="tests/evals/court-orchestrator"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/court-orchestrator.md"
}

@test "[court-orchestrator] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[court-orchestrator] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"court-orchestrator.md"* ]]
}

@test "[court-orchestrator] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[court-orchestrator] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[court-orchestrator] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"court-orchestrator-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[court-orchestrator] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/court-orchestrator.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"court-orchestrator\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

@test "[court-orchestrator] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: court-orchestrator$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[court-orchestrator] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[court-orchestrator] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[court-orchestrator] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[court-orchestrator] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[court-orchestrator] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}

# --- Comportamiento (aggregate): se ejecuta scripts/court-review.sh y se compara su salida ---
# Ejecutor: tests/bats/l4-script-cases-lib.bash. Sin modelo: solo el script determinista.
load l4-script-cases-lib
S_BEHAVIOR="scripts/court-review.sh"

@test "[court-orchestrator] behavior: entre 3 y 5 casos ejecutables y al menos uno negativo" {
  l4_script_cases_shape "$E"
}

@test "[court-orchestrator] behavior golden: sin hallazgos 100 pass; un critico y dos medios 69 fail" {
  l4_script_cases "$E/golden.json" "$S_BEHAVIOR" "$TMP"
}

@test "[court-orchestrator] behavior edge: 89 es conditional, no pass" {
  l4_script_cases "$E/edge.json" "$S_BEHAVIOR" "$TMP"
}

@test "[court-orchestrator] behavior adversarial: hallazgos inflados no dan score negativo" {
  l4_script_cases "$E/adversarial.json" "$S_BEHAVIOR" "$TMP"
}

@test "[court-orchestrator] behavior bypass: una segunda ronda de fix en la misma review falla" {
  l4_script_cases "$E/bypass.json" "$S_BEHAVIOR" "$TMP"
}

@test "[court-orchestrator] mutante: umbral conditional 70 -> 69, golden falla" {
  sed 's/COURT_SCORE_CONDITIONAL:-70/COURT_SCORE_CONDITIONAL:-69/' "$S_BEHAVIOR" > "$TMP/cr.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cr.sh"
  run l4_script_cases "$E/golden.json" "$TMP/cr.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-score-critical-fail"* ]]
}

@test "[court-orchestrator] mutante: sin suelo en 0, adversarial falla" {
  sed 's/\[\[ "\$score" -lt 0 \]\] && score=0/:/' "$S_BEHAVIOR" > "$TMP/cr.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cr.sh"
  run l4_script_cases "$E/adversarial.json" "$TMP/cr.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-score-floor-zero"* ]]
}

@test "[court-orchestrator] mutante: COURT_MAX_FIX_ROUNDS 1 -> 2, bypass falla" {
  sed 's/COURT_MAX_FIX_ROUNDS:-1}/COURT_MAX_FIX_ROUNDS:-2}/' "$S_BEHAVIOR" > "$TMP/cr.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/cr.sh"
  run l4_script_cases "$E/bypass.json" "$TMP/cr.sh" "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-second-fix-round"* ]]
}
