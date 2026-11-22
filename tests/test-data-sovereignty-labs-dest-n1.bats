#!/usr/bin/env bats
# Ref: docs/rules/domain/data-sovereignty.md
# Tests de la orquestadora (TDD cruzado: se suman a los de Codex en
# test-data-sovereignty-labs-dest.bats). La exención de Labs/cúpulas nunca
# alcanza un destino N1 aunque la ruta contenga un segmento labs/ o vaults/.

setup() {
  local src="${BATS_TEST_DIRNAME}/.."
  HOOK="$src/.claude/hooks/data-sovereignty-gate.sh"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/workspace"
  export SAVIA_WORKSPACE_DIR="$CLAUDE_PROJECT_DIR"
  export SAVIA_HOOK_PROFILE=security SAVIA_SHIELD_ENABLED=true
  CONTENT="Contenido sintético de investigación para comprobar la clasificación de confidencialidad sin datos personales ni credenciales."
  mkdir -p "$CLAUDE_PROJECT_DIR/"{scripts,config,output} "$BATS_TEST_TMPDIR/bin"
  cp "$src/scripts/sovereignty-decide.sh" "$CLAUDE_PROJECT_DIR/scripts/"
  cp "$src/config/sovereignty-thresholds.yaml" "$CLAUDE_PROJECT_DIR/config/"
  cat > "$CLAUDE_PROJECT_DIR/scripts/sovereignty-classify.sh" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
echo '{"label":"confidential","confidence":0.99,"deterministic_matches":[]}'
STUB
  chmod +x "$CLAUDE_PROJECT_DIR/scripts/"*.sh
  printf '#!/usr/bin/env bash\nexit 7\n' > "$BATS_TEST_TMPDIR/bin/curl"
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

write_content() {
  jq -nc --arg path "$1" --arg content "$CONTENT" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' > "$BATS_TEST_TMPDIR/in.json"
  run bash "$HOOK" < "$BATS_TEST_TMPDIR/in.json"
}

@test "bloqueo (BLOCK): docs/labs/ del repo público sigue bloqueando CONFIDENTIAL" {
  write_content /x/savia/docs/labs/a.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"classifier_confidential_high_confidence"* ]]
}

@test "bloqueo (BLOCK): scripts/vaults/ del repo público sigue bloqueando CONFIDENTIAL" {
  write_content /x/savia/scripts/vaults/a.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"classifier_confidential_high_confidence"* ]]
}

@test "permitido: la misma escritura en Labs privado pasa con aviso" {
  write_content /x/vaults/SaviaLabs/labs/research/a.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"destino protegido, permitido"* ]]
}
