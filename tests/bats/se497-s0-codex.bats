#!/usr/bin/env bats
# Ref: docs/specs/SE-497-code-linked-knowledge-drift-and-learning-without-self-authority.spec.md (S0)
# Estrategia: contrato de CLI, integridad por SHA-256, JSON round-trip y centinela sed.
# Solo fixtures sintéticos en mktemp; no usa propuestas ni registros del repositorio.

set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LC="$REPO_ROOT/scripts/learning-lifecycle.sh"
  TMPD="$(mktemp -d -t se497-s0-codex-XXXXXX)"
  mkdir -p "$TMPD/propuestas con espacios" "$TMPD/registro con espacios"
  F="$TMPD/propuestas con espacios/LP-TEST.md"
  LED="$TMPD/registro con espacios/lifecycle.jsonl"
  export SCL_LEDGER="$LED"
  SHA="sha:0123456789abcdef0123456789abcdef01234567"
  fixture canary
}

teardown() {
  if [[ -n "${TMPD:-}" && -d "$TMPD" ]]; then
    rm -rf -- "$TMPD"
  fi
}

fixture() {
  local state="${1:-canary}" id="${2:-LP-TEST}" trailer="${3:-}"
  {
    printf '%s\n' '---' "id: $id" 'type: learning_proposal' \
      'provenance: INFERRED' "lifecycle: $state" 'origin: test' \
      'created_utc: 2026-01-01T00:00:00Z' "human_trailer: $trailer" '---'
    printf '\n# Lección sintética\n\nCuerpo con / & ; " y UTF-8: á Ω.\n'
  } > "$F"
}

file_hash() {
  python3 - "$F" <<'PY'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

invoke() {
  run bash "$LC" --file "$F" --ledger "$LED" "$@"
}

assert_state() {
  python3 - "$F" "$1" <<'PY'
import pathlib, sys
header = pathlib.Path(sys.argv[1]).read_text().split('---', 2)[1].splitlines()
assert [l for l in header if l.startswith('lifecycle: ')] == ['lifecycle: ' + sys.argv[2]]
PY
}

assert_jsonl() {
  python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1])]' "$LED"
}

assert_row() {
  # Comprueba TODAS las filas, incluso en los rechazos: ninguna línea vacía se omite.
  assert_jsonl
  python3 - "$LED" "$@" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
assert len(rows) == 1, rows
for key, expected in zip(sys.argv[2::2], sys.argv[3::2]):
    assert rows[0][key] == expected, (key, rows[0][key], expected)
PY
}

assert_active() {
  assert_state active
  python3 - "$F" "$1" <<'PY'
import pathlib, sys
header = pathlib.Path(sys.argv[1]).read_text().split('---', 2)[1].splitlines()
assert [l for l in header if l.startswith('provenance: ')] == ['provenance: human_authored']
assert [l for l in header if l.startswith('human_trailer: ')] == ['human_trailer: ' + sys.argv[2]]
PY
}

reject_trailer() {
  local before
  before="$(file_hash)"
  invoke --to active --human-trailer "$1" --metric-before 0.5 --metric-after 0.6
  # Integridad antes del código: detecta también corrupción aunque el rechazo devuelva 4.
  [ "$(file_hash)" = "$before" ]
  [ "$status" -eq 4 ]
}

accept_trailer() {
  invoke --to active --human-trailer "$1" --metric-before 0.5 --metric-after 0.6
  [ "$status" -eq 0 ]
  assert_active "$1"
  assert_row id LP-TEST from canary to active
}

round_trip() {
  local field="$1" value="$2"
  fixture proposed
  case "$field" in
    id)
      # El fallback público a basename permite un id con LF sin inventar YAML multilínea.
      F="$TMPD/propuestas con espacios/$value.md"
      printf '%s\n' '---' 'lifecycle: proposed' 'provenance: INFERRED' \
        'created_utc: 2026-01-01T00:00:00Z' '---' 'Cuerpo sintético' > "$F"
      invoke --to canary
      ;;
    actor|reason) invoke --to canary "--$field" "$value" ;;
    *) return 1 ;;
  esac
  [ "$status" -eq 0 ]
  assert_state canary
  assert_row "$field" "$value" from proposed to canary
}

