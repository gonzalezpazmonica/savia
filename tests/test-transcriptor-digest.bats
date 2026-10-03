#!/usr/bin/env bats
# test-transcriptor-digest.bats — calibracion SE-376 de la skill transcriptor-digest
# Ref: .claude/skills/transcriptor-digest/SKILL.md
# Reuniones sinteticas en mktemp -d (meta.json con la forma que escribe
# MeetingStore.new_session y el postprocesador de la app de grabacion). El riesgo que
# se vigila: marcar como digerida una reunion que no se digirio (se pierde sin
# aviso) o declarar exito sin haber escrito nada.

SCRIPT="scripts/transcriptor-mark-digested.sh"
SCAN="scripts/transcriptor-scan.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MARK_SH="$REPO_ROOT/$SCRIPT"
  SCAN_SH="$REPO_ROOT/$SCAN"
  TMPDIR_TEST="$(mktemp -d)"
  export SAVIA_TRANSCRIPTOR_DIR="$TMPDIR_TEST/transcriptor"
  M="$SAVIA_TRANSCRIPTOR_DIR/reuniones"
  mkdir -p "$M"
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

# meeting <nombre> <json-meta>: crea la carpeta de una reunion sintetica
meeting() {
  mkdir -p "$M/$1"
  printf '%s\n' "$2" > "$M/$1/meta.json"
}

# field <nombre> <clave>: valor de una clave del meta.json (repr de Python)
field() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$M/$1/meta.json" "$2"
}

@test "objetivos usan set -uo pipefail" {
  grep -q '^set -uo pipefail' "$MARK_SH"
  grep -q '^set -uo pipefail' "$SCAN_SH"
}

@test "scan: lista solo reuniones transcritas y sin digerir" {
  meeting a '{"digested": false, "transcribed": true}'
  meeting b '{"digested": true, "transcribed": true}'
  run bash "$SCAN_SH"
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

@test "scan: reunion en grabacion (transcribed false) no se ofrece para digerir y avisa" {
  meeting rec '{"digested": false, "transcribed": false, "captures": 0}'
  run bash -c "bash '$SCAN_SH' 2>'$TMPDIR_TEST/err'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q "PENDIENTE: rec" "$TMPDIR_TEST/err"
}

@test "scan: sin directorio de reuniones sale 0 y stdout queda vacio (no contamina la lista)" {
  export SAVIA_TRANSCRIPTOR_DIR="$TMPDIR_TEST/inexistente"
  run bash -c "bash '$SCAN_SH' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "scan: directorio vacio (empty) no lista nada" {
  run bash "$SCAN_SH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "scan: meta.json ilegible no se lista como lista para digerir y emite error" {
  meeting rota '{"digested": fal'
  run bash -c "bash '$SCAN_SH' 2>'$TMPDIR_TEST/err'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q "ERROR: meta.json ilegible en rota" "$TMPDIR_TEST/err"
}

@test "scan: sin meta.json pero con transcripcion se lista; sin nada queda pendiente" {
  mkdir -p "$M/legado" "$M/vacia"
  echo "texto" > "$M/legado/transcript.md"
  run bash -c "bash '$SCAN_SH' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "legado" ]
}

@test "scan: digested no booleano (string \"true\") no cuenta como digerida" {
  meeting s '{"digested": "true", "transcribed": true}'
  run bash "$SCAN_SH"
  [ "$output" = "s" ]
}

@test "scan --all: muestra estado digested y transcribed de cada reunion" {
  meeting a '{"digested": false, "transcribed": true}'
  meeting b '{"digested": true, "transcribed": true}'
  meeting c '{"digested": false, "transcribed": false}'
  run bash "$SCAN_SH" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"a digested=False transcribed=True"* ]]
  [[ "$output" == *"b digested=True transcribed=True"* ]]
  [[ "$output" == *"c digested=False transcribed=False"* ]]
}

@test "scan: argumento invalido se rechaza con exit 2" {
  run bash "$SCAN_SH" --al
  [ "$status" -eq 2 ]
}

@test "scan: ruta con espacios y comilla simple funciona" {
  export SAVIA_TRANSCRIPTOR_DIR="$TMPDIR_TEST/o'brien dir"
  M="$SAVIA_TRANSCRIPTOR_DIR/reuniones"
  meeting a '{"digested": true, "transcribed": true}'
  meeting b '{"digested": false, "transcribed": true}'
  run bash "$SCAN_SH"
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

@test "scan: muchas reuniones (large, 300) en orden y sin perder ninguna" {
  for i in $(seq -w 1 300); do meeting "2026-01-01-$i" '{"digested": false, "transcribed": true}'; done
  meeting zz '{"digested": true, "transcribed": true}'
  run bash "$SCAN_SH"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 300 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "2026-01-01-001" ]
}

@test "scan: sin python3 falla en vez de listar todo como no digerido" {
  meeting a '{"digested": true, "transcribed": true}'
  mkdir -p "$TMPDIR_TEST/bin"
  for t in bash dirname basename cat; do ln -s "$(command -v $t)" "$TMPDIR_TEST/bin/$t"; done
  run env PATH="$TMPDIR_TEST/bin" bash "$SCAN_SH"
  [ "$status" -ne 0 ]
  [[ "$output" != "a" ]]
}

@test "mark: marca digerida y conserva el resto de campos" {
  meeting a '{"digested": false, "transcribed": true, "language": "es", "captures": 7}'
  run bash "$MARK_SH" a
  [ "$status" -eq 0 ]
  [ "$(field a digested)" = "True" ]
  [ "$(field a language)" = "es" ]
  [ "$(field a captures)" = "7" ]
  [ "$(field a digested_at)" != "None" ]
  run bash "$SCAN_SH"
  [ -z "$output" ]
}

