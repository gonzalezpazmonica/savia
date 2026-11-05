#!/usr/bin/env bats
# test-transcriptor.bats — SE-308 Savia Transcriptor: integracion de scripts
# Ref: scripts/transcriptor-scan.sh — reuniones transcritas y pendientes SE-308

SCRIPT="scripts/transcriptor-scan.sh"

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export SAVIA_TRANSCRIPTOR_DIR="$(mktemp -d)"
  mkdir -p "$SAVIA_TRANSCRIPTOR_DIR/reuniones/2026-08-04-09-15"
  mkdir -p "$SAVIA_TRANSCRIPTOR_DIR/reuniones/2026-08-04-11-00"
  echo '{"digested": false, "transcribed": true}' > "$SAVIA_TRANSCRIPTOR_DIR/reuniones/2026-08-04-09-15/meta.json"
  echo '{"digested": true, "transcribed": true}' > "$SAVIA_TRANSCRIPTOR_DIR/reuniones/2026-08-04-11-00/meta.json"
}

teardown() {
  rm -rf "$SAVIA_TRANSCRIPTOR_DIR"
}

@test "SE-308: scan lista solo reuniones sin digerir" {
  run bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-04-09-15"* ]]
  [[ "$output" != *"2026-08-04-11-00"* ]]
}

@test "S03n null: meta.json no se lista y conserva el fichero" {
  mk_meeting "2026-08-13" 'null'
  run --separate-stderr bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-08-04-09-15" ]
  [ "$stderr" = "" ]
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1])) is None' "$SAVIA_TRANSCRIPTOR_DIR/$R/2026-08-13/meta.json"
  run bash "$REPO_ROOT/$SCRIPT" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-13 digested=? transcribed=? meta=ilegible"* ]]
}

@test "S03n error empty: meta.json vacío no se toma por reunión transcrita" {
  mk_meeting "2026-08-14" "" transcript.md
  : > "$SAVIA_TRANSCRIPTOR_DIR/$R/2026-08-14/meta.json"
  run --separate-stderr bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-08-04-09-15" ]
  [[ "$stderr" == *"ERROR: meta.json ilegible en 2026-08-14"* ]]
}

@test "S03n error nonexistent: reuniones es un fichero y no se intenta leerlo como directorio" {
  local invalid="$SAVIA_TRANSCRIPTOR_DIR/invalido"
  mkdir -p "$invalid"
  : > "$invalid/reuniones"
  SAVIA_TRANSCRIPTOR_DIR="$invalid" run --separate-stderr bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == "No hay reuniones todavia en "* ]]
}

@test "SE-308: scan --all lista todas con estado" {
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"2026-08-04-09-15 digested=False"* ]]
  [[ "$output" == *"2026-08-04-11-00 digested=True"* ]]
}

@test "SE-308: scan sin directorio no falla" {
  export SAVIA_TRANSCRIPTOR_DIR="/tmp/inexistente-transcriptor-$RANDOM"
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
}

@test "SE-308: mark-digested marca la reunion" {
  bash "$REPO_ROOT/scripts/transcriptor-mark-digested.sh" 2026-08-04-09-15
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == "" ]] || [[ "$output" == *"No hay reuniones"* ]]
}

@test "SE-308: mark-digested requiere argumento" {
  run bash "$REPO_ROOT/scripts/transcriptor-mark-digested.sh"
  [ "$status" -ne 0 ]
}

@test "SE-308: mark-digested falla con carpeta inexistente" {
  run bash "$REPO_ROOT/scripts/transcriptor-mark-digested.sh" 2099-01-01-00-00
  [ "$status" -ne 0 ]
}

# ── S03n: comportamiento discriminante de transcriptor-scan ─────────────────

bats_require_minimum_version 1.5.0

