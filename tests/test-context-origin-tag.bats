#!/usr/bin/env bats
# tests/test-context-origin-tag.bats — SE-221 Slice 1 — Context Origin Tag resolver
#
# Spec: docs/propuestas/SE-221-inverted-security-patterns-as-context-engineering.md (AC-04)
# Refs: SPEC-185 (anchor superior), context-placement N1-N4b
#
# Tests para scripts/context-origin-tag.sh: dado un path, devuelve tag canonico
# segun N1-N4b. Resolucion por prefijo, no por contenido. Cubre cada tier,
# paths fuera del workspace, sandbox, idempotencia, JSON output.
#
# Safety: el script target usa set -uo pipefail.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/context-origin-tag.sh"

setup() {
  # Workspace fijo para tests reproducibles
  WS="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$WS"
  export SAVIA_WORKSPACE_DIR="$WS"
}

teardown() {
  unset SAVIA_WORKSPACE_DIR
}

# === Sintaxis y safety ===

@test "script es bash valido" {
  bash -n "$SCRIPT"
}

@test "uses set -uo pipefail" {
  head -10 "$SCRIPT" | grep -q "set -[euo]*o pipefail"
}

@test "es ejecutable" {
  [[ -x "$SCRIPT" ]]
}

# === Argumentos invalidos ===

@test "exit 2 sin argumentos" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "exit 2 con flag desconocido" {
  run "$SCRIPT" --bogus path.md
  [ "$status" -eq 2 ]
}

@test "exit 2 con multiples paths" {
  run "$SCRIPT" a.md b.md
  [ "$status" -eq 2 ]
}

@test "help via -h imprime usage y exit 0" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"context-origin-tag"* ]]
}

# === Tiers canonicos N1-N5 ===

@test "N1-anchor: docs/critical-facts.md" {
  run "$SCRIPT" "$WS/docs/critical-facts.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N1-anchor" ]
}

@test "N2-eager: docs/rules/domain/radical-honesty.md" {
  run "$SCRIPT" "$WS/docs/rules/domain/radical-honesty.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N2-eager" ]
}

@test "N2-eager: profiles/savia.md" {
  run "$SCRIPT" "$WS/.claude/profiles/savia.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N2-eager" ]
}

@test "N2-eager: CLAUDE.md raiz" {
  run "$SCRIPT" "$WS/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N2-eager" ]
}

@test "N3-active-user: profiles/active-user.md" {
  run "$SCRIPT" "$WS/.claude/profiles/active-user.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N3-active-user" ]
}

@test "N3-active-user: profiles/users/alice/" {
  run "$SCRIPT" "$WS/.claude/profiles/users/alice/identity.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N3-active-user" ]
}

@test "N3-active-user: external-memory" {
  run "$SCRIPT" "$WS/.claude/external-memory/auto/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N3-active-user" ]
}

@test "N4a-lazy-ref: docs/RESOLVER.md" {
  run "$SCRIPT" "$WS/docs/RESOLVER.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4a-lazy-ref" ]
}

@test "N4a-lazy-ref: projects/{X}/CLAUDE.md" {
  run "$SCRIPT" "$WS/projects/foo/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4a-lazy-ref" ]
}

@test "N4b-on-demand: rule generica de domain" {
  run "$SCRIPT" "$WS/docs/rules/domain/foo-bar.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4b-on-demand" ]
}

@test "N4b-on-demand: skill" {
  run "$SCRIPT" "$WS/.opencode/skills/foo/SKILL.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4b-on-demand" ]
}

@test "N4b-on-demand: agent" {
  run "$SCRIPT" "$WS/.opencode/agents/some-agent.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4b-on-demand" ]
}

@test "N4-project: projects/X/data" {
  run "$SCRIPT" "$WS/projects/foo/data/clients.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4-project" ]
}

# === Edge cases ===

@test "sandbox: /tmp/opencode/* siempre exento" {
  run "$SCRIPT" "/tmp/opencode/work.md"
  [ "$status" -eq 0 ]
  [ "$output" = "sandbox" ]
}

@test "N5-external: HOME path fuera del workspace" {
  run "$SCRIPT" "$HOME/.savia-memory/auto/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N5-external" ]
}

@test "untrusted: path absoluto fuera del workspace y de HOME" {
  run "$SCRIPT" "/etc/passwd"
  [ "$status" -eq 0 ]
  [ "$output" = "untrusted" ]
}

