#!/usr/bin/env bats
# scripts/lib/guard-decision-log.sh: formato JSON, saneado del motivo y del guard,
# truncado a 64, veredicto desconocido y fallo de escritura (devuelve 0 siempre).

setup() {
  LIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/scripts/lib/guard-decision-log.sh"
  CASE_ROOT=$(mktemp -d /tmp/savia-gdl.XXXXXX)
  export CLAUDE_PROJECT_DIR="$CASE_ROOT"
  LOG="$CASE_ROOT/output/guard-decisions"
}

teardown() {
  if [[ "${CASE_ROOT:-}" == /tmp/savia-gdl.* ]]; then
    chmod -R u+w "$CASE_ROOT"
    rm -rf -- "$CASE_ROOT"
  fi
}

gdl() { bash -c 'source "$1"; shift; guard_decision_log "$@"' _ "$LIB" "$@"; }

@test "una línea JSON con ts ISO-8601 UTC, guard, verdict y reason" {
  run gdl mi-guard allow motivo-uno
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$LOG/mi-guard.jsonl")" -eq 1 ]
  run jq -r '[.guard,.verdict,.reason] | join(" ")' "$LOG/mi-guard.jsonl"
  [ "$output" = "mi-guard allow motivo-uno" ]
  run jq -r '.ts' "$LOG/mi-guard.jsonl"
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "el motivo se sanea a [a-z0-9-] y no conserva la orden" {
  run gdl g block 'Cp X dir/* "$(rm)" ; ñ'
  [ "$status" -eq 0 ]
  run jq -r '.reason' "$LOG/g.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[a-z0-9-]+$ ]]
  [[ "$output" != *"dir/"* ]]
}

@test "el motivo se trunca a 64 caracteres" {
  run gdl g allow "$(printf 'a%.0s' {1..100})"
  [ "$status" -eq 0 ]
  run jq -r '.reason | length' "$LOG/g.jsonl"
  [ "$output" -eq 64 ]
}

@test "el nombre del guard se sanea: no sale del directorio de medición" {
  run gdl '../../fuera' allow x
  [ "$status" -eq 0 ]
  [ ! -e "$CASE_ROOT/fuera.jsonl" ]
  [ -f "$LOG/------fuera.jsonl" ]
}

@test "veredicto desconocido no escribe nada" {
  run gdl g maybe x
  [ "$status" -eq 0 ]
  [ ! -e "$LOG/g.jsonl" ]
}

@test "fallo de escritura devuelve 0 y no escribe" {
  mkdir -p "$LOG"
  chmod a-w "$LOG"
  run gdl g allow x
  [ "$status" -eq 0 ]
  [ ! -e "$LOG/g.jsonl" ]
}
