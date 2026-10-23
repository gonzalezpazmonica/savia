#!/usr/bin/env bats
# BATS tests for scripts/telemetry-tail-sample.sh
# SE-313 S4 — sampling tail + retención + rotación + redacción.
# Ref: docs/propuestas/SE-313-observabilidad-trazabilidad-agentes-eu-ai-act.md

SCRIPT="scripts/telemetry-tail-sample.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export SAVIA_TELEMETRY_FILE="${BATS_TEST_TMPDIR:-/tmp}/telemetry-s4.jsonl"
  rm -f "${SAVIA_TELEMETRY_FILE}" "${SAVIA_TELEMETRY_FILE}."* 2>/dev/null || true
}

teardown() {
  rm -f "${SAVIA_TELEMETRY_FILE:-}" "${SAVIA_TELEMETRY_FILE:-}."* 2>/dev/null || true
  cd /
}

@test "script exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "passes bash -n syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "check sin eventos no falla" {
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
}

@test "check valida líneas con schema correcto" {
  bash scripts/otel-emit.sh agent.started agent_name=x >/dev/null
  bash scripts/otel-emit.sh dispatch.resolved agent_name=y >/dev/null
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"telemetry-events.jsonl: 2 lines"* ]]
}

@test "redact degrada a solo ts+event con SAVIA_TELEMETRY_REDACT=1" {
  bash scripts/otel-emit.sh agent.started agent_name=secret-agent tier=mid >/dev/null
  run bash "$SCRIPT" redact
  [ "$status" -eq 0 ]
  run jq -e '.event == "agent.started" and (has("agent_name") | not) and (has("tier") | not) and .schema == "savia.event/1.0" and .ts' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "rotate no muta cuando está bajo el umbral" {
  bash scripts/otel-emit.sh agent.started agent_name=x >/dev/null
  run bash "$SCRIPT" rotate
  [ "$status" -eq 0 ]
  # No debe haber fichero rotado
  [[ ! -f "${SAVIA_TELEMETRY_FILE}."* ]]
}

@test "usage inválido falla" {
  run bash "$SCRIPT" no-such-mode
  [ "$status" -eq 2 ]
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# Proyecto temporal con política propia; el script lee CLAUDE_PROJECT_DIR/config.
mk_project() {
  PROJ="$(mktemp -d)"
  mkdir -p "$PROJ/config" "$PROJ/output"
  printf 'retention_days: %s\nrotation_lines: %s\nrotation_max_files: %s\n' "${1:-180}" "${2:-10000}" "${3:-20}" \
    > "$PROJ/config/telemetry-policies.yaml"
  EV="$PROJ/output/telemetry-events.jsonl"
  export CLAUDE_PROJECT_DIR="$PROJ" SAVIA_TELEMETRY_FILE="$EV"
}

ev_line() { printf '{"schema":"savia.event/1.0","ts":"2026-01-01T00:00:00Z","event":"e%s","agent_name":"secreto"}\n' "$1"; }

@test "usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "check at exactly the rotation threshold is not a violation (boundary)" {
  mk_project 180 3
  for i in 1 2 3; do ev_line $i >> "$EV"; done
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 lines (rotation_threshold=3)"* ]]
  [[ "$output" != *"VIOLATION"* ]]
}

@test "check over the rotation threshold reports VIOLATION and exits 1" {
  mk_project 180 3
  for i in 1 2 3 4; do ev_line $i >> "$EV"; done
  run bash "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION: over rotation threshold"* ]]
}

@test "check flags a line with wrong schema and exits 1" {
  mk_project
  ev_line 1 >> "$EV"
  echo '{"schema":"otro/9","event":"x"}' >> "$EV"
  run bash "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 line(s) con schema incorrecto"* ]]
}

@test "check reads retention and rotation from the policy file" {
  mk_project 42 7 5
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"retention_days=42 rotation_lines=7"* ]]
}

@test "check falls back to defaults when the policy yaml is invalid" {
  mk_project
  printf 'retention_days: [unclosed\n' > "$PROJ/config/telemetry-policies.yaml"
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"retention_days=180 rotation_lines=10000"* ]]
}

@test "check with missing events file reports no events and exits 0" {
  mk_project
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no existe"* ]]
}

@test "rotate over the threshold moves the file to a timestamped name" {
  mk_project 180 3
  for i in 1 2 3 4; do ev_line $i >> "$EV"; done
  run bash "$SCRIPT" rotate
  [ "$status" -eq 0 ]
  [[ "$output" == rotated:* ]]
  [[ ! -f "$EV" ]]
  rotated=("$EV".*)
  [ "${#rotated[@]}" -eq 1 ]
  [ "$(wc -l < "${rotated[0]}")" -eq 4 ]
}

@test "rotate at exactly the threshold does not rotate (boundary)" {
  mk_project 180 3
  for i in 1 2 3; do ev_line $i >> "$EV"; done
  run bash "$SCRIPT" rotate
  [ "$status" -eq 0 ]
  [[ -f "$EV" ]]
  [ -z "$output" ]
}

@test "rotate with nonexistent events file is a no-op" {
  mk_project
  run bash "$SCRIPT" rotate
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "redact keeps schema ts event and drops every other attribute on every line" {
  mk_project
  for i in 1 2 3; do ev_line $i >> "$EV"; done
  run bash "$SCRIPT" redact
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$EV")" -eq 3 ]
  run jq -e -s 'all(.[]; keys == ["event","schema","ts"])' "$EV"
  [ "$status" -eq 0 ]
  ! grep -q secreto "$EV"
}

@test "redact leaves the file untouched when it contains invalid JSON" {
  mk_project
  ev_line 1 >> "$EV"
  echo 'esto no es json' >> "$EV"
  before="$(cksum < "$EV")"
  run bash "$SCRIPT" redact
  [ "$(cksum < "$EV")" = "$before" ]
  grep -q secreto "$EV"
}

@test "prune removes rotated files older than retention_days and keeps recent ones" {
  mk_project 10 10000 20
  ev_line 1 > "$EV.old"; touch -d "20 days ago" "$EV.old"
  ev_line 2 > "$EV.new"; touch -d "2 days ago" "$EV.new"
  ev_line 3 > "$EV"; touch -d "400 days ago" "$EV"
  run bash "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"pruned: $EV.old"* ]]
  [[ ! -e "$EV.old" ]]
  [[ -f "$EV.new" ]]
  # el fichero activo nunca se purga, aunque sea antiguo
  [[ -f "$EV" ]]
}

@test "prune caps rotated files at rotation_max_files deleting the oldest first" {
  mk_project 180 10000 2
  for n in 1 2 3 4; do
    ev_line $n > "$EV.f$n"
    touch -d "$((10 - n)) days ago" "$EV.f$n"
  done
  run bash "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [[ ! -e "$EV.f1" && ! -e "$EV.f2" ]]
  [[ -f "$EV.f3" && -f "$EV.f4" ]]
}

@test "prune with empty directory of rotated files does nothing" {
  mk_project
  ev_line 1 > "$EV"
  run bash "$SCRIPT" prune
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ -f "$EV" ]]
}

@test "unknown mode prints usage on stdout and exits 2 without touching the file" {
  mk_project
  ev_line 1 > "$EV"
  run bash "$SCRIPT" borrar-todo
  [ "$status" -eq 2 ]
  [[ "$output" == usage:* ]]
  [[ -f "$EV" ]]
}
