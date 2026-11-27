#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para frontend-test-runner: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/frontend-test-runner.md"
D="contracts/capabilities/agent.frontend-test-runner.yaml"
E="tests/evals/frontend-test-runner"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/frontend-test-runner.md"
}

@test "[frontend-test-runner] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[frontend-test-runner] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"frontend-test-runner.md"* ]]
}

@test "[frontend-test-runner] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[frontend-test-runner] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[frontend-test-runner] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"frontend-test-runner-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[frontend-test-runner] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/frontend-test-runner.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"frontend-test-runner\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

@test "[frontend-test-runner] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: frontend-test-runner$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[frontend-test-runner] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[frontend-test-runner] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[frontend-test-runner] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[frontend-test-runner] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[frontend-test-runner] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}

# --- Comportamiento ejecutado: el hook real .claude/hooks/responsibility-judge.sh ---
# PreToolUse Edit|Write (registrado en .claude/settings.json). Es lo que impide al
# agente "arreglar" un test frontend que falla saltandolo (xit/xtest) o bajando
# TEST_COVERAGE_MIN_PERCENT. Ref: tests/bats/l4-exec-lib.bash. Sin modelo.
load l4-exec-lib
J=".claude/hooks/responsibility-judge.sh"

_judge_mutant() { # <expresion-sed> -> copia mutada; savia-env.sh se resuelve via ../../scripts
  mkdir -p "$TMP/r"
  [ -e "$TMP/r/scripts" ] || ln -s "$PWD/scripts" "$TMP/r/scripts"
  l4_exec_mutant "$J" "$1" "$TMP/r/.claude/hooks/responsibility-judge.sh"
}

@test "[frontend-test-runner] golden ejecutado: test frontend normal pasa, xit se bloquea" {
  l4_exec_cases "$E/golden.json"
}

@test "[frontend-test-runner] edge ejecutado: Edit con new_string tambien se juzga" {
  l4_exec_cases "$E/edge.json"
}

@test "[frontend-test-runner] adversarial ejecutado: una orden de apagado dentro del contenido es dato" {
  l4_exec_cases "$E/adversarial.json"
}

@test "[frontend-test-runner] bypass ejecutado: bajar TEST_COVERAGE_MIN_PERCENT se bloquea" {
  l4_exec_cases "$E/bypass.json"
}

@test "[frontend-test-runner] mutante: S-02 sin xit, golden.json falla" {
  _judge_mutant 's/\|\^\\s\*xit\\b//'
  run l4_exec_cases "$E/golden.json" "$J=$TMP/r/.claude/hooks/responsibility-judge.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-exec-xit-blocked"* ]]
}

@test "[frontend-test-runner] mutante: solo se lee content y no new_string, edge.json falla" {
  _judge_mutant "s/p\.get\('content', p\.get\('new_string', ''\)\)/p.get('content', '')/"
  run l4_exec_cases "$E/edge.json" "$J=$TMP/r/.claude/hooks/responsibility-judge.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-exec-edit-new-string-judged"* ]]
}

@test "[frontend-test-runner] mutante: el contenido puede apagar el juez, adversarial.json falla" {
  _judge_mutant 's/^PATTERN=""$/echo "$CONTENT" | grep -q "RESPONSIBILITY_JUDGE_ENABLED=false" \&\& exit 0\nPATTERN=""/'
  run l4_exec_cases "$E/adversarial.json" "$J=$TMP/r/.claude/hooks/responsibility-judge.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-exec-disable-in-content-is-data"* ]]
}

@test "[frontend-test-runner] mutante: S-05 sin min_percent, bypass.json falla" {
  _judge_mutant 's/\(coverage_min\|min_percent\|min_coverage\)/(coverage_min|min_coverage)/'
  run l4_exec_cases "$E/bypass.json" "$J=$TMP/r/.claude/hooks/responsibility-judge.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-exec-coverage-min-lowered"* ]]
}
