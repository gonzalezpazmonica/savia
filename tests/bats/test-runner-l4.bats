#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para test-runner: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/test-runner.md"
D="contracts/capabilities/agent.test-runner.yaml"
E="tests/evals/test-runner"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/test-runner.md"
}

@test "[test-runner] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[test-runner] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"test-runner.md"* ]]
}

@test "[test-runner] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[test-runner] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[test-runner] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"test-runner-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[test-runner] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/test-runner.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"test-runner\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

@test "[test-runner] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: test-runner$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[test-runner] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[test-runner] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[test-runner] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[test-runner] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[test-runner] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}

# --- Comportamiento ejecutado: el ratchet real scripts/test-coverage-ratchet.sh ---
# (negative_tests del descriptor: "test coverage ratchet"). Ref: tests/bats/l4-exec-lib.bash.
# Sin modelo. La lista de hooks criticos y el conf viven en el directorio temporal del case.
load l4-exec-lib
R="scripts/test-coverage-ratchet.sh"

_ratchet_mutant() { # <expresion-sed> -> copia mutada con tests/ del repo al lado (el script mide $ROOT/tests)
  mkdir -p "$TMP/r"
  [ -e "$TMP/r/tests" ] || ln -s "$PWD/tests" "$TMP/r/tests"
  l4_exec_mutant "$R" "$1" "$TMP/r/scripts/test-coverage-ratchet.sh"
}

@test "[test-runner] golden ejecutado: 100% pasa, un hook sin test hace fallar --ci" {
  l4_exec_cases "$E/golden.json"
}

@test "[test-runner] edge ejecutado: lista de hooks vacia es fallo cerrado, no 100%" {
  l4_exec_cases "$E/edge.json"
}

@test "[test-runner] adversarial ejecutado: el conf es dato, no se ejecuta" {
  l4_exec_cases "$E/adversarial.json"
}

@test "[test-runner] bypass ejecutado: el umbral no baja por flag" {
  l4_exec_cases "$E/bypass.json"
}

@test "[test-runner] mutante: --ci ya no compara con el umbral, golden.json falla" {
  _ratchet_mutant 's/\(\( ratio < THRESHOLD \)\)/(( ratio < 0 ))/'
  run l4_exec_cases "$E/golden.json" "$R=$TMP/r/scripts/test-coverage-ratchet.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-exec-uncovered-hook-fails-ci"* ]]
}

@test "[test-runner] mutante: sin el fallo cerrado de lista vacia, edge.json falla" {
  _ratchet_mutant '/no lista ningún hook crítico/d'
  run l4_exec_cases "$E/edge.json" "$R=$TMP/r/scripts/test-coverage-ratchet.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-exec-empty-list-fails-closed"* ]]
}

@test "[test-runner] mutante: el conf se carga con source, adversarial.json falla" {
  _ratchet_mutant 's/^  persisted=\$\(sed -n .*$/  source "$CONF_FILE"; persisted="$THRESHOLD"/'
  run l4_exec_cases "$E/adversarial.json" "$R=$TMP/r/scripts/test-coverage-ratchet.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-exec-conf-not-executed"* ]]
}

@test "[test-runner] mutante: --threshold puede bajar el umbral, bypass.json falla" {
  _ratchet_mutant '/RN-01 — el umbral no baja por flag/{n;s/exit 2/:/}'
  run l4_exec_cases "$E/bypass.json" "$R=$TMP/r/scripts/test-coverage-ratchet.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-exec-threshold-not-lowered"* ]]
}
