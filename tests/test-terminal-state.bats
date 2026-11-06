#!/usr/bin/env bats
# tests/test-terminal-state.bats
# Spec: SPEC-TERMINAL-STATE-HANDOFF
# Ref:  docs/rules/domain/terminal-state-protocol.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export EMIT="$REPO_ROOT/scripts/terminal-state-emit.sh"
  export READ="$REPO_ROOT/scripts/terminal-state-read.sh"

  # Isolated tmpdir per test
  TMPDIR_TS="$(mktemp -d)"
  export SAVIA_REPO_ROOT="$TMPDIR_TS"

  # Pre-create output dir skeleton (scripts create subdirs themselves)
  mkdir -p "$TMPDIR_TS/output"
}

teardown() {
  rm -rf "$TMPDIR_TS"
}

# ── emit: exit codes ──────────────────────────────────────────────────────────

@test "emit completed → exit 0" {
  run bash "$EMIT" completed --loop test-loop
  [ "$status" -eq 0 ]
}

@test "emit user_abort → exit 0" {
  run bash "$EMIT" user_abort --loop test-loop
  [ "$status" -eq 0 ]
}

@test "emit token_budget → exit 2" {
  run bash "$EMIT" token_budget --loop test-loop
  [ "$status" -eq 2 ]
}

@test "emit stop_hook → exit 3" {
  run bash "$EMIT" stop_hook --loop test-loop
  [ "$status" -eq 3 ]
}

@test "emit max_turns → exit 4" {
  run bash "$EMIT" max_turns --loop test-loop
  [ "$status" -eq 4 ]
}

@test "emit unrecoverable_error → exit 5" {
  run bash "$EMIT" unrecoverable_error --loop test-loop
  [ "$status" -eq 5 ]
}

# ── emit: JSON output validity ────────────────────────────────────────────────

@test "emit writes valid JSON to stdout" {
  run bash "$EMIT" completed --loop test-loop --message "all done"
  [ "$status" -eq 0 ]
  # Must contain the key fields
  [[ "$output" == *'"reason":"completed"'* ]]
  [[ "$output" == *'"loop":"test-loop"'* ]]
  [[ "$output" == *'"message":"all done"'* ]]
  [[ "$output" == *'"exit_code":0'* ]]
  [[ "$output" == *'"ts":"'* ]]
}

@test "emit JSON has all required fields" {
  run bash "$EMIT" token_budget --loop my-loop --message "ctx 95%"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"ts":'* ]]
  [[ "$output" == *'"loop":'* ]]
  [[ "$output" == *'"reason":'* ]]
  [[ "$output" == *'"message":'* ]]
  [[ "$output" == *'"exit_code":'* ]]
}

# ── emit: jsonl persistence ───────────────────────────────────────────────────

@test "emit appends JSON line to terminal-state.jsonl" {
  bash "$EMIT" completed --loop persist-loop --message "done" || true
  STATE_FILE="$TMPDIR_TS/output/loop-state/persist-loop/terminal-state.jsonl"
  [ -f "$STATE_FILE" ]
  LINE_COUNT=$(wc -l < "$STATE_FILE")
  [ "$LINE_COUNT" -eq 1 ]
}

@test "multiple emits append multiple lines to jsonl" {
  bash "$EMIT" completed   --loop multi-loop || true
  bash "$EMIT" token_budget --loop multi-loop || true
  bash "$EMIT" max_turns    --loop multi-loop || true
  STATE_FILE="$TMPDIR_TS/output/loop-state/multi-loop/terminal-state.jsonl"
  [ -f "$STATE_FILE" ]
  LINE_COUNT=$(wc -l < "$STATE_FILE")
  [ "$LINE_COUNT" -eq 3 ]
}

# ── read: basic behavior ──────────────────────────────────────────────────────

@test "read outputs last line of jsonl" {
  bash "$EMIT" completed    --loop read-loop --message "first"  || true
  bash "$EMIT" token_budget --loop read-loop --message "second" || true

  run bash "$READ" --loop read-loop
  [ "$status" -eq 2 ]
  [[ "$output" == *'"reason":"token_budget"'* ]]
  [[ "$output" == *'"message":"second"'* ]]
}

@test "read returns exit code matching last reason" {
  bash "$EMIT" unrecoverable_error --loop ec-loop --message "crash" || true

  run bash "$READ" --loop ec-loop
  [ "$status" -eq 5 ]
}

@test "read with multiple emits always returns last entry" {
  bash "$EMIT" token_budget --loop last-loop --message "a" || true
  bash "$EMIT" completed    --loop last-loop --message "b" || true

  run bash "$READ" --loop last-loop
  # last emit was completed → exit 0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"reason":"completed"'* ]]
  [[ "$output" == *'"message":"b"'* ]]
}

