#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para dev-orchestrator: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/dev-orchestrator.md"
D="contracts/capabilities/agent.dev-orchestrator.yaml"
E="tests/evals/dev-orchestrator"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/dev-orchestrator.md"
}

@test "[dev-orchestrator] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[dev-orchestrator] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"dev-orchestrator.md"* ]]
}

@test "[dev-orchestrator] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[dev-orchestrator] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[dev-orchestrator] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"dev-orchestrator-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[dev-orchestrator] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/dev-orchestrator.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"dev-orchestrator\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

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

# --- Comportamiento (aggregate): se ejecuta scripts/savia-orchestrator-helper.sh y se compara su salida ---
# Ejecutor: tests/bats/l4-exec-lib.bash (l4_exec_eval.py). Sin modelo: solo el script determinista.
load l4-exec-lib
S_BEHAVIOR="scripts/savia-orchestrator-helper.sh"

@test "[dev-orchestrator] behavior: entre 3 y 5 casos ejecutables y al menos uno negativo" {
  l4_exec_shape "$E"
}

@test "[dev-orchestrator] behavior golden: inline-prompt quita el frontmatter; fan-out solo si el entorno lo declara" {
  l4_exec_cases "$E/golden.json"
}

@test "[dev-orchestrator] behavior edge: sin savia-env.sh el modo es single-shot (peor caso)" {
  l4_exec_cases "$E/edge.json"
}

@test "[dev-orchestrator] behavior adversarial: la salida inline con JSON incrustado queda como dato en el sobre" {
  l4_exec_cases "$E/adversarial.json"
}

@test "[dev-orchestrator] behavior bypass: agente inexistente => exit 2, nada que inyectar" {
  l4_exec_cases "$E/bypass.json"
}

@test "[dev-orchestrator] mutante: el frontmatter se filtra al prompt, golden falla" {
  sed 's/c >= 2  { print }/c >= 1  { print }/' "$S_BEHAVIOR" > "$TMP/oh.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/oh.sh"
  run l4_exec_cases "$E/golden.json" "$S_BEHAVIOR=$TMP/oh.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-inline-strips-frontmatter"* ]]
}

@test "[dev-orchestrator] mutante: sin entorno se supone fan-out, edge falla" {
  sed 's/# No env script available — assume worst case (no Task tool)/&\n    echo "fan-out"; return/' "$S_BEHAVIOR" > "$TMP/oh.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/oh.sh"
  run l4_exec_cases "$E/edge.json" "$S_BEHAVIOR=$TMP/oh.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-mode-without-env-single-shot"* ]]
}

@test "[dev-orchestrator] mutante: sobre sin escape JSON, adversarial falla" {
  sed 's/print(json.dumps({/print("{\\"agent\\": \\"%s\\", \\"mode\\": \\"single-shot\\", \\"result\\": \\"%s\\"}" % (agent, raw)); sys.exit(0); print(json.dumps({/' "$S_BEHAVIOR" > "$TMP/oh.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/oh.sh"
  run l4_exec_cases "$E/adversarial.json" "$S_BEHAVIOR=$TMP/oh.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-wrap-embedded-json-is-data"* ]]
}

@test "[dev-orchestrator] mutante: agente inexistente devuelve 0, bypass falla" {
  sed '0,/    return 2/s//    return 0/' "$S_BEHAVIOR" > "$TMP/oh.sh"
  ! cmp -s "$S_BEHAVIOR" "$TMP/oh.sh"
  run l4_exec_cases "$E/bypass.json" "$S_BEHAVIOR=$TMP/oh.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-unknown-agent"* ]]
}
