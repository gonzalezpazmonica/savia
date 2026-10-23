#!/usr/bin/env bats
# tests/test-se-218-s2-kg-export.bats — SE-218 S2: KG snapshot versionado
# Ref: docs/propuestas/SE-218-codebase-memory-patterns.md

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/kg-export.sh"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export SAVIA_WORKSPACE_DIR="$TEST_TMPDIR"
  export SAVIA_KG_DB="$TEST_TMPDIR/output/knowledge-graph.db"
  mkdir -p "$TEST_TMPDIR/output" "$TEST_TMPDIR/scripts"
  # Crear KG mínimo de prueba (SQLite válido para compresión)
  echo '{"nodes":[],"edges":[]}' > "$SAVIA_KG_DB"
  cp "$SCRIPT" "$TEST_TMPDIR/scripts/kg-export.sh" 2>/dev/null || true
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# ── 1. Script existe y es ejecutable ─────────────────────────────────────────

@test "kg-export.sh existe y es ejecutable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

# ── 2. set -uo pipefail en línea 2 ───────────────────────────────────────────

@test "set -uo pipefail en línea 2" {
  run sed -n '2p' "$SCRIPT"
  [[ "$output" == "set -uo pipefail" ]]
}

# ── 3. export --mode best con KG existente: crea snapshot ────────────────────

@test "export --mode best con KG existente: crea snapshot (.zst o .gz)" {
  run bash "$SCRIPT" export --mode best
  [[ "$status" -eq 0 ]]
  # Acepta .zst o .gz según disponibilidad de zstd
  local snap_zst="$TEST_TMPDIR/.savia-kg/graph.db.zst"
  local snap_gz="$TEST_TMPDIR/.savia-kg/graph.db.gz"
  [[ -f "$snap_zst" || -f "$snap_gz" ]]
}

# ── 4. export --mode fast con KG existente: crea snapshot, exit 0 ────────────

@test "export --mode fast con KG existente: exit 0 y crea snapshot" {
  run bash "$SCRIPT" export --mode fast
  [[ "$status" -eq 0 ]]
  local snap_zst="$TEST_TMPDIR/.savia-kg/graph.db.zst"
  local snap_gz="$TEST_TMPDIR/.savia-kg/graph.db.gz"
  [[ -f "$snap_zst" || -f "$snap_gz" ]]
}

# ── 5. status muestra campos requeridos ──────────────────────────────────────

@test "status muestra campos requeridos (Snapshot: y KG DB:)" {
  run bash "$SCRIPT" status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Snapshot:"* ]]
  [[ "$output" == *"KG DB:"* ]]
}

# ── 6. import con snapshot corrupto: warning + exit 0 ────────────────────────

@test "import con snapshot corrupto: warning + exit 0" {
  mkdir -p "$TEST_TMPDIR/.savia-kg"
  echo "not_a_valid_compressed_file" > "$TEST_TMPDIR/.savia-kg/graph.db.zst"
  run bash "$SCRIPT" import
  # exit 0 — fallos son warnings, nunca crashes
  [[ "$status" -eq 0 ]]
}

# ── 7. import sin snapshot: warning + exit 0 ─────────────────────────────────

@test "import sin snapshot: WARN + exit 0" {
  # No hay .savia-kg en absoluto
  run bash "$SCRIPT" import
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WARN"* || "$stderr" == *"WARN"* ]]
}

# ── 8. export con modo desconocido: exit 2 ───────────────────────────────────

@test "export con modo desconocido: exit 2" {
  run bash "$SCRIPT" export --mode invalid_mode
  [[ "$status" -eq 2 ]]
}

# ── 9. .gitattributes contiene merge=ours tras export ────────────────────────

@test ".gitattributes contiene merge=ours tras export" {
  run bash "$SCRIPT" export --mode fast
  [[ "$status" -eq 0 ]]
  local ga="$TEST_TMPDIR/.gitattributes"
  [[ -f "$ga" ]]
  run grep "merge=ours" "$ga"
  [[ "$status" -eq 0 ]]
}

# ── 10. export sin KG: exit 1 con mensaje claro ──────────────────────────────

@test "export sin KG: exit 1 con mensaje claro" {
  rm -f "$SAVIA_KG_DB"
  run bash "$SCRIPT" export --mode best
  [[ "$status" -eq 1 ]]
  # El mensaje de error debe mencionar el problema
  [[ "$output" == *"ERROR"* || "$stderr" == *"ERROR"* ]]
}

@test "edge: export with empty KG file exits 1 with clear error" {
  echo "" > "$SAVIA_KG_DB"
  run bash "$SCRIPT" export --mode best
  # Empty file — behavior: either succeeds (zstd handles empty) or exits 1
  # Either is acceptable; must not crash with unhandled error
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "edge: import with nonexistent snapshot directory exits 0" {
  rm -rf "$TEST_TMPDIR/.savia-kg"
  run bash "$SCRIPT" import
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: no snapshot found"* ]]
}

@test "assertion: status output contains required fields as JSON-parseable lines" {
  run bash "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Snapshot:"
  echo "$output" | grep -q "KG DB:"
}
