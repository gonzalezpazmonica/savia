#!/usr/bin/env bats
# BATS tests for .claude/hooks/sycophancy-strip.sh
# Ref: radical-honesty.md (Rule #24), SPEC-192 (anti-adulación), Layer 1 hook.
# SE-339: cobertura de hook crítico.
SCRIPT=".claude/hooks/sycophancy-strip.sh"

setup() { cd "$BATS_TEST_DIRNAME/.."; }
teardown() { cd /; }

@test "existe" { [[ -f "$SCRIPT" ]]; }
@test "usa set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "pasa bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "referencia SPEC-192 / Rule #24" {
  run grep -c 'SPEC-192' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "detecta patrones de adulación via corpus externo" {
  # Layer 1 usa regex-patterns.json (SPEC-192); el hook debe referenciarlo
  run grep -ciE 'regex-patterns|anti-adulation|adulation' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "soporta modos off/shadow/warn/strip/block" {
  run grep -cE 'SAVIA_ANTIADULATION_LAYER1|shadow|strip|block' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "master switch SAVIA_ANTIADULATION=off" {
  run grep -c 'SAVIA_ANTIADULATION' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
# --- Comportamiento real: texto por stdin, modo por entorno, telemetría en proyecto temporal ---

run_hook() {  # $1 = modo, $2 = texto o JSON
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$CLAUDE_PROJECT_DIR"
  LOG="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  run bash -c 'printf "%s" "$2" | SAVIA_ANTIADULATION_LAYER1="$1" bash "$0" 2>"$BATS_TEST_TMPDIR/err"' "$SCRIPT" "$1" "$2"
}
decision() { jq -r .decision "$LOG" | tail -1; }

@test "block: adulacion al inicio (score 95, pos 0) sale 2 con aviso y registra BLOCKED" {
  run_hook block "Great question! Here is the answer."
  [ "$status" -eq 2 ]
  grep -q 'position 0 (score=95)' "$BATS_TEST_TMPDIR/err"
  [ "$(decision)" = "BLOCKED" ]
}

@test "block: texto sin adulacion pasa con exit 0 y PASS" {
  run_hook block "El sprint va al 40%. AB#1023 bloqueado."
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(decision)" = "PASS" ]
  [ "$(jq -r .score "$LOG")" = "0" ]
}

@test "block: patron sutil (score 50) no llega al umbral 85: exit 0 BELOW_BLOCK_THRESHOLD" {
  run_hook block "Texto neutro. Completamente de acuerdo con eso."
  [ "$status" -eq 0 ]
  [ "$(decision)" = "BELOW_BLOCK_THRESHOLD" ]
  [ "$(jq -r .score "$LOG")" = "50" ]
  [ "$(jq -r .position "$LOG")" = "14" ]
}

@test "block: adulacion en medio del texto (no es apertura) no cuenta: PASS" {
  run_hook block "Este es un informe largo sobre el estado del sprint actual.
Great question about it."
  [ "$status" -eq 0 ]
  [ "$(decision)" = "PASS" ]
}

@test "strip: devuelve el texto sin la apertura y registra STRIPPED" {
  run_hook strip "Great question! Here is the answer."
  [ "$status" -eq 0 ]
  [ "$output" = "Here is the answer." ]
  [ "$(decision)" = "STRIPPED" ]
}

@test "strip: texto limpio no emite nada" {
  run_hook strip "Velocity cayo 12%."
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "warn: aviso por stderr con score y categoria, stdout vacio, exit 0" {
  run_hook warn "You're absolutely right, lo reviso."
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'WARN: pattern matched (score=95 pos=0 category=obvious)' "$BATS_TEST_TMPDIR/err"
  [ "$(decision)" = "WARN" ]
}

@test "shadow (por defecto): solo telemetria, sin stderr ni cambio de exit" {
  run_hook shadow "Great point, gracias."
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/err" ]
  [ "$(decision)" = "SHADOW_DETECTED" ]
}

@test "modo desconocido cae a shadow" {
  run_hook inventado "Great idea!"
  [ "$status" -eq 0 ]
  [ "$(jq -r .mode "$LOG")" = "shadow" ]
}

@test "modo off y master switch off: no escriben telemetria" {
  run_hook off "El sprint va al 40%."
  [ "$status" -eq 0 ]
  [ ! -e "$LOG" ]
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj2"; mkdir -p "$CLAUDE_PROJECT_DIR"
  run bash -c 'printf "Great question!" | SAVIA_ANTIADULATION=off SAVIA_ANTIADULATION_LAYER1=block bash "$0"' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl" ]
}

@test "entrada vacia sale 0 sin telemetria" {
  run_hook block ""
  [ "$status" -eq 0 ]
  [ ! -e "$LOG" ]
}

@test "envoltorio PostToolUse: analiza tool_response.content, no el JSON crudo" {
  env_json='{"tool_response":{"content":[{"type":"text","text":"Great question! Respuesta."}]}}'
  run_hook block "$env_json"
  [ "$status" -eq 2 ]
  [ "$(decision)" = "BLOCKED" ]
}

@test "envoltorio sin texto del agente registra NO_TEXT y sale 0" {
  run_hook block '{"tool_response":{"status":"async_launched"}}'
  [ "$status" -eq 0 ]
  [ "$(decision)" = "NO_TEXT" ]
}

@test "patrones inexistentes: fail-open con FAIL_OPEN y exit 0 aunque haya adulacion" {
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/proj3"; mkdir -p "$CLAUDE_PROJECT_DIR"
  LOG="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  run bash -c 'printf "Great question!" | SAVIA_ANTIADULATION_PATTERNS=/no/existe.json SAVIA_ANTIADULATION_LAYER1=block bash "$0"' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(decision)" = "FAIL_OPEN" ]
  [ "$(jq -r .category "$LOG")" = "detector_or_patterns_missing" ]
}

@test "telemetria registra draft_len del texto" {
  run_hook warn "Good point."
  [ "$(jq -r .draft_len "$LOG")" = "11" ]
}

@test "block: el umbral de posicion usa la posicion real (patron propio tras el caracter 50 no bloquea)" {
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/projp"; mkdir -p "$CLAUDE_PROJECT_DIR"
  LOG="$CLAUDE_PROJECT_DIR/output/anti-adulation-telemetry.jsonl"
  echo '{"version":1,"obvious":["great question"],"subtle":[]}' > "$BATS_TEST_TMPDIR/pat.json"
  run bash -c 'printf "%s" "$1" | SAVIA_ANTIADULATION_PATTERNS="$2" SAVIA_ANTIADULATION_LAYER1=block bash "$0" 2>/dev/null' "$SCRIPT" "great question: arranca ya" "$BATS_TEST_TMPDIR/pat.json"
  [ "$status" -eq 2 ]
  run bash -c 'printf "%s" "$1" | SAVIA_ANTIADULATION_PATTERNS="$2" SAVIA_ANTIADULATION_LAYER1=block bash "$0" 2>/dev/null' "$SCRIPT" "Informe largo de contexto del sprint con muchas palabras antes. great question" "$BATS_TEST_TMPDIR/pat.json"
  [ "$status" -eq 0 ]
  [ "$(decision)" = "BELOW_BLOCK_THRESHOLD" ]
  [ "$(jq -r .position "$LOG" | tail -1)" -ge 50 ]
}
