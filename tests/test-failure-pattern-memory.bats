#!/usr/bin/env bats
# tests/test-failure-pattern-memory.bats
# SPEC-188 Fase 1 — failure-pattern-memory.sh formal tests
# >= 6 tests
#
# Tests the failure pattern memory store introduced in SPEC-188 Phase 1.
# Uses a temporary SQLite database so production data is never touched.
# Feature flag: SAVIA_FAILURE_PATTERN_MEMORY_ENABLED (default 0)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/failure-pattern-memory.sh"

# ── Setup/teardown ────────────────────────────────────────────────────────────
setup() {
  # Isolated temp dir per test — avoids cross-test DB contamination
  TEST_TMP="$(mktemp -d)"
  export PROJECT_ROOT="$TEST_TMP"
  export DB_FILE_OVERRIDE="$TEST_TMP/.claude/external-memory/failure-patterns/patterns.db"
  # Enable feature flag for tests that need it
  export SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=1
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ── Test 1: script exists and is executable ───────────────────────────────────
@test "SPEC-188-F1 AC-01: failure-pattern-memory.sh exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

# ── Test 2: init creates the database structure ───────────────────────────────
@test "SPEC-188-F1 AC-02: init creates the SQLite database and failure_patterns table" {
  run bash "$SCRIPT" init
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK\|initialised\|schema"

  # Verify the DB file was created
  DB_PATH="$TEST_TMP/.claude/external-memory/failure-patterns/patterns.db"
  [[ -f "$DB_PATH" ]]

  # Verify the table schema was created
  run python3 -c "
import sqlite3, sys
conn = sqlite3.connect('$DB_PATH')
cur = conn.cursor()
cur.execute(\"SELECT name FROM sqlite_master WHERE type='table' AND name='failure_patterns'\")
row = cur.fetchone()
sys.exit(0 if row else 1)
"
  [ "$status" -eq 0 ]
}

# ── Test 3: add inserts a pattern (with feature flag enabled) ─────────────────
@test "SPEC-188-F1 AC-03: add inserts a failure pattern into the database" {
  # Pre-init the DB
  bash "$SCRIPT" init > /dev/null 2>&1

  run bash "$SCRIPT" add \
    --agent "test-runner" \
    --error "TimeoutException: test took >120s" \
    --file-glob "tests/**/*.bats" \
    --lesson "Reduce fixture size to avoid timeout"

  [ "$status" -eq 0 ]
  # Output confirms INSERT or UPDATED
  echo "$output" | grep -qE "INSERTED|UPDATED"
}

# ── Test 4: list returns output (possibly empty, but no error) ────────────────
@test "SPEC-188-F1 AC-04: list returns valid output (empty or populated, no error)" {
  bash "$SCRIPT" init > /dev/null 2>&1

  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  # Output must be non-empty (at minimum "0 entries" message)
  [[ -n "$output" ]]
}

# ── Test 5: stats returns structured text output ──────────────────────────────
@test "SPEC-188-F1 AC-05: stats returns structured text with total/open/acknowledged/resolved fields" {
  bash "$SCRIPT" init > /dev/null 2>&1

  run bash "$SCRIPT" stats
  [ "$status" -eq 0 ]
  # Must include the key counters
  echo "$output" | grep -q "total:"
  echo "$output" | grep -q "open:"
  echo "$output" | grep -q "resolved:"
  # Must also report the feature flag state
  echo "$output" | grep -q "SAVIA_FAILURE_PATTERN_MEMORY_ENABLED"
}

# ── Test 6: SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=0 → disabled behavior ────────
@test "SPEC-188-F1 AC-06: ENABLED=0 disables add and list (returns info message)" {
  bash "$SCRIPT" init > /dev/null 2>&1
  export SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=0

  run bash "$SCRIPT" add --agent "dotnet-developer" --error "NullRef"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "disabled\|ENABLED=0\|SAVIA_FAILURE_PATTERN_MEMORY_ENABLED"

  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "disabled\|ENABLED=0\|SAVIA_FAILURE_PATTERN_MEMORY_ENABLED"
}

# ── Test 7: add + list round-trip (data persists) ─────────────────────────────
@test "SPEC-188-F1 AC-07: add then list round-trip — inserted pattern appears in list" {
  bash "$SCRIPT" init > /dev/null 2>&1

  bash "$SCRIPT" add \
    --agent "python-developer" \
    --error "ModuleNotFoundError: fastapi" \
    > /dev/null 2>&1

  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "python-developer"
}

# ── Test 8: stats works even on empty store (no crash) ────────────────────────
@test "SPEC-188-F1 AC-08: stats on uninitialised store does not crash" {
  # No init called — DB does not exist
  # stats should handle gracefully (not crash with exit code != 0)
  run bash "$SCRIPT" stats
  # Exit 0 expected (graceful handling)
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "not initialised\|not initialized\|Store"
}

# ── Comportamiento: identidad, upsert y puente de promoción ───────────────────

_add() { bash "$SCRIPT" add "$@"; }
_id_of() { printf '%s' "$1" | sha256sum | cut -c1-8; }
_show_field() { bash "$SCRIPT" show "$1" | grep "^$2:" | sed "s/^$2: *//"; }

@test "SPEC-188-F1: pattern_id es sha256(agent+error+glob) recortado a 8 hex" {
  run _add --agent "a1" --error "boom" --file-glob "*.sh"
  [ "$status" -eq 0 ]
  expected="$(_id_of 'a1boom*.sh')"
  [ "$output" = "INSERTED: $expected agent=a1" ]
}

@test "SPEC-188-F1: la misma firma en otro agente o con otro glob es otro patrón" {
  a="$(_add --agent "a1" --error "boom" | awk '{print $2}')"
  b="$(_add --agent "a2" --error "boom" | awk '{print $2}')"
  c="$(_add --agent "a1" --error "boom" --file-glob "x" | awk '{print $2}')"
  [ "$a" != "$b" ]
  [ "$a" != "$c" ]
  [ "$(bash "$SCRIPT" list | tail -1)" = "3 pattern(s) found" ]
}

@test "SPEC-188-F1: repetir la firma incrementa occurrences y conserva first_seen" {
  id="$(_add --agent "a1" --error "boom" | awk '{print $2}')"
  first="$(_show_field "$id" first_seen)"
  sleep 1
  run _add --agent "a1" --error "boom"
  [ "$output" = "UPDATED: $id occurrences=2" ]
  [ "$(_show_field "$id" occurrences)" = "2" ]
  [ "$(_show_field "$id" first_seen)" = "$first" ]
  [[ "$(_show_field "$id" last_seen)" > "$first" ]]
}

@test "SPEC-188-F1: una lección nueva reemplaza a la anterior; sin lección se conserva" {
  id="$(_add --agent "a1" --error "boom" --lesson "primera" | awk '{print $2}')"
  _add --agent "a1" --error "boom" >/dev/null
  [ "$(_show_field "$id" human_lesson)" = "primera" ]
  _add --agent "a1" --error "boom" --lesson "segunda" >/dev/null
  [ "$(_show_field "$id" human_lesson)" = "segunda" ]
}

@test "SPEC-188-F1: el aviso de promoción aparece en la 10ª ocurrencia y no antes" {
  for i in 1 2 3 4 5 6 7 8; do _add --agent "a1" --error "boom" >/dev/null; done
  run _add --agent "a1" --error "boom"
  [ "$output" = "UPDATED: $(_id_of 'a1boom') occurrences=9" ]
  run _add --agent "a1" --error "boom"
  [[ "$output" == *"occurrences=10"* ]]
  [[ "$output" == *"BRIDGE: occurrences >= 10"* ]]
}

@test "SPEC-188-F1: add sin --agent o sin --error falla con exit 1 y nombra la opción" {
  run _add --error "boom"
  [ "$status" -eq 1 ]
  [[ "$output" == *"add requires --agent"* ]]
  run _add --agent "a1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"add requires --error"* ]]
  run _add --agent "a1" --error "x" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
}

@test "SPEC-188-F1: add crea el almacén si no existe (sin init previo)" {
  run _add --agent "a1" --error "boom"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/.claude/external-memory/failure-patterns/patterns.db" ]
}

@test "SPEC-188-F1: init es idempotente y no borra los patrones existentes" {
  _add --agent "a1" --error "boom" >/dev/null
  run bash "$SCRIPT" init
  [ "$status" -eq 0 ]
  [[ "$output" == "OK: schema initialised at "* ]]
  [[ "$(bash "$SCRIPT" list | tail -1)" == "1 pattern(s) found" ]]
}

# ── Comportamiento: show / resolve ────────────────────────────────────────────

@test "SPEC-188-F1: show imprime todos los campos; glob y lección ausentes salen como (none)" {
  id="$(_add --agent "a1" --error "boom" | awk '{print $2}')"
  run bash "$SCRIPT" show "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pattern_id:      $id"* ]]
  [[ "$output" == *"agent:           a1"* ]]
  [[ "$output" == *"error_signature: boom"* ]]
  [[ "$output" == *"file_glob:       (none)"* ]]
  [[ "$output" == *"occurrences:     1"* ]]
  [[ "$output" == *"status:          open"* ]]
  [[ "$output" == *"human_lesson:    (none)"* ]]
  [[ "$output" == *"verified_source: tool:post-tool-failure-log"* ]]
}