R="reuniones"
mk_meeting() {  # mk_meeting <nombre> [meta-json] [fichero-transcripción]
  mkdir -p "$SAVIA_TRANSCRIPTOR_DIR/$R/$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$SAVIA_TRANSCRIPTOR_DIR/$R/$1/meta.json"
  [[ -n "${3:-}" ]] && : > "$SAVIA_TRANSCRIPTOR_DIR/$R/$1/$3"
  return 0
}

@test "S03n: en grabación (transcribed false) va a stderr como PENDIENTE, nunca a stdout" {
  mk_meeting "2026-08-05-10-00" '{"digested": false, "transcribed": false}'
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-08-04-09-15" ]
  [ "$stderr" = "PENDIENTE: 2026-08-05-10-00 (sin transcribir todavia)" ]
}

@test "S03n: sin meta.json cuenta como transcrita solo si hay transcript.md o .vtt" {
  mk_meeting "2026-08-06-a" "" "transcript.vtt"
  mk_meeting "2026-08-06-b" "" "transcript.md"
  mk_meeting "2026-08-06-c" "" "notas.txt"
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '2026-08-04-09-15\n2026-08-06-a\n2026-08-06-b')" ]
  [ "$stderr" = "PENDIENTE: 2026-08-06-c (sin transcribir todavia)" ]
}

@test "S03n: la clave transcribed manda sobre la presencia del fichero" {
  mk_meeting "2026-08-07" '{"transcribed": false}' "transcript.md"
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$output" = "2026-08-04-09-15" ]
  [[ "$stderr" == *"PENDIENTE: 2026-08-07"* ]]
}

@test "S03n: solo el booleano true cuenta (\"true\" en texto no es digerida ni transcrita)" {
  mk_meeting "2026-08-08" '{"digested": "true", "transcribed": true}'
  mk_meeting "2026-08-09" '{"digested": false, "transcribed": "true"}'
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$output" = "$(printf '2026-08-04-09-15\n2026-08-08')" ]
  [[ "$stderr" == *"PENDIENTE: 2026-08-09"* ]]
}

@test "S03n: meta.json ilegible o que no es objeto da ERROR en stderr y no se lista" {
  mk_meeting "2026-08-10" '{roto'
  mk_meeting "2026-08-11" '[1, 2]'
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-08-04-09-15" ]
  [[ "$stderr" == *"ERROR: meta.json ilegible en 2026-08-10"* ]]
  [[ "$stderr" == *"ERROR: meta.json ilegible en 2026-08-11: no es un objeto JSON"* ]]
}

@test "S03n: --all marca la ilegible con ? y el resto con su estado real" {
  mk_meeting "2026-08-10" '{roto'
  mk_meeting "2026-08-12" "" "transcript.md"
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh" --all
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    '2026-08-04-09-15 digested=False transcribed=True' \
    '2026-08-04-11-00 digested=True transcribed=True' \
    '2026-08-10 digested=? transcribed=? meta=ilegible' \
    '2026-08-12 digested=False transcribed=True')" ]
}

@test "S03n: ignora carpetas ocultas y ficheros sueltos en reuniones/" {
  mk_meeting ".tmp-grabando" '{"digested": false, "transcribed": true}'
  : > "$SAVIA_TRANSCRIPTOR_DIR/$R/suelto.txt"
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$output" = "2026-08-04-09-15" ]
}

@test "S03n: argumento desconocido es error de uso (exit 2) y --help sale 0" {
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh" --todo
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento no reconocido: --todo"* ]]
  run bash "$REPO_ROOT/scripts/transcriptor-scan.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"transcriptor-scan.sh"* ]]
}

@test "S03n: sin directorio de reuniones avisa por stderr y no lista nada" {
  export SAVIA_TRANSCRIPTOR_DIR="$SAVIA_TRANSCRIPTOR_DIR/no-hay"
  run --separate-stderr bash "$REPO_ROOT/scripts/transcriptor-scan.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [[ "$stderr" == "No hay reuniones todavia en "* ]]
}
