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

# ── Cliente stdio con servidor falso ────────────────────────────────────────

@test "stdio: recorre la paginación (nextCursor) hasta el catálogo completo" {
  run env FAKE_MCP_MODE=paginate bash "$SCRIPT" --schemas --json --expected "$FX/expected.txt" \
    -- python3 "$FX/fake-mcp-server.py"
  [ "$status" -eq 0 ]
  [ "$(jq '.tools | length' <<<"$output")" -eq 3 ]
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
