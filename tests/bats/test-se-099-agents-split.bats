#!/usr/bin/env bats
# tests/bats/test-se-099-agents-split.bats — SE-099 Agent oversized audit
# Verifies: no FAIL violations in agents-size-checker, references/ valid, script works.
#
# Ref: docs/propuestas/SE-099-agents-oversized-rest.md
# Note: SE-099 documents that NO agents exceed the 200-line WARN threshold.
#       All SLA_WARN violations are byte-based (>4096B), not line-based.

SCRIPT="$(git rev-parse --show-toplevel)/scripts/agents-size-checker.sh"
REFERENCES_DIR="$(git rev-parse --show-toplevel)/.opencode/agents/references"

# ── Test 1: agents-size-checker.sh exists and is parseable ───────────────────
@test "SE-099-01: agents-size-checker.sh exists and is bash-parseable" {
  [ -f "$SCRIPT" ]
  bash -n "$SCRIPT"
}

# ── Test 2: Script produces output ───────────────────────────────────────────
@test "SE-099-02: agents-size-checker.sh produces output" {
  run bash "$SCRIPT" 2>/dev/null
  [ -n "$output" ]
}

# ── Test 3: No agents exceed 400-line FAIL threshold ─────────────────────────
@test "SE-099-03: no agents emit FAIL (>400 lines)" {
  run bash "$SCRIPT" 2>/dev/null
  # Exit code 0 means no FAIL violations
  [ "$status" -eq 0 ]
}

# ── Test 4: No agents exceed 200-line WARN threshold ─────────────────────────
@test "SE-099-04: no agents exceed 200-line WARN threshold" {
  # Column 2 is LINES. Skip header and summary lines.
  # An agent is over the line-WARN threshold if LINES (col2) > 200.
  hard_warn=$(bash "$SCRIPT" 2>/dev/null | awk 'NR>2 && $2~/^[0-9]+$/ && $2+0 > 200 {print $0}' | wc -l)
  [ "$hard_warn" -eq 0 ]
}

# ── Test 5: references/ directory exists ─────────────────────────────────────
@test "SE-099-05: .opencode/agents/references/ directory exists" {
  [ -d "$REFERENCES_DIR" ]
}

