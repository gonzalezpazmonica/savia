#!/usr/bin/env bats
# tests/bats/test-opencode-config-validate.bats — opencode-config-validate.sh
#
# SE-253 errata: prevents unknown keys (like 'catalog') from being added
# to opencode.json where they cause startup failures in OpenCode >=1.16.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/opencode-config-validate.sh"
  TMPDIR="$(mktemp -d)"
  CONFIG="$TMPDIR/opencode.json"
}

teardown() {
  rm -rf "$TMPDIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-1: Fichero inexistente (no error, skip)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-1: config inexistente sale con exit 0" {
  OPENCODE_CONFIG="$TMPDIR/nonexistent.json" run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-2: JSON no valido
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-2: JSON invalido sale con exit 2" {
  printf '%s\n' 'not json{' > "$CONFIG"
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-3: Solo keys validas
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-3a: solo schema — valido" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema": "https://opencode.ai/config.json"}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "AC-3b: keys tipicas (agent, mcp, command) — valido" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x","agent":{"b":{"mode":"primary"}},"mcp":{},"command":{}}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4: Key desconocida bloquea en --check, avisa en --warn
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4a: key catalog bloquea en --check (exit 1)" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x","catalog":{"tier_field":"tier","default_tier":"core"}}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
}

@test "AC-4b: key catalog avisa en --warn (exit 0)" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x","catalog":{"tier":"core"}}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --warn
  [ "$status" -eq 0 ]
}

@test "AC-4c: key inventada bloquea en --check" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x","foo_bad":123}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
}

@test "AC-4d: multiple keys desconocidas" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x","catalog":{},"bad_key":null}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --check
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-5: Modo invalido
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-5: modo invalido sale con exit 2" {
  cat > "$CONFIG" <<'ENDJSON'
{"$schema":"x"}
ENDJSON
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" --invalid
  [ "$status" -eq 2 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-6: Config real del repo pasa (regresion)
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-6: opencode.json real del repo pasa" {
  OPENCODE_CONFIG="$REPO_ROOT/opencode.json" run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Comportamiento: claves validas por version, extensiones x_savia_*, salida y --health con stubs
# ─────────────────────────────────────────────────────────────────────────────

chk() { OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT" "${1:---check}"; }

@test "claves V2 (default_agent, policies, logLevel, server) son validas" {
  echo '{"default_agent":"a","policies":{},"logLevel":"info","server":{},"plugins":[]}' > "$CONFIG"
  chk
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 5 top-level keys"* ]]
}

@test "las claves se distinguen por mayusculas (loglevel, MODEL no son validas)" {
  echo '{"loglevel":"info","MODEL":"x"}' > "$CONFIG"
  chk
  [ "$status" -eq 1 ]
  [[ "$output" == *"'MODEL' is not a recognized"* && "$output" == *"'loglevel' is not a recognized"* ]]
  [[ "$output" == *"2 unknown key(s)"* ]]
}

@test "extensiones x_savia_* se ignoran; x_otro no" {
  echo '{"x_savia_tiers":{},"model":"m"}' > "$CONFIG"
  chk
  [ "$status" -eq 0 ]
  echo '{"x_otro":1}' > "$CONFIG"
  chk
  [ "$status" -eq 1 ]
  [[ "$output" == *"'x_otro'"* ]]
}

@test "el prefijo x_savia sin guion bajo final no es una extension" {
  echo '{"x_saviaa":1}' > "$CONFIG"
  chk
  [ "$status" -eq 1 ]
}

@test "objeto vacio: PASS con no keys" {
  echo '{}' > "$CONFIG"
  chk
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid JSON with no keys"* ]]
}

@test "solo se miran claves de primer nivel: una clave anidada desconocida no falla" {
  echo '{"agent":{"catalog":1}}' > "$CONFIG"
  chk
  [ "$status" -eq 0 ]
}

@test "--check bloquea con mensaje BLOCKED; --warn avisa con WARNING y sale 0" {
  echo '{"catalog":1}' > "$CONFIG"
  chk --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED: remove unknown keys"* ]]
  chk --warn
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: fix before committing"* && "$output" != *"BLOCKED"* ]]
}

@test "sin argumento el modo por defecto es --check" {
  echo '{"catalog":1}' > "$CONFIG"
  OPENCODE_CONFIG="$CONFIG" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "JSON invalido sale 2 incluso en --warn" {
  echo '{roto' > "$CONFIG"
  chk --warn
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not valid JSON"* ]]
}

@test "modo invalido imprime el uso y sale 2 sin leer la config" {
  OPENCODE_CONFIG="$BATS_TEST_TMPDIR/inexistente.json" run bash "$SCRIPT" --nada
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown mode '--nada'"* && "$output" == *"Usage:"* ]]
}

# --health con ejecutables simulados en PATH

health_env() {  # $1 = salida de 'opencode debug config'
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  HCFG="$1"
  cat > "$STUBS/opencode" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "--version "*|"--version") echo "9.9.9" ;;
  "plugin list") echo "${STUB_PLUGINS:-savia-foundation}" ;;
  "debug config") printf '%s' "${STUB_CONFIG:-}" ;;
  "mcp list") echo "${STUB_MCP:-ok}" ;;
