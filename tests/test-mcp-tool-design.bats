#!/usr/bin/env bats
# SE-443 S1 — doctrina docs/rules/domain/mcp-tool-design.md y lint de esquemas MCP
# (scripts/mcp-audit.sh --schemas). Contrato de salida: gate-result-contract.md (SE-453).

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/scripts/mcp-audit.sh"
DOC="$ROOT/docs/rules/domain/mcp-tool-design.md"
FX="$BATS_TEST_DIRNAME/fixtures/mcp-tool-design"
VAULTS="$ROOT/projects/savia-vaults"

lint() { bash "$SCRIPT" --schemas "$@"; }

# ── Doctrina ────────────────────────────────────────────────────────────────

@test "doctrina: existe y no supera 150 líneas" {
  [ -f "$DOC" ]
  [ "$(wc -l < "$DOC")" -le 150 ]
}

@test "doctrina: cubre forma, efectos, catálogo completo, argumentos no confiables y orden" {
  grep -q '^## 1. Forma' "$DOC"
  grep -q '^## 2. Efectos declarados' "$DOC"
  grep -q '^## 3. Catálogo completo' "$DOC"
  grep -q '^## 4. Argumentos como datos no confiables' "$DOC"
  grep -q '^## 5. El orden del catálogo no significa nada' "$DOC"
}

# ── Servidor real: savia-vaults por stdio ───────────────────────────────────

@test "savia-vaults: tools/list servido completo y con esquemas válidos" {
  # Fail-closed: sin dependencias instaladas el test falla, no se salta.
  [ -x "$VAULTS/node_modules/.bin/tsx" ] || { echo "falta node_modules: cd projects/savia-vaults && npm ci"; false; }
  local tmp="$BATS_TEST_TMPDIR"
  local handled
  handled="$(grep -oE "case '[a-z_]+'" "$VAULTS/src/server/mcp.ts" | sort -u | wc -l)"
  [ "$handled" -ge 19 ]
  run env HOME="$tmp/home" bash -c 'cd "$1" && bash "$2" --schemas --json --timeout 60 \
      --expected-from-source src/server/mcp.ts \
      -- node_modules/.bin/tsx src/cli/index.ts serve --transport mcp --path "$3/vault"' \
      _ "$VAULTS" "$SCRIPT" "$tmp"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(jq -r .result <<<"$output")" = "clean" ]
  [ "$(jq '.tools | length' <<<"$output")" -eq "$handled" ]
  [ "$(jq '.findings | length' <<<"$output")" -eq 0 ]
}

# ── Catálogo de fixture: positivo, orden y negativos ────────────────────────

@test "catálogo correcto: clean, exit 0 y línea gate-result final" {
  run lint --catalog "$FX/catalog-ok.json" --expected "$FX/expected.txt"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"clean"}' ]
}

@test "orden sin significado: el catálogo invertido da el mismo resultado" {
  run lint --catalog "$FX/catalog-ok.json" --expected "$FX/expected.txt" --json
  [ "$status" -eq 0 ]
  local a; a="$(jq -c '{result, tools, findings}' <<<"$output")"
  run lint --catalog "$FX/catalog-shuffled.json" --expected "$FX/expected.txt" --json
  [ "$status" -eq 0 ]
  [ "$(jq -c '{result, tools, findings}' <<<"$output")" = "$a" ]
}

@test "orden sin significado: con varios hallazgos, la salida no depende del orden" {
  # Dos herramientas sin descripción en extremos opuestos: sin ordenar los
  # hallazgos, invertir el catálogo invierte la salida.
  jq '.tools[0].description = "" | .tools[2].description = ""' "$FX/catalog-ok.json" > "$BATS_TEST_TMPDIR/a.json"
  jq '.tools |= reverse' "$BATS_TEST_TMPDIR/a.json" > "$BATS_TEST_TMPDIR/b.json"
  run lint --catalog "$BATS_TEST_TMPDIR/a.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  local a="$output"
  [[ "$a" == *"note_read: sin descripción"* && "$a" == *"note_search: sin descripción"* ]]
  run lint --catalog "$BATS_TEST_TMPDIR/b.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [ "$output" = "$a" ]
}

@test "negativo: nombre duplicado hace fallar el lint" {
  jq '.tools[1].name = "note_read"' "$FX/catalog-ok.json" > "$BATS_TEST_TMPDIR/c.json"
  run lint --catalog "$BATS_TEST_TMPDIR/c.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_read: nombre duplicado"* ]]
}

