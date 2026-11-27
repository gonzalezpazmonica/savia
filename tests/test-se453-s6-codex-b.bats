#!/usr/bin/env bats
# SE-453 S6 — regresión SH01: una coincidencia parcial no convierte PII en código.
# Ref: docs/evidence/graduacion-s27/SE-453.md y SE-453-S4-evidence-grading.md.
# Estrategia: ejecutar el hook real con JSON por stdin y daemon simulado, sin red.
# Positivos: entidades sintéticas conservan BLOCK; negativos: tokens completos
# conservan WARN. Bordes: prefijo, sufijo, subcadena, mezcla y destino no código.
# El corpus también se ejecuta contra isCodeToken TS; no simula el guard TS.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$ROOT/.opencode/hooks/data-sovereignty-gate.sh"
  TS_PATTERNS="$ROOT/.opencode/plugins/lib/sovereignty-patterns.ts"
  command -v jq >/dev/null
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/workspace"
  export SAVIA_WORKSPACE_DIR="$CLAUDE_PROJECT_DIR"
  export SAVIA_HOOK_PROFILE=ci SAVIA_SHIELD_ENABLED=true
  export SAVIA_PROVIDER=unknown SAVIA_PROJECT_SLUG=fixture
  export SH01_RESPONSE="$BATS_TEST_TMPDIR/response.json"
  export SH01_REQUEST="$BATS_TEST_TMPDIR/request.json"
  export SH01_CALLS="$BATS_TEST_TMPDIR/calls"
  AUDIT="$CLAUDE_PROJECT_DIR/output/data-sovereignty-audit.jsonl"
  mkdir -p "$CLAUDE_PROJECT_DIR" "$BATS_TEST_TMPDIR/bin"

  # Doble de transporte: exige POST y el payload completo del hook. Una URL
  # inesperada falla; nunca invoca curl real ni el daemon de la operadora.
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${*: -1}" in
  http://127.0.0.1:*/health)
    printf 'health\n' >> "$SH01_CALLS"
    printf '{"status":"ok"}\n'
    ;;
  *)
    method= url= payload=
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -X) method="$2"; shift 2 ;;
        -d) payload="$2"; shift 2 ;;
        http://127.0.0.1:*/gate) url="$1"; shift ;;
        *) shift ;;
      esac
    done
    [[ "$method" == POST && -n "$url" ]]
    printf '%s' "$payload" | jq -ce . > "$SH01_REQUEST"
    printf 'gate\n' >> "$SH01_CALLS"
    cat "$SH01_RESPONSE"
    ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Misma entrada en el hook y en la función TS. Datos exclusivamente sintéticos.
blocked_entities() {
  cat <<'JSON'
[
  {"id":"microsoft","type":"ORG","text":"Microsoft test-client confidential client"},
  {"id":"http","type":"ORG","text":"HTTP confidential test-client"},
  {"id":"chrome","type":"ORG","text":"Chrome confidential test-client"},
  {"id":"api","type":"CREDENTIAL","text":"API-prod-key-test-client"},
  {"id":"github","type":"URL","text":"github.com/test-org/secret-roadmap"},
  {"id":"from","type":"PERSON","text":"from Persona Prueba Sintetica"},
  {"id":"ip8080","type":"IP_ADDRESS","text":"10.23.45.67:8080"},
  {"id":"host8443","type":"URL","text":"db-prod.example.invalid:8443"},
  {"id":"numeric_suffix","type":"CREDENTIAL","text":"TEST_pwd=12345678"},
  {"id":"timeout_inside","type":"ORG","text":"test-client timeout=5 confidential"},
  {"id":"timeout_tail","type":"ORG","text":"timeout=5 confidential test-client"},
  {"id":"exception","type":"PERSON","text":"RuntimeError Persona Prueba Sintetica"},
  {"id":"casefold","type":"ORG","text":"mIcRoSoFt confidential test-client"}
]
JSON
}

legitimate_tokens() {
  printf '%s\n' '["Microsoft","HTTP","Chrome","github","JSON","Path","RuntimeError"]'
}

invoke_hook() {
  local entities="$1" dest="${2:-src/fixture.py}" tool="${3:-Write}"
  jq -nc --argjson entities "$entities" \
    '{verdict:"BLOCK",entities:$entities}' > "$SH01_RESPONSE"
  jq -nc --arg path "$dest" --arg tool "$tool" \
    --argjson entities "$entities" '
      {tool_name:$tool,tool_input:{file_path:$path}}
      | .tool_input[if $tool == "Edit" then "new_string" else "content" end]
        = ([$entities[].text] | join("; "))
    ' > "$BATS_TEST_TMPDIR/input.json"
  run bash "$HOOK" < "$BATS_TEST_TMPDIR/input.json"
  # No aceptar falsos verdes por skip temprano, fallback o doble sin ejecutar.
  [ -s "$SH01_REQUEST" ]
  cmp "$BATS_TEST_TMPDIR/input.json" "$SH01_REQUEST"
  [ "$(cat "$SH01_CALLS")" = $'health\ngate' ]
}

assert_blocked() {
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO [Savia Shield]: PII detectado"* ]]
  jq -se --slurpfile response "$SH01_RESPONSE" '
    length == 1 and .[0].verdict == "BLOCK" and .[0].layer == "gate"
    and .[0].entities == $response[0].entities
    and (.[0] | has("override") | not)
    and (.[0].ts | type == "string" and length > 0)
  ' "$AUDIT"
}

