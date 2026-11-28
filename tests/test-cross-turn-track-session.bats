#!/usr/bin/env bats
# tests/test-cross-turn-track-session.bats — barrido Python 2026-11-27.
# scripts/cross-turn-correlation/track.py: --session es un identificador, nunca una ruta.

TRACK="${BATS_TEST_DIRNAME}/../scripts/cross-turn-correlation/track.py"

setup() {
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/ws"
  export SAVIA_HARDENING_LOG="$BATS_TEST_TMPDIR/telemetry.jsonl"
  mkdir -p "$CLAUDE_PROJECT_DIR"
}

@test "session con ../ se rechaza y no escribe fuera de output/cross-turn" {
  run python3 "$TRACK" --session "../../../escapado" --turn t1 --text "hola"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/escapado.jsonl" ]
}

@test "session absoluta se rechaza" {
  run python3 "$TRACK" --session "$BATS_TEST_TMPDIR/abs" --turn t1 --text "hola"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/abs.jsonl" ]
}

@test "session válida sigue registrando el turno" {
  run python3 "$TRACK" --session "abc-123_X" --turn t1 --text "hola"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_PROJECT_DIR/output/cross-turn/abc-123_X.jsonl" ]
}