@test "S0-6: sha de 40 hex minúsculos activa con mejora" {
  accept_trailer "$SHA"
}

@test "S0-6: se488 de un carácter activa (boundary mínimo)" {
  accept_trailer 'se488:a'
}

@test "S0-6: se488 de 64 caracteres activa (boundary máximo)" {
  local token
  printf -v token '%064d' 0
  accept_trailer "se488:$token"
}

@test "S0-6: se488 permite mayúsculas números punto guion y subrayado" {
  accept_trailer 'se488:Az09._-'
}

@test "S0-6: se488 permite identificador que empieza por guion" {
  accept_trailer 'se488:-recibo'
}

@test "S0-6: igualdad de métricas permite activar (boundary sin regresión)" {
  invoke --to active --human-trailer "$SHA" --metric-before 0.5 --metric-after 0.5
  [ "$status" -eq 0 ]
  assert_active "$SHA"
  assert_row metric_before 0.5 metric_after 0.5
}

@test "S0-6: dos métricas zero son presentes y permiten activar" {
  invoke --to active --human-trailer "$SHA" --metric-before 0 --metric-after 0
  [ "$status" -eq 0 ]
  assert_active "$SHA"
  assert_row metric_before 0 metric_after 0
}

@test "S0-1: rechaza trailer ausente y conserva hash de la lección" {
  local before
  before="$(file_hash)"
  invoke --to active --metric-before 0.5 --metric-after 0.6
  [ "$status" -eq 4 ]
  [ "$(file_hash)" = "$before" ]
}

@test "S0-1: rechaza trailer empty y conserva hash de la lección" {
  reject_trailer ''
}

@test "S0-1: rechaza texto libre aunque no tenga metacaracteres" {
  reject_trailer 'firma-humana'
}

@test "S0-1: rechaza sha de 39 hex (boundary inferior)" {
  reject_trailer "${SHA%?}"
}

@test "S0-1: rechaza sha de 41 hex (boundary superior)" {
  reject_trailer "${SHA}0"
}

@test "S0-1: rechaza sha con hex mayúsculo" {
  reject_trailer 'sha:A123456789abcdef0123456789abcdef01234567'
}

@test "S0-1: rechaza sha con carácter que no es hexadecimal" {
  reject_trailer 'sha:g123456789abcdef0123456789abcdef01234567'
}

@test "S0-1: rechaza prefijo SHA en mayúsculas" {
  reject_trailer "SHA:${SHA#sha:}"
}

@test "S0-1: rechaza se488 empty sin identificador" {
  reject_trailer 'se488:'
}

@test "S0-1: rechaza se488 de 65 caracteres (boundary superior)" {
  local token
  printf -v token '%065d' 0
  reject_trailer "se488:$token"
}

@test "S0-1: rechaza espacio antes de un trailer válido" {
  reject_trailer " $SHA"
}

@test "S0-1: rechaza espacio después de un trailer válido" {
  reject_trailer "$SHA "
}

@test "S0-1: rechaza prefijo ajeno antes de un trailer válido" {
  reject_trailer "x$SHA"
}

@test "S0-1: rechaza sufijo ajeno después de un trailer válido" {
  reject_trailer "${SHA}x"
}

@test "S0-1: rechaza trailer que empieza por guion de opción" {
  reject_trailer '--help'
}

@test "S0-2: rechaza barra / sin tocar cabecera ni cuerpo" {
  reject_trailer 'se488:recibo/extra'
}

@test "S0-2: rechaza ampersand & sin tocar cabecera ni cuerpo" {
  reject_trailer 'se488:recibo&extra'
}

@test "S0-2: rechaza punto y coma ; sin tocar cabecera ni cuerpo" {
  reject_trailer 'se488:recibo;extra'
}

@test "S0-2: rechaza comilla simple sin tocar cabecera ni cuerpo" {
  reject_trailer "se488:recibo'extra"
}

@test "S0-2: rechaza comilla doble sin tocar cabecera ni cuerpo" {
  reject_trailer 'se488:recibo"extra'
}

