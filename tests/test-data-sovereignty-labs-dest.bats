#!/usr/bin/env bats
# Ref: docs/rules/domain/data-sovereignty.md
# TDD cruzado: solo tests; las dos escrituras CONFIDENTIAL protegidas son RED en main.
# Estrategia: permitir confidencialidad en Labs/cúpulas con auditoría; mantener
# bloqueos públicos/no protegidos, normalización de rutas y regex de secretos.

setup() {
  local src="${BATS_TEST_DIRNAME}/.."
  HOOK="$src/.claude/hooks/data-sovereignty-gate.sh"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/workspace"
  export SAVIA_WORKSPACE_DIR="$CLAUDE_PROJECT_DIR"
  export SAVIA_HOOK_PROFILE=security SAVIA_SHIELD_ENABLED=true
  export CLASSIFIER_CALLS="$BATS_TEST_TMPDIR/classifier-calls.jsonl"
  export TEST_CLASSIFIER_LABEL=confidential
  AUDIT_LOG="$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
  CONTENT="Contenido sintético de investigación para comprobar la clasificación de confidencialidad sin datos personales ni credenciales."
  mkdir -p "$CLAUDE_PROJECT_DIR/"{scripts,config,output} "$BATS_TEST_TMPDIR/bin"

  # Inyección existente: el gate busca scripts bajo CLAUDE_PROJECT_DIR, no en
  # PATH. Solo se dobla classify; decide y su política son los reales del repo.
  cp "$src/scripts/sovereignty-decide.sh" "$CLAUDE_PROJECT_DIR/scripts/"
  cp "$src/config/sovereignty-thresholds.yaml" "$CLAUDE_PROJECT_DIR/config/"
  cat > "$CLAUDE_PROJECT_DIR/scripts/sovereignty-classify.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == "--context-path" ]]
content=$(cat)
jq -nc --arg path "$2" --arg content "$content" \
  '{path:$path,content:$content}' >> "$CLASSIFIER_CALLS"
jq -nc --arg label "$TEST_CLASSIFIER_LABEL" \
  '{label:$label,confidence:0.99,deterministic_matches:[]}'
STUB
  chmod +x "$CLAUDE_PROJECT_DIR/scripts/"*.sh

  # Forzar fallback sin depender de puertos libres, daemon, red o LLM local.
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
exit 7
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

write_content() {
  local dest="$1" content="${2:-$CONTENT}"
  jq -nc --arg path "$dest" --arg content "$content" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:$content}}' \
    > "$BATS_TEST_TMPDIR/input.json"
  run bash "$HOOK" < "$BATS_TEST_TMPDIR/input.json"
}

assert_classified() {
  local normalized="$1"
  # Impide un falso verde por skip temprano, contenido corto o stub no ejecutado.
  jq -se --arg path "$normalized" --arg content "$CONTENT" \
    'length == 1 and .[0].path == $path and .[0].content == $content' \
    "$CLASSIFIER_CALLS"
}

assert_audited() {
  local dest="$1" verdict="$2" reason="$3"
  [ -s "$AUDIT_LOG" ]
  jq -se --arg dest "$dest" --arg verdict "$verdict" --arg reason "$reason" '
    any(.[]; .file == $dest and (.ts | type == "string" and length > 0)
      and .verdict == $verdict and .reason == $reason)
  ' "$AUDIT_LOG"
}

assert_allowed_and_audited() {
  local dest="$1"
  [ "$status" -eq 0 ]
  assert_classified "$dest"
  [ -s "$AUDIT_LOG" ]
  # No fijar el nombre de un override aún no implementado; sí exigir una
  # decisión explícita no bloqueante para este fichero y timestamp de auditoría.
  jq -se --arg dest "$dest" '
    any(.[]; .file == $dest and (.ts | type == "string" and length > 0)
      and (.verdict == "ALLOW" or .verdict == "WARN"))
    and all(.[]; .verdict != "BLOCK" and .verdict != "BLOCKED")
  ' "$AUDIT_LOG"
}

assert_confidential_blocked() {
  local dest="$1" normalized="${2:-$1}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"classifier_confidential_high_confidence"* ]]
  assert_classified "$normalized"
  assert_audited "$dest" BLOCKED classifier_confidential_high_confidence
}

