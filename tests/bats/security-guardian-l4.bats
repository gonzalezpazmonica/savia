#!/usr/bin/env bats
# SE-387 Slice D — eval L4 para security-guardian: smoke/golden/edge/adversarial/bypass
A=".opencode/agents/security-guardian.md"
D="contracts/capabilities/agent.security-guardian.yaml"
E="tests/evals/security-guardian"

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
  sed -E "s/^model_tier:.*/$1/" "$A" > "$TMP/.opencode/agents/security-guardian.md"
}

@test "[security-guardian] tier: model_tier es neutro y no hay model: de proveedor" {
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
  ! grep -qE "^model:" "$A"
}

@test "[security-guardian] reject: model: de proveedor en el agente falla el lint de tiers" {
  _fixture_agent "model: vendor\/model-x"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"security-guardian.md"* ]]
}

@test "[security-guardian] invalid: model_tier fuera de heavy|mid|fast falla el lint" {
  _fixture_agent "model_tier: ultra"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"model_tier inválido 'ultra'"* ]]
}

@test "[security-guardian] empty: model_tier vacio falla el lint" {
  _fixture_agent "model_tier:"
  run env PROJECT_ROOT="$TMP" bash scripts/model-tier-lint.sh
  [ "$status" -ne 0 ]
}

@test "[security-guardian] nonexistent: agente inexistente => sin inyeccion (null output)" {
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"security-guardian-nonexistent\"}}' | CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[security-guardian] zero-config: sin prefs locales se inyecta el default del tier" {
  mkdir -p "$TMP/.claude/agents" && cp "$A" "$TMP/.claude/agents/security-guardian.md"
  tier=$(sed -nE 's/^model_tier: (heavy|mid|fast)$/\1/p' "$A")
  declare -A def=([heavy]=opus [mid]=sonnet [fast]=haiku)
  run bash -c "printf '%s' '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"security-guardian\"}}' | SAVIA_PREFS_FILE='$TMP/none.yaml' CLAUDE_PROJECT_DIR='$TMP' bash .claude/hooks/model-tier-inject.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"model\": \"${def[$tier]}\""* ]]
}

@test "[security-guardian] smoke: agente existe con frontmatter completo" {
  [ -f "$A" ]
  grep -q "^name: security-guardian$" "$A"
  grep -q "^permission_level: L4" "$A"
  grep -qE "^model_tier: (heavy|mid|fast)$" "$A"
}

@test "[security-guardian] golden: descriptor con cadena laws->enforcement->receipt" {
  [ -f "$D" ]
  grep -q "laws:" "$D"
  grep -q "enforcement:" "$D"
  grep -q "receipt:" "$D"
  grep -q "LAW-" "$D"
}

@test "[security-guardian] edge: fixtures de casos borde presentes y validos" {
  jq -e '.cases | length >= 3' "$E/edge.json" >/dev/null
}

@test "[security-guardian] adversarial: inyeccion tratada como dato (origin untrusted)" {
  jq -e '.cases | length >= 2' "$E/adversarial.json" >/dev/null
}

@test "[security-guardian] bypass: intentos sin approval/gate => BLOCK (fixtures exigentes)" {
  jq -e '.cases | length >= 3' "$E/bypass.json" >/dev/null
  jq -e '[.cases[].expected] | any(contains("BLOCK"))' "$E/bypass.json" >/dev/null
}

@test "[security-guardian] regression: golden fixture versionado" {
  jq -e '.scenario == "golden"' "$E/golden.json" >/dev/null
}

# --- Comportamiento ejecutado: hooks reales block-credential-leak y block-pat-file-write ---
# (enforcement del descriptor). Ref: tests/bats/l4-exec-lib.bash. Sin modelo.
# Las credenciales de los fixtures se trocean en partes: el fichero no contiene ninguna entera.
load l4-exec-lib
HC=".claude/hooks/block-credential-leak.sh"
HP=".claude/hooks/block-pat-file-write.sh"

@test "[security-guardian] golden ejecutado: clave AWS bloqueada, orden limpia permitida" {
  l4_exec_cases "$E/golden.json"
}

@test "[security-guardian] edge ejecutado: un hash git de 40 hex no es un PAT" {
  l4_exec_cases "$E/edge.json"
}

@test "[security-guardian] adversarial ejecutado: clave privada en un heredoc se bloquea" {
  l4_exec_cases "$E/adversarial.json"
}

@test "[security-guardian] bypass ejecutado: escribir un fichero -pat versionado se bloquea" {
  l4_exec_cases "$E/bypass.json"
}

@test "[security-guardian] mutante: clave AWS deja de bloquear, golden.json falla" {
  l4_exec_mutant "$HC" '/AWS Access Key detectada/{n;s/exit 2/exit 0/}' "$TMP/m/hook.sh"
  run l4_exec_cases "$E/golden.json" "$HC=$TMP/m/hook.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"golden-exec-aws-key-blocked"* ]]
}

@test "[security-guardian] mutante: sin la excepcion de hash git, edge.json falla" {
  l4_exec_mutant "$HC" 's/\[a-f0-9\]\{40\}/[a-f0-9]{41}/' "$TMP/m/hook.sh"
  run l4_exec_cases "$E/edge.json" "$HC=$TMP/m/hook.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edge-exec-git-hash-not-pat"* ]]
}

@test "[security-guardian] mutante: clave privada deja de bloquear, adversarial.json falla" {
  l4_exec_mutant "$HC" '/Private key detectada/{n;s/exit 2/exit 0/}' "$TMP/m/hook.sh"
  run l4_exec_cases "$E/adversarial.json" "$HC=$TMP/m/hook.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"adv-exec-private-key-heredoc"* ]]
}

@test "[security-guardian] mutante: la escritura a ruta -pat no bloquea, bypass.json falla" {
  l4_exec_mutant "$HP" '/^EOF$/{n;s/exit 2/exit 0/}' "$TMP/m/pat.sh"
  run l4_exec_cases "$E/bypass.json" "$HP=$TMP/m/pat.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bypass-exec-pat-path-write"* ]]
}