@test "S0-2: rechaza barra invertida sin tocar cabecera ni cuerpo" {
  reject_trailer 'se488:recibo\extra'
}

@test "S0-2: rechaza tabulador sin tocar cabecera ni cuerpo" {
  reject_trailer $'se488:recibo\textra'
}

@test "S0-2: rechaza LF interior sin tocar cabecera ni cuerpo" {
  reject_trailer $'se488:recibo\nextra'
}

@test "S0-2: rechaza CR interior sin tocar cabecera ni cuerpo" {
  reject_trailer $'se488:recibo\rextra'
}

@test "S0-2: rechaza control ASCII U+0001" {
  reject_trailer $'se488:recibo\001extra'
}

@test "S0-2: rechaza control DEL U+007F" {
  reject_trailer $'se488:recibo\177extra'
}

@test "S0-2: rechaza control Unicode U+0085" {
  reject_trailer $'se488:recibo\u0085extra'
}

@test "S0-2: rechaza control Unicode bidi U+202E" {
  reject_trailer $'se488:recibo\u202eextra'
}

@test "S0-2: rechaza Unicode de ancho cero U+200B" {
  reject_trailer $'se488:recibo\u200bextra'
}

@test "S0-2: rechaza letra Unicode visualmente similar a ASCII" {
  reject_trailer $'se488:r\u0435cibo'
}

@test "S0-2: rechaza trailer válido seguido de LF y más texto" {
  reject_trailer "$SHA"$'\ncabecera: inyectada'
}

@test "S0-2: rechaza trailer válido seguido solamente de LF final" {
  reject_trailer "$SHA"$'\n'
}

@test "S0-2: rechaza trailer válido seguido de CRLF" {
  reject_trailer "$SHA"$'\r\n'
}

@test "S0-2: rechaza inyección GNU sed e touch y no crea centinela" {
  local sentinel="$TMPD/centinela-sed" payload before
  payload=$'x/\ne touch '"$sentinel"$'\n#'
  before="$(file_hash)"
  [ ! -e "$sentinel" ]
  invoke --to active --human-trailer "$payload" --metric-before 0.5 --metric-after 0.6
  [ ! -e "$sentinel" ]
  [ "$(file_hash)" = "$before" ]
  [ "$status" -eq 4 ]
}

@test "S0-3: reason con comillas simples y dobles conserva JSON y valor" {
  round_trip reason $'razón "doble" y \'simple\''
}

@test "S0-3: reason con barra invertida conserva JSON y valor" {
  round_trip reason 'razón\literal'
}

@test "S0-3: reason con salto de línea conserva una única fila JSON" {
  round_trip reason $'primera línea\nsegunda línea'
}

@test "S0-3: actor con comillas simples y dobles conserva JSON y valor" {
  round_trip actor $'actor "doble" y \'simple\''
}

@test "S0-3: actor con barra invertida conserva JSON y valor" {
  round_trip actor 'actor\literal'
}

@test "S0-3: actor con salto de línea conserva una única fila JSON" {
  round_trip actor $'actor\nsegunda línea'
}

@test "S0-3: id con comillas simples y dobles conserva JSON y valor" {
  round_trip id $'LP-"doble"-\'simple\''
}

@test "S0-3: id con barra invertida conserva JSON y valor" {
  round_trip id 'LP-\literal'
}

@test "S0-3: id con LF interior en basename conserva una única fila JSON" {
  round_trip id $'LP-primera\nsegunda'
}

@test "S0-3: id explícito en cabecera con comillas y barra conserva valor" {
  local id='LP-"cita"-\literal'
  fixture proposed "$id"
  invoke --to canary
  [ "$status" -eq 0 ]
  assert_row id "$id"
}

@test "S0-3: reason con escape JSON literal no se decodifica dos veces" {
  round_trip reason 'línea\ntexto'
}

@test "S0-3: actor con escape JSON literal no se decodifica dos veces" {
  round_trip actor 'actor\ntexto'
}

@test "S0-3: id con escape JSON literal no se decodifica dos veces" {
  round_trip id 'LP-\ntexto'
}

@test "S0-3: id con LF final en basename conserva el salto al decodificar" {
  round_trip id $'LP-final\n'
}