@test "negativo: descripción solo con espacios hace fallar el lint" {
  jq '.tools[0].description = "   "' "$FX/catalog-ok.json" > "$BATS_TEST_TMPDIR/c.json"
  run lint --catalog "$BATS_TEST_TMPDIR/c.json" --expected "$FX/expected.txt" --json
  [ "$status" -eq 1 ]
  [ "$(jq -c .findings <<<"$output")" = '["note_read: sin descripción"]' ]
}

@test "negativo: inputSchema.type distinto de object hace fallar el lint" {
  jq '.tools[0].inputSchema.type = "array"' "$FX/catalog-ok.json" > "$BATS_TEST_TMPDIR/c.json"
  run lint --catalog "$BATS_TEST_TMPDIR/c.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *'note_read: inputSchema.type debe ser "object"'* ]]
}

@test "negativo: herramienta sin inputSchema hace fallar el lint" {
  run lint --catalog "$FX/catalog-no-input-schema.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_write: sin inputSchema"* ]]
  [ "${lines[-1]}" = 'gate-result: {"result":"findings"}' ]
}

@test "negativo: esquema inválido como JSON Schema hace fallar el lint" {
  run lint --catalog "$FX/catalog-invalid-schema.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_search: esquema inválido"* ]]
}

@test "negativo: falta una herramienta esperada (catálogo incompleto)" {
  run lint --catalog "$FX/catalog-missing-tool.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_search: falta en el catálogo"* ]]
}

@test "negativo: herramienta servida sin estar esperada" {
  run lint --catalog "$FX/catalog-extra-tool.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_hidden: servida pero no esperada"* ]]
}

@test "negativo: required con una clave que no está en properties" {
  run lint --catalog "$FX/catalog-required-unknown.json" --expected "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_read: required 'ruta' no está en properties"* ]]
}

@test "límite: sin annotations es aviso, no fallo" {
  run lint --catalog "$FX/catalog-no-annotations.json" --expected "$FX/expected.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN note_read: sin efectos declarados"* ]]
}

@test "límite: readOnlyHint no booleano (\"no\", null) no cuenta como efecto declarado" {
  jq '.tools[0].annotations = {readOnlyHint: "no"} | .tools[2].annotations = {readOnlyHint: null}' \
    "$FX/catalog-ok.json" > "$BATS_TEST_TMPDIR/c.json"
  run lint --catalog "$BATS_TEST_TMPDIR/c.json" --expected "$FX/expected.txt" --json
  [ "$status" -eq 0 ]
  [ "$(jq '.warnings | length' <<<"$output")" -eq 2 ]
}

@test "lista esperada desde fuente: acepta case con comillas dobles" {
  printf "switch (n) {\n  case 'note_read':\n  case \"note_write\":\n  case 'note_search': break\n}\n" > "$BATS_TEST_TMPDIR/s.ts"
  run lint --catalog "$FX/catalog-ok.json" --expected-from-source "$BATS_TEST_TMPDIR/s.ts" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .result <<<"$output")" = "clean" ]
}

@test "aislamiento: un jsonschema/ en el cwd no sustituye al validador" {
  mkdir -p "$BATS_TEST_TMPDIR/cwd/jsonschema"
  cat > "$BATS_TEST_TMPDIR/cwd/jsonschema/__init__.py" <<'EOF'
class Draft202012Validator:
    @staticmethod
    def check_schema(s): pass
EOF
  printf 'from jsonschema import Draft202012Validator\ndef validator_for(s, default=None): return Draft202012Validator\n' \
    > "$BATS_TEST_TMPDIR/cwd/jsonschema/validators.py"
  printf 'class SchemaError(Exception): pass\n' > "$BATS_TEST_TMPDIR/cwd/jsonschema/exceptions.py"
  run bash -c 'cd "$1" && bash "$2" --schemas --catalog "$3" --expected "$4"' \
    _ "$BATS_TEST_TMPDIR/cwd" "$SCRIPT" "$FX/catalog-invalid-schema.json" "$FX/expected.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"note_search: esquema inválido"* ]]
}

# ── Cliente stdio con servidor falso ────────────────────────────────────────

@test "stdio: recorre la paginación (nextCursor) hasta el catálogo completo" {
  run env FAKE_MCP_MODE=paginate bash "$SCRIPT" --schemas --json --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 0 ]
  [ "$(jq '.tools | length' <<<"$output")" -eq 3 ]
}