assert_warned() {
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING [Savia Shield SH01]"* ]]
  jq -se --slurpfile response "$SH01_RESPONSE" '
    length == 1 and .[0].override == "sh01_allowlist" and .[0].layer == "gate"
    and .[0].entities == $response[0].entities
    and (.[0].ts | type == "string" and length > 0)
  ' "$AUDIT"
}

assert_entity_blocked() {
  local entities
  entities=$(blocked_entities | jq -ce --arg id "$1" '[.[] | select(.id == $id) | del(.id)] | select(length == 1)')
  invoke_hook "$entities"
  assert_blocked
}

@test "S6 BLOCK: prefijo Microsoft no oculta una organización confidencial" {
  assert_entity_blocked microsoft
}
@test "S6 BLOCK: prefijo HTTP no oculta una entidad confidencial" {
  assert_entity_blocked http
}
@test "S6 BLOCK: prefijo Chrome no oculta una organización confidencial" {
  assert_entity_blocked chrome
}
@test "S6 BLOCK: prefijo API no oculta una credencial sintética" {
  assert_entity_blocked api
}
@test "S6 BLOCK: prefijo github no oculta una URL de roadmap" {
  assert_entity_blocked github
}
@test "S6 BLOCK: from seguido de un nombre sintético no es un token completo" {
  assert_entity_blocked from
}
@test "S6 BLOCK boundary: terminar en 8080 no permite una IP interna" {
  assert_entity_blocked ip8080
}
@test "S6 BLOCK boundary: terminar en 8443 no permite un host" {
  assert_entity_blocked host8443
}
@test "S6 BLOCK boundary: sufijo numérico no permite una credencial" {
  assert_entity_blocked numeric_suffix
}
@test "S6 BLOCK: timeout= como subcadena no permite texto confidencial" {
  assert_entity_blocked timeout_inside
}
@test "S6 BLOCK: timeout=5 seguido de texto deja de ser un token de código" {
  assert_entity_blocked timeout_tail
}
@test "S6 BLOCK: nombre de excepción seguido de persona no permite la entidad" {
  assert_entity_blocked exception
}
@test "S6 BLOCK: mayúsculas mezcladas no evitan el anclaje completo" {
  assert_entity_blocked casefold
}
@test "S6 BLOCK: varias entidades parcialmente permitidas siguen bloqueadas" {
  local entities
  entities=$(blocked_entities | jq -c '[.[] | select(.id == "microsoft" or .id == "ip8080") | del(.id)]')
  invoke_hook "$entities"
  assert_blocked
}
@test "S6 negativo: timeout=5 legítimo conserva WARN y auditoría" {
  invoke_hook '[{"type":"ORG","text":"timeout=5"}]'
  assert_warned
}
@test "S6 negativo: tokens completos legítimos conservan WARN" {
  local entities
  entities=$(legitimate_tokens | jq -c '[.[] | {type:"ORG",text:.}]')
  invoke_hook "$entities"
  assert_warned
}
@test "S6 negativo: entidad sin palabras de código conserva BLOCK" {
  invoke_hook '[{"type":"PERSON","text":"Persona Prueba Sintetica"}]'
  assert_blocked
}
@test "S6 negativo: token legítimo no oculta otra entidad no permitida" {
  invoke_hook '[{"type":"ORG","text":"HTTP"},{"type":"PERSON","text":"Persona Prueba Sintetica"}]'
  assert_blocked
}
@test "S6 negativo: mismo token legítimo en fichero de documentación conserva BLOCK" {
  invoke_hook '[{"type":"ORG","text":"HTTP"}]' docs/fixture.md
  assert_blocked
}
@test "S6 Edit: new_string con prefijo Microsoft conserva BLOCK" {
  local entities
  entities=$(blocked_entities | jq -c '[.[] | select(.id == "microsoft") | del(.id)]')
  invoke_hook "$entities" src/fixture.ts Edit
  assert_blocked
}
@test "S6 Edit negativo: new_string de código legítimo conserva WARN" {
  invoke_hook '[{"type":"ORG","text":"JSON"}]' src/fixture.ts Edit
  assert_warned
}
@test "S6 TS: las mismas 13 entidades sintéticas no son tokens de código" {
  command -v bun >/dev/null
  blocked_entities > "$BATS_TEST_TMPDIR/entities.json"
  run bun -e '
    const { isCodeToken } = await import(process.argv[1]);
    const entities = await Bun.file(process.argv[2]).json();
    for (const entity of entities) {
      if (isCodeToken(entity.text) !== false) throw Error(JSON.stringify(entity));
    }
    console.log(`${entities.length} entidades rechazadas`);
  ' "$TS_PATTERNS" "$BATS_TEST_TMPDIR/entities.json"
  [ "$status" -eq 0 ]
  [ "$output" = "13 entidades rechazadas" ]
}
@test "S6 TS negativo: los mismos siete tokens completos son código" {
  command -v bun >/dev/null
  legitimate_tokens > "$BATS_TEST_TMPDIR/entities.json"
  run bun -e '
    const { isCodeToken } = await import(process.argv[1]);
    const entities = await Bun.file(process.argv[2]).json();
    for (const text of entities) {
      if (isCodeToken(text) !== true) throw Error(JSON.stringify(text));
    }
    console.log(`${entities.length} tokens aceptados`);
  ' "$TS_PATTERNS" "$BATS_TEST_TMPDIR/entities.json"
  [ "$status" -eq 0 ]
  [ "$output" = "7 tokens aceptados" ]
}