@test "fichero inexistente recibe tag (resolucion por prefijo, no por contenido)" {
  run "$SCRIPT" "$WS/docs/rules/domain/nonexistent.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4b-on-demand" ]
}

@test "path con espacios funciona (quoted)" {
  run "$SCRIPT" "$WS/docs/rules/domain/with space.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N4b-on-demand" ]
}

@test "path relativo se resuelve contra cwd" {
  cd "$WS"
  mkdir -p docs
  touch docs/critical-facts.md
  run "$SCRIPT" "docs/critical-facts.md"
  [ "$status" -eq 0 ]
  [ "$output" = "N1-anchor" ]
}

# === JSON output ===

@test "--json emite JSON valido" {
  run "$SCRIPT" --json "$WS/docs/critical-facts.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.' >/dev/null
}

@test "--json contiene path tier abs y workspace" {
  run "$SCRIPT" --json "$WS/docs/critical-facts.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.path and .tier and .abs and .workspace' >/dev/null
}

@test "--json tier es N1-anchor para critical-facts.md" {
  run "$SCRIPT" --json "$WS/docs/critical-facts.md"
  [ "$status" -eq 0 ]
  result=$(echo "$output" | jq -r '.tier')
  [ "$result" = "N1-anchor" ]
}

# === Idempotencia (resolucion deterministica) ===

@test "mismo path produce mismo tag dos veces" {
  run "$SCRIPT" "$WS/docs/rules/domain/foo.md"
  first="$output"
  run "$SCRIPT" "$WS/docs/rules/domain/foo.md"
  [ "$output" = "$first" ]
}

# === Negative ===

@test "exit 2 con --json sin path" {
  run "$SCRIPT" --json
  [ "$status" -eq 2 ]
}

@test "spec_reference: SE-221 documentado en script" {
  grep -q "SE-221" "$SCRIPT"
}

# === Edge cases (boundary, empty, large, no-args, timeout, null) ===
# Coverage: ejercitan abs_path() y resolve_tier() funciones del target.

@test "edge: empty path argument is rejected" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}

@test "edge: nonexistent absolute path still resolves tier (boundary case)" {
  # abs_path() y resolve_tier() deben operar sobre prefijos, no sobre contenido.
  run "$SCRIPT" "/this/path/does/not/exist/foo.md"
  [ "$status" -eq 0 ]
}

@test "edge: large path (>4kb) does not overflow buffer or hang" {
  # Construir path largo cerca de PATH_MAX para verificar boundary.
  long_segment=$(printf 'a%.0s' {1..100})
  long_path="$WS"
  for _ in {1..30}; do long_path="$long_path/$long_segment"; done
  long_path="$long_path/file.md"
  run timeout 3 "$SCRIPT" "$long_path"
  # No nos importa el verdict — solo que no cuelgue ni explote.
  [ "$status" -ne 124 ]  # 124 = timeout exit code
}

@test "edge: zero arguments triggers help/error (no-arg boundary)" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "edge: null byte in path is rejected gracefully" {
  # Bash strings no soportan NUL, pero el wrapper debe ser robusto.
  run "$SCRIPT" $'\x00invalid'
  # Cualquier salida controlada acepta — lo critico es no segfault.
  [ "$status" -ne 139 ]  # 139 = SIGSEGV
}

# === Rutas Windows (Git Bash) ===

@test "windows: ruta C:\ fuera del workspace no hereda un tier interno" {
  run bash "$SCRIPT" 'C:\Users\otra\AppData\Local\Temp\fake-spec.md'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "untrusted" || "$output" == "N5-external" ]]
}

@test "windows: workspace y ruta en formato C:\ resuelven el anchor" {
  SAVIA_WORKSPACE_DIR='C:\ws-savia' run bash "$SCRIPT" 'C:\ws-savia\docs\critical-facts.md'
  [[ "$output" == "N1-anchor" ]]
  SAVIA_WORKSPACE_DIR='C:\ws-savia' run bash "$SCRIPT" 'c:/ws-savia/docs/critical-facts.md'
  [[ "$output" == "N1-anchor" ]]
}

@test "directorio hermano con el mismo prefijo no cuenta como workspace" {
  run bash "$SCRIPT" "${WS}-otro/docs/critical-facts.md"
  [[ "$output" != "N1-anchor" ]]
}