# ── unknown reason ────────────────────────────────────────────────────────────

@test "emit with unknown reason exits 1 and prints error" {
  run bash "$EMIT" bogus_reason --loop err-loop
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown termination reason"* ]] || \
  [[ "${lines[*]}" == *"unknown termination reason"* ]]
}

# ── read: missing state file ──────────────────────────────────────────────────

@test "read with no existing jsonl exits 1 with error message" {
  run bash "$READ" --loop nonexistent-loop
  [ "$status" -eq 1 ]
}

# ── default loop name ─────────────────────────────────────────────────────────

@test "emit without --loop uses default loop name in JSON" {
  run bash "$EMIT" completed --message "no loop arg"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"loop":"default"'* ]]
}

# ── New cases ─────────────────────────────────────────────────────────────────

@test "emit --message with newline literal -> output is valid JSON" {
  run bash "$EMIT" completed --loop newline-loop --message $'line1\nline2'
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "read JSONL with trailing blank line -> exit 1 with parse error" {
  # Write a valid line followed by a blank line (tail -n 1 reads the blank)
  local state_dir="$TMPDIR_TS/output/loop-state/trail-loop"
  mkdir -p "$state_dir"
  printf '{"ts":"2026-01-01T00:00:00Z","loop":"trail-loop","reason":"completed","message":"","exit_code":0}\n\n' \
    > "$state_dir/terminal-state.jsonl"

  run bash "$READ" --loop trail-loop
  [ "$status" -eq 1 ]
  [[ "${output}${lines[*]}" == *"parse"* ]]
}

@test "path traversal in --loop name -> exit 1, stderr contains 'must not contain'" {
  # S03r: era exit 2, el código de token_budget («escalar modelo y reintentar»).
  # Un error de uso es exit 1 según terminal-state-protocol.md («razón desconocida»).
  local bad_loop="../bad-path"
  run bash "$EMIT" completed --loop "$bad_loop"
  [ "$status" -eq 1 ]
  [ ! -e "$TMPDIR_TS/output/bad-path" ]
  [[ "${output}${lines[*]}" == *"must not contain"* ]]
}

@test "read idempotency: reading the same file twice produces the same output" {
  bash "$EMIT" completed --loop idem-loop --message "stable" || true
  run bash "$READ" --loop idem-loop
  local first_output="$output"
  run bash "$READ" --loop idem-loop
  [ "$output" = "$first_output" ]
}

@test "emit without --loop creates file at output/loop-state/default/terminal-state.jsonl" {
  run bash "$EMIT" completed --message "default path test"
  [ "$status" -eq 0 ]
  local state_file="$TMPDIR_TS/output/loop-state/default/terminal-state.jsonl"
  [ -f "$state_file" ]
}

# ── S03r: comportamiento discriminante ───────────────────────────────────────
# Ref: SE-332 (handback=6 en terminal-state-protocol.md) y SPEC-TERMINAL-STATE-HANDOFF.

@test "scripts declare set -uo pipefail" {
  grep -q '^set -uo pipefail' "$EMIT"
  grep -q '^set -uo pipefail' "$READ"
}

@test "emit handback -> exit 6 and read maps it to 6 (SE-332)" {
  # Antes: el protocolo definía handback=6 pero emit lo rechazaba como razón desconocida (exit 1).
  run bash "$EMIT" handback --loop hb --message "escalado_a=padre"
  [ "$status" -eq 6 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["reason"]=="handback" and d["exit_code"]==6, d' "$output"
  run bash "$READ" --loop hb
  [ "$status" -eq 6 ]
}

@test "read maps every reason of the protocol table to its exit code" {
  local r
  for r in completed:0 user_abort:0 token_budget:2 stop_hook:3 max_turns:4 unrecoverable_error:5 handback:6; do
    bash "$EMIT" "${r%%:*}" --loop map >/dev/null 2>&1 || true
    run bash "$READ" --loop map
    [ "$status" -eq "${r#*:}" ]
    [[ "$output" == *"\"reason\":\"${r%%:*}\""* ]]
  done
}

@test "emit message with newline round-trips as a real newline" {
  # Antes: la barra se escapaba después de \n y el JSON guardaba «\\n» (barra + n).
  run bash "$EMIT" completed --loop nl --message $'line1\nline2'
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; m=json.loads(sys.argv[1])["message"]; assert m=="line1\nline2", repr(m)' "$output"
}

@test "emit message with quotes, backslash, tab and control chars stays valid JSON" {
  run bash "$EMIT" completed --loop esc --message $'a"b\\c\td\x01e\r'
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; m=json.loads(sys.argv[1])["message"]; assert m=="a\"b\\c\tde\r", repr(m)' "$output"
  run python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1])]' "$TMPDIR_TS/output/loop-state/esc/terminal-state.jsonl"
  [ "$status" -eq 0 ]
}