@test "stdio: notificación y respuesta en la misma escritura no dan timeout falso" {
  run timeout 30 env FAKE_MCP_MODE=burst bash "$SCRIPT" --schemas --json --timeout 5 \
    --expected "$FX/expected.txt" -- python3 "$FX/fake-mcp-server.py"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(jq '.tools | length' <<<"$output")" -eq 3 ]
}

@test "fail-closed: línea parcial sin salto y servidor callado → timeout, no cuelgue" {
  run timeout 30 env FAKE_MCP_MODE=partial bash "$SCRIPT" --schemas --timeout 2 \
    --expected "$FX/expected.txt" -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"reason":"timeout"'* ]]
}

@test "fail-closed: initialize con error JSON-RPC → initialize_failed, exit 2" {
  run env FAKE_MCP_MODE=initerror bash "$SCRIPT" --schemas --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"server","reason":"initialize_failed"}]}' ]
}

@test "fail-closed: nextCursor infinito se corta en el límite de páginas → exit 2" {
  run timeout 120 env FAKE_MCP_MODE=endless bash "$SCRIPT" --schemas --timeout 100 \
    --expected "$FX/expected.txt" -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"tools/list","reason":"limit"}]}' ]
}

# ── Fail-closed (SE-453: unknown, nunca PASS) ───────────────────────────────

@test "fail-closed: servidor que sale sin responder → unknown, exit 2" {
  run env FAKE_MCP_MODE=exit bash "$SCRIPT" --schemas --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"server","reason":"not_executed"}]}' ]
}

@test "fail-closed: servidor mudo → timeout, exit 2" {
  run env FAKE_MCP_MODE=silent bash "$SCRIPT" --schemas --timeout 2 --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"reason":"timeout"'* ]]
}

@test "fail-closed: tools/list con error JSON-RPC → unknown, exit 2" {
  run env FAKE_MCP_MODE=error bash "$SCRIPT" --schemas --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"check":"tools/list","reason":"unreadable"'* ]]
}

@test "fail-closed: comando de servidor inexistente → exit 2" {
  run lint --expected "$FX/expected.txt" -- "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"result":"unknown"'* ]]
}

@test "fail-closed: sin la herramienta de validación (jsonschema) → unknown, exit 2" {
  run env PYTHONPATH="$FX/no-jsonschema" bash "$SCRIPT" --schemas \
    --catalog "$FX/catalog-ok.json" --expected "$FX/expected.txt"
  [ "$status" -eq 2 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"jsonschema","reason":"missing_tool"}]}' ]
}

@test "fail-closed: sin lista esperada no hay veredicto de completitud" {
  run lint --catalog "$FX/catalog-ok.json"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"reason":"no_baseline"'* ]]
}

@test "fail-closed: --expected vacío o solo comentarios → unknown, nunca clean" {
  printf '# nada\n\n' > "$BATS_TEST_TMPDIR/empty.txt"
  run lint --catalog "$FX/catalog-extra-tool.json" --expected "$BATS_TEST_TMPDIR/empty.txt"
  [ "$status" -eq 2 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"expected","reason":"empty"}]}' ]
  run lint --catalog "$FX/catalog-ok.json" --expected /dev/null
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"reason":"empty"'* ]]
}

@test "fail-closed: --expected-from-source sin ningún case → unknown, exit 2" {
  printf 'export const x = 1\n' > "$BATS_TEST_TMPDIR/s.ts"
  run lint --catalog "$FX/catalog-ok.json" --expected-from-source "$BATS_TEST_TMPDIR/s.ts"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"check":"expected","reason":"empty"'* ]]
}

@test "argumentos: --expected y --expected-from-source a la vez es error de uso" {
  run lint --catalog "$FX/catalog-ok.json" --expected "$FX/expected.txt" \
    --expected-from-source "$VAULTS/src/server/mcp.ts"
  [ "$status" -eq 2 ]
  [[ "$output" == *"excluyentes"* ]]
}

@test "fail-closed: catálogo ilegible → unknown, exit 2" {
  printf '{no json' > "$BATS_TEST_TMPDIR/bad.json"
  run lint --catalog "$BATS_TEST_TMPDIR/bad.json" --expected "$FX/expected.txt"
  [ "$status" -eq 2 ]
  [[ "${lines[-1]}" == *'"check":"catalog","reason":"unreadable"'* ]]
}

@test "argumentos: --catalog y servidor a la vez es error de uso" {
  run lint --catalog "$FX/catalog-ok.json" -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"uno de los dos"* ]]
}