@test "SPEC-188-F1: show de un id inexistente informa NOT_FOUND y show sin id es error" {
  bash "$SCRIPT" init >/dev/null
  run bash "$SCRIPT" show deadbeef
  [ "$status" -eq 0 ]
  [ "$output" = "NOT_FOUND: pattern_id=deadbeef" ]
  run bash "$SCRIPT" show
  [ "$status" -eq 1 ]
  [[ "$output" == *"show requires <pattern_id>"* ]]
}

@test "SPEC-188-F1: resolve cambia el estado y con --lesson guarda la lección" {
  id="$(_add --agent "a1" --error "boom" --lesson "vieja" | awk '{print $2}')"
  run bash "$SCRIPT" resolve "$id"
  [ "$output" = "RESOLVED: $id" ]
  [ "$(_show_field "$id" status)" = "resolved" ]
  [ "$(_show_field "$id" human_lesson)" = "vieja" ]
  bash "$SCRIPT" resolve "$id" --lesson "nueva" >/dev/null
  [ "$(_show_field "$id" human_lesson)" = "nueva" ]
}

@test "SPEC-188-F1: resolve con id inexistente, sin id, sin almacén u opción desconocida" {
  run bash "$SCRIPT" resolve abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"Store not initialised"* ]]
  bash "$SCRIPT" init >/dev/null
  run bash "$SCRIPT" resolve deadbeef
  [ "$output" = "NOT_FOUND: pattern_id=deadbeef" ]
  run bash "$SCRIPT" resolve
  [ "$status" -eq 1 ]
  [[ "$output" == *"resolve requires <pattern_id>"* ]]
  run bash "$SCRIPT" resolve deadbeef --bogus
  [ "$status" -eq 1 ]
}