esac
STUB
  printf '#!/usr/bin/env bash\nexit "${STUB_NODE_RC:-0}"\n' > "$STUBS/node"
  chmod +x "$STUBS/opencode" "$STUBS/node"
  export PATH="$STUBS:$PATH" STUB_CONFIG="$HCFG"
}
GOOD_CFG='{"permission":{"external_directory":"ask"},"subagent_depth": 2,"policies":{}}'

@test "--health: todo correcto da RESULT PASS con 0 warnings" {
  health_env "$GOOD_CFG"
  run bash "$SCRIPT" --health
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS opencode 9.9.9"* ]]
  [[ "$output" == *"RESULT PASS (0 warnings)"* ]]
}

@test "--health: model_tier en la config efectiva es FAIL (fuga a request.body)" {
  health_env '{"model_tier":"heavy","external_directory":1,"subagent_depth": 2,"policies":1}'
  run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL model_tier en la config efectiva"* && "$output" == *"RESULT FAIL (1 fallos"* ]]
}

@test "--health: ausencias de external_directory, subagent_depth o policies son WARN y no fallan" {
  health_env '{"x":1}'
  run bash "$SCRIPT" --health
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN external_directory no definido"* ]]
  [[ "$output" == *"WARN subagent_depth distinto de 2"* ]]
  [[ "$output" == *"WARN policies ausentes"* ]]
  [[ "$output" == *"RESULT PASS (3 warnings)"* ]]
}

@test "--health: plugin savia-foundation no descubierto es FAIL" {
  health_env "$GOOD_CFG"
  STUB_PLUGINS="otro" run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL plugin savia-foundation no descubierto"* ]]
}

@test "--health: config efectiva vacia es FAIL" {
  health_env ""
  run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL opencode debug config no devuelve configuración"* ]]
}

@test "--health: savia-vaults fallido y servidores desactivados que arrancan son FAIL distintos" {
  health_env "$GOOD_CFG"
  STUB_MCP="✗ savia-vaults  failed" run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL savia-vaults no conecta"* ]]
  STUB_MCP="✗ codegraph" run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL servidores desactivados siguen intentando arrancar"* ]]
  STUB_MCP="✗ codebase-memory-mcp" run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL servidores desactivados"* ]]
  STUB_MCP="✓ codegraph" run bash "$SCRIPT" --health
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS servidores desactivados no arrancan"* ]]
  [[ "$output" == *"PASS savia-vaults sin fallo reportado"* ]]
}

@test "--health: el smoke dual que falla es FAIL; el que pasa es PASS" {
  health_env "$GOOD_CFG"
  STUB_NODE_RC=1 run bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL smoke dual V1/V2"* ]]
  STUB_NODE_RC=0 run bash "$SCRIPT" --health
  [[ "$output" == *"PASS smoke dual V1/V2"* ]]
}

@test "--health sin opencode en PATH falla de inmediato" {
  PATH="/usr/bin:/bin" command -v opencode >/dev/null && skip "opencode instalado en /usr/bin o /bin"
  run env PATH="/usr/bin:/bin" bash "$SCRIPT" --health
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL opencode no está en PATH"* ]]
}