@test "S0-3: actor que empieza por guion se conserva como dato" {
  round_trip actor '--actor-sintetico'
}

@test "S0-3: reason que empieza por guion se conserva como dato" {
  round_trip reason '--reason-sintetica'
}

@test "S0-3: id que empieza por guion se conserva como dato" {
  round_trip id '--id-sintetico'
}

@test "S0-3: reason con Unicode combinado tabulador y CR conserva valor" {
  round_trip reason $'cafe\u0301 Ω\tcolumna\rretorno'
}

@test "S0-3: rechazo por trailer ausente registra JSON con valores especiales" {
  local actor=$'actor "x"\\y\nz' reason=$'razón "x"\\y\nz'
  local id='LP-"x"-\y' before
  fixture canary "$id"
  before="$(file_hash)"
  invoke --to active --actor "$actor" --reason "$reason"
  [ "$status" -eq 4 ]
  [ "$(file_hash)" = "$before" ]
  assert_row id "$id" actor "$actor" reason "$reason" status refused-no-human
}

@test "S0-4: rechaza activación con cero métricas y conserva canary" {
  local before
  before="$(file_hash)"
  invoke --to active --human-trailer "$SHA"
  [ "$status" -eq 5 ]
  assert_state canary
  [ "$(file_hash)" = "$before" ]
}

@test "S0-4: rechaza activación con solo metric-before y conserva canary" {
  local before
  before="$(file_hash)"
  invoke --to active --human-trailer "$SHA" --metric-before 0.5
  [ "$status" -eq 5 ]
  assert_state canary
  [ "$(file_hash)" = "$before" ]
}

@test "S0-4: rechaza activación con solo metric-after y conserva canary" {
  local before
  before="$(file_hash)"
  invoke --to active --human-trailer "$SHA" --metric-after 0.6
  [ "$status" -eq 5 ]
  assert_state canary
  [ "$(file_hash)" = "$before" ]
}

@test "S0-4: rechaza métrica before empty aunque after esté presente" {
  invoke --to active --human-trailer "$SHA" --metric-before '' --metric-after 0.6
  [ "$status" -eq 5 ]
  assert_state canary
}

@test "S0-4: rechaza métrica after empty aunque before esté presente" {
  invoke --to active --human-trailer "$SHA" --metric-before 0.5 --metric-after ''
  [ "$status" -eq 5 ]
  assert_state canary
}

@test "S0-4: rechaza regresión con salida 5 y revierte a proposed" {
  invoke --to active --human-trailer "$SHA" --metric-before 0.8 --metric-after 0.6
  [ "$status" -eq 5 ]
  assert_state proposed
  assert_row from canary to proposed metric_before 0.8 metric_after 0.6
}

@test "S0-4: rechaza regresión pequeña de decimales sin redondearla a igualdad" {
  invoke --to active --human-trailer "$SHA" --metric-before 0.5001 --metric-after 0.5
  [ "$status" -eq 5 ]
  assert_state proposed
}

@test "S0-5: segunda activación idéntica no añade fila ni cambia el fichero" {
  local before
  invoke --to active --human-trailer "$SHA" --metric-before 0.5 --metric-after 0.6
  [ "$status" -eq 0 ]
  assert_active "$SHA"
  assert_row from canary to active
  before="$(file_hash)"
  cp "$LED" "$TMPD/ledger-antes"
  invoke --to active --human-trailer "$SHA" --metric-before 0.5 --metric-after 0.6
  [ "$status" -eq 0 ]
  assert_active "$SHA"
  [ "$(file_hash)" = "$before" ]
  cmp "$LED" "$TMPD/ledger-antes"
  assert_row from canary to active
}

@test "S0-5: superseded repetido no duplica tombstone ni fila" {
  local before
  invoke --to superseded --reason obsoleta
  [ "$status" -eq 0 ]
  assert_state superseded
  [ "$(grep -c '^tombstone:' "$F")" -eq 1 ]
  assert_row from canary to superseded
  before="$(file_hash)"
  cp "$LED" "$TMPD/ledger-antes"
  invoke --to superseded --reason obsoleta
  [ "$status" -eq 0 ]
  [ "$(grep -c '^tombstone:' "$F")" -eq 1 ]
  [ "$(file_hash)" = "$before" ]
  cmp "$LED" "$TMPD/ledger-antes"
}