@test "mark: acepta ruta absoluta con espacios y comilla simple" {
  export SAVIA_TRANSCRIPTOR_DIR="$TMPDIR_TEST/o'brien dir"
  M="$SAVIA_TRANSCRIPTOR_DIR/reuniones"
  meeting a '{"digested": false, "transcribed": true}'
  run bash "$MARK_SH" "$M/a"
  [ "$status" -eq 0 ]
  [ "$(field a digested)" = "True" ]
}

@test "mark: reunion sin transcribir se rechaza (block) y no se toca" {
  meeting rec '{"digested": false, "transcribed": false}'
  before="$(cat "$M/rec/meta.json")"
  run bash "$MARK_SH" rec
  [ "$status" -eq 3 ]
  [ "$(cat "$M/rec/meta.json")" = "$before" ]
}

@test "mark --force: marca una reunion sin transcribir cuando se pide expresamente" {
  meeting rec '{"digested": false, "transcribed": false}'
  run bash "$MARK_SH" --force rec
  [ "$status" -eq 0 ]
  [ "$(field rec digested)" = "True" ]
}

@test "mark: meta.json ilegible falla (error) sin declarar exito ni tocar el fichero" {
  meeting rota '{"digested": fal'
  run bash "$MARK_SH" rota
  [ "$status" -ne 0 ]
  [[ "$output" != *"Marcada como digerida"* ]]
  [ "$(cat "$M/rota/meta.json")" = '{"digested": fal' ]
}

@test "mark: meta.json que no es un objeto (null) falla sin declarar exito" {
  meeting n 'null'
  run bash "$MARK_SH" n
  [ "$status" -ne 0 ]
  [[ "$output" != *"Marcada como digerida"* ]]
}

@test "mark: sin python3 falla en vez de declarar exito" {
  meeting a '{"digested": false, "transcribed": true}'
  mkdir -p "$TMPDIR_TEST/bin"
  for t in bash dirname basename cat; do ln -s "$(command -v $t)" "$TMPDIR_TEST/bin/$t"; done
  run env PATH="$TMPDIR_TEST/bin" bash "$MARK_SH" a
  [ "$status" -ne 0 ]
  [[ "$output" != *"Marcada como digerida"* ]]
}

@test "mark: sin argumento falla con uso" {
  run bash "$MARK_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "mark: carpeta inexistente falla" {
  run bash "$MARK_SH" 2099-01-01-00-00
  [ "$status" -ne 0 ]
}

@test "mark: nombre '..' se rechaza (invalid) y no toca el meta.json del directorio padre" {
  printf '{"digested": false, "transcribed": true}\n' > "$SAVIA_TRANSCRIPTOR_DIR/meta.json"
  run bash "$MARK_SH" ..
  [ "$status" -ne 0 ]
  grep -q '"digested": false' "$SAVIA_TRANSCRIPTOR_DIR/meta.json"
}

@test "mark: ya digerida es idempotente (exit 0) y conserva digested_at original" {
  meeting a '{"digested": true, "transcribed": true, "digested_at": "2026-01-01T00:00:00+00:00"}'
  run bash "$MARK_SH" a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya estaba digerida"* ]]
  [ "$(field a digested_at)" = "2026-01-01T00:00:00+00:00" ]
}

@test "mark: conserva los permisos del meta.json" {
  meeting a '{"digested": false, "transcribed": true}'
  chmod 0644 "$M/a/meta.json"
  bash "$MARK_SH" a
  [ "$(stat -c %a "$M/a/meta.json")" = "644" ]
}

@test "mark: escritura atomica, un lector concurrente nunca ve un meta.json invalido" {
  big="$(python3 -c 'print("x"*200000)')"
  for i in $(seq -w 1 30); do
    meeting "m$i" "{\"digested\": false, \"transcribed\": true, \"notes\": \"$big\"}"
  done
  ( for i in $(seq -w 1 30); do bash "$MARK_SH" "m$i" >/dev/null; done ) &
  pid=$!
  run python3 - "$M" "$pid" <<'EOF'
import json, os, sys, glob
root, pid = sys.argv[1], int(sys.argv[2])
files = sorted(glob.glob(os.path.join(root, "m*", "meta.json")))
reads = bad = 0
alive = True
while alive:
    try:
        os.kill(pid, 0)
    except OSError:
        alive = False
    for f in files:
        reads += 1
        try:
            json.load(open(f))
        except Exception:
            bad += 1
print(f"reads={reads} invalid={bad}")
EOF
  wait "$pid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid=0"* ]]
  for i in $(seq -w 1 30); do [ "$(field "m$i" digested)" = "True" ]; done
}

@test "mark: no deja ficheros temporales en la carpeta de la reunion" {
  meeting a '{"digested": false, "transcribed": true}'
  bash "$MARK_SH" a
  [ "$(ls -A "$M/a")" = "meta.json" ]
}

@test "mark: reunion legada sin meta.json pero transcrita crea meta.json digerido (scan y mark coherentes)" {
  mkdir -p "$M/legado"
  echo "texto" > "$M/legado/transcript.vtt"
  run bash "$MARK_SH" legado
  [ "$status" -eq 0 ]
  [ "$(field legado digested)" = "True" ]
  run bash -c "bash '$SCAN_SH' 2>/dev/null"
  [ -z "$output" ]
}

@test "mark: carpeta sin meta.json ni transcripcion se rechaza con exit 3 y no crea nada" {
  mkdir -p "$M/vacia"
  run bash "$MARK_SH" vacia
  [ "$status" -eq 3 ]
  [ ! -e "$M/vacia/meta.json" ]
}