# ── Comportamiento: list / stats ──────────────────────────────────────────────

@test "SPEC-188-F1: list ordena por occurrences descendente y cuenta los patrones" {
  _add --agent "pocos" --error "e1" >/dev/null
  for i in 1 2 3; do _add --agent "muchos" --error "e2" >/dev/null; done
  run bash "$SCRIPT" list
  [ "$(echo "$output" | sed -n 3p | awk '{print $2}')" = "muchos" ]
  [ "$(echo "$output" | sed -n 4p | awk '{print $2}')" = "pocos" ]
  [[ "$output" == *"2 pattern(s) found"* ]]
}

@test "SPEC-188-F1: list filtra por --agent y --status, y sin coincidencias dice 0 entries" {
  id="$(_add --agent "a1" --error "e1" | awk '{print $2}')"
  _add --agent "a2" --error "e2" >/dev/null
  bash "$SCRIPT" resolve "$id" >/dev/null
  run bash "$SCRIPT" list --agent a2
  [[ "$output" == *"1 pattern(s) found"* ]]
  [[ "$output" != *"a1 "* ]]
  run bash "$SCRIPT" list --status resolved
  [[ "$output" == *"a1"* ]]
  [[ "$output" != *"a2"* ]]
  run bash "$SCRIPT" list --agent a2 --status resolved
  [ "$output" = "0 entries" ]
  run bash "$SCRIPT" list --bogus
  [ "$status" -eq 1 ]
}