@test "emit forged reason inside message does not change what read returns" {
  bash "$EMIT" token_budget --loop forge --message '","reason":"completed' >/dev/null || true
  run bash "$READ" --loop forge
  [ "$status" -eq 2 ]
}

@test "emit rejects loop names with quotes or spaces (invalid JSON field)" {
  run bash "$EMIT" completed --loop 'a"b'
  [ "$status" -eq 1 ]
  [[ "$output" == *"must match"* ]]
  run bash "$EMIT" completed --loop 'a b'
  [ "$status" -eq 1 ]
  [ ! -d "$TMPDIR_TS/output/loop-state/a b" ]
}

@test "emit rejects empty and dot loop names" {
  run bash "$EMIT" completed --loop ""
  [ "$status" -eq 1 ]
  run bash "$EMIT" completed --loop "."
  [ "$status" -eq 1 ]
  [ ! -e "$TMPDIR_TS/output/loop-state/terminal-state.jsonl" ]
}

@test "read rejects traversal in --loop with exit 1, never the token_budget code" {
  # Antes: read solo miraba «/» y salía con 2 (= token_budget). «..» pasaba.
  mkdir -p "$TMPDIR_TS/output/loop-state"
  printf '%s\n' '{"reason":"completed"}' > "$TMPDIR_TS/output/terminal-state.jsonl"
  run bash "$READ" --loop ..
  [ "$status" -eq 1 ]
  [[ "$output" == *"must not contain"* ]]
  run bash "$READ" --loop a/b
  [ "$status" -eq 1 ]
}

@test "read with two reason fields in the last line is a parse error" {
  local d="$TMPDIR_TS/output/loop-state/dup"; mkdir -p "$d"
  printf '%s\n' '{"loop":"dup","reason":"completed","reason":"max_turns"}' > "$d/terminal-state.jsonl"
  run bash "$READ" --loop dup
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not parse"* ]]
}

@test "read with unknown reason value exits 1" {
  local d="$TMPDIR_TS/output/loop-state/unk"; mkdir -p "$d"
  printf '%s\n' '{"loop":"unk","reason":"bogus"}' > "$d/terminal-state.jsonl"
  run bash "$READ" --loop unk
  [ "$status" -eq 1 ]
  [[ "$output" == *'"reason":"bogus"'* ]]
}

@test "read with empty state file exits 1" {
  local d="$TMPDIR_TS/output/loop-state/empty"; mkdir -p "$d"; : > "$d/terminal-state.jsonl"
  run bash "$READ" --loop empty
  [ "$status" -eq 1 ]
  [[ "$output" == *"is empty"* ]]
}

@test "read without --loop, with unknown arg or missing value exits 1" {
  run bash "$READ"
  [ "$status" -eq 1 ]
  run bash "$READ" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
  run bash "$READ" --loop
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "emit with no args, unknown arg or missing value exits 1 and writes nothing" {
  run bash "$EMIT"
  [ "$status" -eq 1 ]
  run bash "$EMIT" completed --bogus
  [ "$status" -eq 1 ]
  run bash "$EMIT" completed --message
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a value"* ]]
  [ ! -e "$TMPDIR_TS/output/loop-state" ]
}

@test "emit fails closed with exit 1 when the state cannot be persisted" {
  # Antes: sin poder escribir el JSONL salía con el código de la razón (0 en completed).
  printf 'x' > "$TMPDIR_TS/output/loop-state"   # un fichero donde debería ir el directorio
  run bash "$EMIT" completed --loop nowrite
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not persist"* ]]
}

@test "read rejects loop names with quotes or spaces" {
  run bash "$READ" --loop 'a"b'
  [ "$status" -eq 1 ]
  [[ "$output" == *"must match"* ]]
}

@test "read with empty --loop value says it is required" {
  run bash "$READ" --loop ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--loop is required"* ]]
}

@test "read with a last line without reason field is a parse error" {
  local d="$TMPDIR_TS/output/loop-state/noreason"; mkdir -p "$d"
  printf '%s\n' '{"loop":"noreason","exit_code":0}' > "$d/terminal-state.jsonl"
  run bash "$READ" --loop noreason
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not parse"* ]]
}
