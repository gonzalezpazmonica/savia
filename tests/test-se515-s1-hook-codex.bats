#!/usr/bin/env bats
# SE-515 S1 — refutación Codex ronda 2 (PR #1523), parte del hook de Claude Code:
# sin fila de emisión escrita no se inyectan criterios (AC-3) y el interruptor off
# no depende de jq (AC-16). Cada test reproduce un hallazgo del informe.
# Spec: docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md (AC-3, AC-16)
# HOOK_UNDER_TEST permite ejecutar la suite contra otra versión del hook.

HOOK="${HOOK_UNDER_TEST:-.claude/hooks/learning-recall-hook.sh}"

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  unset SAVIA_LEARNING_APPLIED SAVIA_LEARNING_RECALL SCL_RECALL_TIMEOUT_S SCL_CRITERIO_PATH
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/scripts"
  export CLAUDE_PROJECT_DIR="$PROJ"
  export SCL_EMISSION_LOG="$BATS_TEST_TMPDIR/emission.jsonl"
}

fake_recall() { printf '#!/usr/bin/env bash\n%s\n' "$1" > "$PROJ/scripts/learning-recall.sh"; }
HITS='{"effective_hits":[{"criterion_id":"CRIT-001","principle":"Dato soberano"}]}'
PROMPT='{"content":"como publico la rama del sprint"}'
# hook: stdout del hook (lo que se inyecta); stderr aparte en $BATS_TEST_TMPDIR/stderr.
hook() { run bash -c 'printf "%s" "$1" | bash "$0" 2>"$2"' "$HOOK" "$PROMPT" "$BATS_TEST_TMPDIR/stderr"; }

@test "P1 codex: log de emisión no escribible (/dev/full) → el hook no inyecta criterios" {
  [ -w /dev/full ] || skip "sin /dev/full"
  fake_recall "printf '%s' '$HITS'"
  SCL_EMISSION_LOG=/dev/full hook
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "inyectó sin traza: $output"; return 1; }
  grep -q 'no se inyectan criterios' "$BATS_TEST_TMPDIR/stderr"
}

@test "P1 codex: directorio del log no creable → el hook no inyecta criterios" {
  fake_recall "printf '%s' '$HITS'"
  printf 'x' > "$BATS_TEST_TMPDIR/file"
  SCL_EMISSION_LOG="$BATS_TEST_TMPDIR/file/sub/emission.jsonl" hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "P1 codex (control): log escribible → inyecta y la fila end emitted=true precede a la salida" {
  fake_recall "printf '%s' '$HITS'"
  hook
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'CRIT-001'
  [ "$(jq -rc 'select(.phase=="end") | .emitted' "$SCL_EMISSION_LOG" | tail -1)" = "true" ]
}

@test "P2 codex: interruptor off sin jq → sigue inyectando el criterio (comportamiento anterior)" {
  fake_recall "printf '%s' '$HITS'"
  local nojq="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$nojq"
  printf '#!/bin/sh\nexit 127\n' > "$nojq/jq"; chmod +x "$nojq/jq"
  run env PATH="$nojq:$PATH" SAVIA_LEARNING_APPLIED=off bash -c 'printf "%s" "$1" | bash "$0"' "$HOOK" "$PROMPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'CRIT-001' || { echo "sin inyección: '$output'"; return 1; }
}

@test "P2 codex: aciertos sin criterion_id → bad_output y sin inyección (paridad con el guard)" {
  fake_recall "printf '%s' '{\"effective_hits\":[{}]}'"
  hook
  [ -z "$output" ]
  [ "$(jq -r 'select(.phase=="end") | .reason' "$SCL_EMISSION_LOG" | tail -1)" = "bad_output" ]
}