@test "SPEC-188-F1: list trunca firmas de más de 60 caracteres con puntos suspensivos" {
  long="$(printf 'x%.0s' $(seq 1 70))"
  _add --agent "a1" --error "$long" >/dev/null
  run bash "$SCRIPT" list
  [[ "$output" == *"$(printf 'x%.0s' $(seq 1 60))..."* ]]
  [[ "$output" != *"$(printf 'x%.0s' $(seq 1 61))"* ]]
}

@test "SPEC-188-F1: list sin almacén no falla" {
  run bash "$SCRIPT" list
  [ "$status" -eq 0 ]
  [ "$output" = "0 entries (store not initialised)" ]
}

@test "SPEC-188-F1: stats cuenta por estado y lista el top-3 por ocurrencias" {
  id="$(_add --agent "a1" --error "e1" | awk '{print $2}')"
  _add --agent "a2" --error "e2" >/dev/null
  _add --agent "a3" --error "e3" >/dev/null
  _add --agent "a4" --error "e4" >/dev/null
  for i in 1 2 3; do _add --agent "a4" --error "e4" >/dev/null; done
  for i in 1 2; do _add --agent "a3" --error "e3" >/dev/null; done
  bash "$SCRIPT" resolve "$id" >/dev/null
  run bash "$SCRIPT" stats
  [[ "$output" == *"total:        4"* ]]
  [[ "$output" == *"open:         3"* ]]
  [[ "$output" == *"acknowledged: 0"* ]]
  [[ "$output" == *"resolved:     1"* ]]
  [[ "$output" == *"1. [$(_id_of 'a4e4')] a4 — e4 (4 times)"* ]]
  [[ "$output" == *"2. [$(_id_of 'a3e3')] a3 — e3 (3 times)"* ]]
  [[ "$output" != *"4. ["* ]]
  [[ "$output" == *"SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=1"* ]]
}

@test "SPEC-188-F1: stats sobre almacén vacío dice que no hay patrones" {
  bash "$SCRIPT" init >/dev/null
  run bash "$SCRIPT" stats
  [[ "$output" == *"total:        0"* ]]
  [[ "$output" == *"top-3: (no patterns recorded)"* ]]
}

# ── Comportamiento: flag desactivado y uso ────────────────────────────────────

@test "SPEC-188-F1: con el flag a 0 add no inserta nada, y show/resolve avisan sin tocar datos" {
  bash "$SCRIPT" init >/dev/null
  export SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=0
  run _add --agent "a1" --error "boom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"failure pattern memory is disabled"* ]]
  run bash "$SCRIPT" show abc
  [[ "$output" == *"is disabled"* ]]
  run bash "$SCRIPT" resolve abc
  [[ "$output" == *"is disabled"* ]]
  export SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=1
  run bash "$SCRIPT" stats
  [[ "$output" == *"total:        0"* ]]
}

@test "SPEC-188-F1: stats e init funcionan con el flag a 0 y stats lo refleja" {
  export SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=0
  run bash "$SCRIPT" init
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" stats
  [[ "$output" == *"SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=0"* ]]
}

@test "SPEC-188-F1: sin subcomando exit 1 con uso; subcomando desconocido exit 1 con la lista" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == "Usage: failure-pattern-memory.sh <init|add|list|show|resolve|stats>"* ]]
  run bash "$SCRIPT" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown subcommand: frobnicate. Valid: init add list show resolve stats"* ]]
}

@test "SPEC-188-F1: firma de exactamente 60 caracteres no se trunca; con 61 sí" {
  s60="$(printf 'y%.0s' $(seq 1 60))"
  _add --agent "a1" --error "$s60" >/dev/null
  run bash "$SCRIPT" list
  [[ "$output" == *"$s60"* ]]
  [[ "$output" != *"$s60..."* ]]
  _add --agent "a2" --error "${s60}y" >/dev/null
  run bash "$SCRIPT" list
  [[ "$output" == *"$s60..."* ]]
}