@test "S0-5: proposed repetido no crea registro de una transición inexistente" {
  fixture proposed
  # Ledger preexistente vacío: permite comprobar el NOOP sin fijar si se crea archivo.
  : > "$LED"
  local before
  before="$(file_hash)"
  invoke --to proposed
  [ "$status" -eq 0 ]
  [ "$(file_hash)" = "$before" ]
  [ ! -s "$LED" ]
}

@test "S0-1: rechazos repetidos por trailer ausente sí añaden evidencia" {
  local before
  before="$(file_hash)"
  invoke --to active --reason intento-sin-firma
  [ "$status" -eq 4 ]
  invoke --to active --reason intento-sin-firma
  [ "$status" -eq 4 ]
  [ "$(file_hash)" = "$before" ]
  assert_jsonl
  python3 - "$LED" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
assert len(rows) == 2, rows
for row in rows:
    assert row['from'] == 'canary' and row['to'] == 'active', row
    assert row['status'] == 'refused-no-human', row
    assert row['reason'] == 'intento-sin-firma', row
PY
}

@test "S0-6: active con trailer heredado de texto libre admite superseded" {
  local legacy='operadora/perfil-sintetico/2026-01-01T00:00:00Z'
  fixture active LP-LEGACY "$legacy"
  # Una entrada activa real ya tiene esta procedencia.
  python3 - "$F" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace('provenance: INFERRED', 'provenance: human_authored'))
PY
  assert_state active
  invoke --to superseded --reason obsoleta
  [ "$status" -eq 0 ]
  assert_state superseded
  grep -Fx "human_trailer: $legacy" "$F"
  grep -Fx 'provenance: human_authored' "$F"
  [ "$(grep -c '^tombstone:' "$F")" -eq 1 ]
  assert_row id LP-LEGACY from active to superseded
}

@test "S0-6: rutas con espacios y ledger en directorio nonexistent se crean" {
  LED="$TMPD/directorio nuevo con espacios/subdirectorio/lifecycle.jsonl"
  accept_trailer 'se488:recibo-rutas'
  [ -f "$LED" ]
}

@test "S0-1: strict rechaza trailer ausente sin alterar la lección y registra evidencia" {
  local before
  before="$(file_hash)"
  invoke --to active --strict --metric-before 0.5 --metric-after 0.6
  [ "$status" -eq 4 ]
  [ "$(file_hash)" = "$before" ]
  assert_row id LP-TEST from canary to active status refused-no-human
}

@test "S0-1: rechaza trailer inválido incluso si la lección ya está active" {
  fixture active LP-TEST "$SHA"
  reject_trailer 'firma-no-valida'
}

@test "S0-7: ningún sed interpola argumentos recibidos por CLI" {
  python3 - "$LC" <<'PY'
import pathlib, re, shlex, sys
source = pathlib.Path(sys.argv[1]).read_text()
# Solo analiza líneas que invocan sed: un heredoc Python ajeno no es sintaxis shell.
source = source.replace('\\\n', '')
sed_call = re.compile(r'(?<![\w-])(?:[\w./-]+/)?sed(?:[ \t]|$)')
forbidden = re.compile(r'\$(?:\{)?(?:HUMAN_TRAILER|REASON|ACTOR|ID|SUBSET|METRIC_BEFORE|METRIC_AFTER)(?:\}|\b)')
commands = []
for line in source.splitlines():
    if line.lstrip().startswith('#') or not sed_call.search(line):
        continue
    lexer = shlex.shlex(line, posix=True, punctuation_chars=';&|()')
    command = []
    for token in lexer:
        if token and all(c in ';&|()' for c in token):
            commands.append(command)
            command = []
        else:
            command.append(token)
    commands.append(command)
violations = [c for c in commands if any(t.rsplit('/', 1)[-1] == 'sed' for t in c)
              and any(forbidden.search(t) for t in c)]
assert not violations, 'sed interpola argumentos: ' + repr(violations)
PY
}