assert_secret_blocked() {
  local dest="$1" content="$2" reason="$3"
  write_content "$dest" "$content"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO [fallback]: $reason"* ]]
  assert_audited "$dest" BLOCKED "$reason"
  # El secreto debe detectarse ANTES del clasificador, incluso si este permite.
  [ ! -e "$CLASSIFIER_CALLS" ]
}

@test "CONFIDENTIAL de alta confianza se permite y audita en cúpula SaviaLabs" {
  write_content /x/vaults/SaviaLabs/labs/research/a.md
  assert_allowed_and_audited /x/vaults/SaviaLabs/labs/research/a.md
}

@test "CONFIDENTIAL de alta confianza se permite y audita en labs de un worktree" {
  write_content /x/labs-wt-foo/labs/research/a.md
  assert_allowed_and_audited /x/labs-wt-foo/labs/research/a.md
}

@test "bloqueo (BLOCK): el mismo CONFIDENTIAL sigue bloqueado en docs N1" {
  write_content /x/savia/docs/a.md
  assert_confidential_blocked /x/savia/docs/a.md
}

@test "bloqueo (BLOCK): el mismo CONFIDENTIAL sigue bloqueado en n4 no protegido" {
  write_content /x/savia/foo.md
  assert_confidential_blocked /x/savia/foo.md
}

@test "edge boundary traversal: docs/../../vaults se normaliza antes de clasificar" {
  # PUBLIC aísla la normalización (ya existente) del permiso pendiente para
  # CONFIDENTIAL, cubierto arriba. No fija como contrato el bloqueo erróneo.
  export TEST_CLASSIFIER_LABEL=public
  write_content /x/savia/docs/../../vaults/a.md
  [ "$status" -eq 0 ]
  assert_classified /x/vaults/a.md
}

@test "bloqueo (BLOCK) boundary: docs/labs-notes.md no es un segmento labs protegido" {
  write_content /x/savia/docs/labs-notes.md
  assert_confidential_blocked /x/savia/docs/labs-notes.md
}

@test "bloqueo (BLOCK) traversal: labs/../docs se trata como docs y bloquea" {
  write_content /x/savia/labs/../docs/a.md
  assert_confidential_blocked /x/savia/labs/../docs/a.md /x/savia/docs/a.md
}

@test "bloqueo (BLOCK) boundary: el prefijo labs-wt sin segmento labs no protege" {
  write_content /x/labs-wt-foo/research/a.md
  assert_confidential_blocked /x/labs-wt-foo/research/a.md
}

@test "bloqueo (BLOCK): token GitHub sigue bloqueado en cúpula aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  local token
  token=$(printf 'ghp_%036d' 0) # sintético: forma válida para la regex, sin secreto real
  assert_secret_blocked /x/vaults/SaviaLabs/labs/research/a.md "$token" github_token
}

@test "bloqueo (BLOCK): token GitHub sigue bloqueado en Labs aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  local token
  token=$(printf 'ghp_%036d' 0)
  assert_secret_blocked /x/labs-wt-foo/labs/research/a.md "$token" github_token
}

@test "bloqueo (BLOCK): clave privada sigue bloqueada en cúpula aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  local key
  key=$(printf -- '-----BEGIN %s KEY-----\nsynthetic-fixture\n-----END %s KEY-----' PRIVATE PRIVATE)
  assert_secret_blocked /x/vaults/SaviaLabs/labs/research/a.md "$key" private_key
}

@test "bloqueo (BLOCK): clave privada sigue bloqueada en Labs aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  local key
  key=$(printf -- '-----BEGIN %s KEY-----\nsynthetic-fixture\n-----END %s KEY-----' PRIVATE PRIVATE)
  assert_secret_blocked /x/labs-wt-foo/labs/research/a.md "$key" private_key
}

@test "bloqueo (BLOCK): cadena de conexión sigue bloqueada en cúpula aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  assert_secret_blocked /x/vaults/SaviaLabs/labs/research/a.md \
    'Server=db.example.invalid;Database=fixture;Password=synthetic-only' connection_string
}

@test "bloqueo (BLOCK): cadena de conexión sigue bloqueada en Labs aunque classify permita" {
  export TEST_CLASSIFIER_LABEL=public
  assert_secret_blocked /x/labs-wt-foo/labs/research/a.md \
    'Server=db.example.invalid;Database=fixture;Password=synthetic-only' connection_string
}