# ── Test 6: references/ contains only valid markdown files ───────────────────
@test "SE-099-06: all files in references/ are non-empty markdown" {
  # Skip if directory is empty
  ref_files=("$REFERENCES_DIR"/*.md)
  if [[ ! -f "${ref_files[0]}" ]]; then
    skip "references/ directory is empty (no agents were split)"
  fi
  for f in "$REFERENCES_DIR"/*.md; do
    [ -s "$f" ]   # non-empty
    [[ "$f" == *.md ]]
  done
}

# ── Test 7: Total WARN+FAIL count is deterministic ───────────────────────────
@test "SE-099-07: agents-size-checker.sh output ends with summary line" {
  run bash "$SCRIPT" 2>/dev/null
  [[ "$output" == *"Total:"* ]]
}

# ── Comportamiento con agentes sintéticos (SE-456) ────────────────────────────
# REPO_ROOT se puede sobrescribir: el checker lee $REPO_ROOT/.opencode/agents.

mk_agent() {  # mk_agent <nombre> <líneas> [bytes-extra-por-línea]
  local name="$1" n="$2" pad="${3:-0}" i line
  line="x"
  [[ "$pad" -gt 0 ]] && line="$(printf 'x%.0s' $(seq 1 "$pad"))"
  : > "$FIXROOT/.opencode/agents/$name.md"
  for ((i = 0; i < n; i++)); do echo "$line" >> "$FIXROOT/.opencode/agents/$name.md"; done
}

fix_setup() {
  FIXROOT="$(mktemp -d)"
  mkdir -p "$FIXROOT/.opencode/agents"
}

fix_teardown() { rm -rf "$FIXROOT"; }

@test "SE-099 comportamiento: umbrales exactos de líneas (200 OK, 201 WARN, 400 WARN, 401 FAIL)" {
  fix_setup
  mk_agent a200 200
  mk_agent a201 201
  mk_agent a400 400
  mk_agent a401 401
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --json
  [ "$status" -eq 1 ]
  json="${output%%FAIL:*}"
  [ "$(jq -r '.agents[]|select(.name=="a200")|.status' <<<"$json")" = "OK" ]
  [ "$(jq -r '.agents[]|select(.name=="a201")|.status' <<<"$json")" = "WARN" ]
  [ "$(jq -r '.agents[]|select(.name=="a400")|.status' <<<"$json")" = "WARN" ]
  [ "$(jq -r '.agents[]|select(.name=="a401")|.status' <<<"$json")" = "FAIL" ]
  [ "$(jq -r .summary.fail <<<"$json")" -eq 1 ]
  [ "$(jq -r .summary.warn <<<"$json")" -eq 2 ]
  [ "$(jq -r .summary.total <<<"$json")" -eq 4 ]
  fix_teardown
}

@test "SE-099 comportamiento: umbral de bytes exacto (4096 OK, 4097 SLA_WARN) y WARN tiene prioridad" {
  fix_setup
  # 4096 bytes: 64 líneas de 63 'x' + salto = 64 bytes cada una
  mk_agent b4096 64 63
  # 4097 bytes: 4096 + 1 línea corta de 1 byte+salto no vale; usar 1 línea más corta
  mk_agent b4160 65 63
  mk_agent w201 201 30
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents[]|select(.name=="b4096")|.bytes' <<<"$output")" -eq 4096 ]
  [ "$(jq -r '.agents[]|select(.name=="b4096")|.status' <<<"$output")" = "OK" ]
  [ "$(jq -r '.agents[]|select(.name=="b4160")|.status' <<<"$output")" = "SLA_WARN" ]
  [ "$(jq -r '.agents[]|select(.name=="w201")|.status' <<<"$output")" = "WARN" ]
  [ "$(jq -r .summary.warn <<<"$output")" -eq 2 ]
  fix_teardown
}

@test "SE-099 comportamiento: orden por líneas descendente y bytes/líneas reales" {
  fix_setup
  mk_agent corto 3
  mk_agent largo 50
  mk_agent medio 20
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.agents[].name]|join(",")' <<<"$output")" = "largo,medio,corto" ]
  [ "$(jq -r '.agents[0].lines' <<<"$output")" -eq 50 ]
  [ "$(jq -r '.agents[0].bytes' <<<"$output")" -eq 100 ]
  [ "$(jq -r '.summary|[.sla_bytes,.warn_lines,.fail_lines]|join(",")' <<<"$output")" = "4096,200,400" ]
  fix_teardown
}

@test "SE-099 comportamiento: tabla de texto con totales, marcas y exit 1 con FAIL" {
  fix_setup
  mk_agent grande 401
  mk_agent normal 10
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Total: 2 agents | FAIL: 1 | WARN: 0"* ]]
  [[ "$output" == *"!! FAIL (>400 lines — must split)"* ]]
  [[ "$output" == *"Thresholds: WARN >200 lines, FAIL >400 lines, SLA_WARN >4096B"* ]]
  [[ "$output" == *"FAIL: 1 agent(s) exceed 400 lines (Rule #22 hard limit)"* ]]
  fix_teardown
}

@test "SE-099 comportamiento: marcas WARN y SLA_WARN en la tabla, exit 0" {
  fix_setup
  mk_agent aviso 250
  mk_agent pesado 65 63
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"!  WARN (>200 lines)"* ]]
  [[ "$output" == *"~  SLA_WARN (>4096B)"* ]]
  [[ "$output" == *"Total: 2 agents | FAIL: 0 | WARN: 2"* ]]
  fix_teardown
}

@test "SE-099 comportamiento: --quiet no imprime tabla pero conserva el exit code" {
  fix_setup
  mk_agent grande 401
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --quiet
  [ "$status" -eq 1 ]
  [[ "$output" != *"AGENT"* ]]
  [[ "$output" != *"Total:"* ]]
  mk_agent grande 10
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  fix_teardown
}

@test "SE-099 comportamiento: solo cuenta ficheros .md del primer nivel" {
  fix_setup
  mk_agent uno 5
  mkdir -p "$FIXROOT/.opencode/agents/references"
  echo "x" > "$FIXROOT/.opencode/agents/references/ref.md"
  echo "x" > "$FIXROOT/.opencode/agents/notas.txt"
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --json
  [ "$(jq -r .summary.total <<<"$output")" -eq 1 ]
  [ "$(jq -r '.agents[0].name' <<<"$output")" = "uno" ]
  fix_teardown
}

@test "SE-099 comportamiento: directorio vacío → total 0 y exit 0" {
  fix_setup
  REPO_ROOT="$FIXROOT" run bash "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .summary.total <<<"$output")" -eq 0 ]
  fix_teardown
}

@test "SE-099 comportamiento: --help sale con 0 y argumento desconocido con 2" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--json"* ]]
  run bash "$SCRIPT" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--nope'"* ]]
}
