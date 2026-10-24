#!/usr/bin/env bats
# BATS tests for scripts/judge-calibration.sh (SE-269 S4)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/judge-calibration.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S4: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S4: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Dispose operation (AC-4.1) ────────────────────────────────────────────

@test "SE269-S4 AC-4.1: --dispose with valid params succeeds" {
  local cal_file; cal_file="$(mktemp)"
  run env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose H001 aceptado
  [ "$status" -eq 0 ]
  rm -f "$cal_file"
}

@test "SE269-S4 AC-4.1: --dispose rejects invalid disposition" {
  run bash "$SCRIPT" --dispose H001 inventado
  [ "$status" -eq 1 ]
}

@test "SE269-S4 AC-4.1: --dispose records entry in calibration file" {
  local cal_file; cal_file="$(mktemp)"
  run env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose H001 aceptado
  [ "$status" -eq 0 ]
  [[ -f "$cal_file" ]]
  run wc -l < "$cal_file"
  [[ "$output" -ge 1 ]]
  rm -f "$cal_file"
}

@test "SE269-S4 AC-4.1: all 4 dispositions are valid" {
  for d in aceptado descartado-nimiedad descartado-malentendido descartado-inexistente; do
    local cal_file; cal_file="$(mktemp)"
    run env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "T-$d" "$d"
    [ "$status" -eq 0 ]
    rm -f "$cal_file"
  done
}

# ── Report operation (AC-4.2) ─────────────────────────────────────────────

@test "SE269-S4 AC-4.2: --report with no data returns sin_datos" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --report test-judge
  [ "$status" -eq 0 ]
  [[ "$output" == *'"N": 0'* ]]
  rm -f "$cal_file" "$fn_file"
}

@test "SE269-S4 AC-4.2: --report with <25 entries returns sin_datos" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  # Insert 10 dispositions
  for i in $(seq 1 10); do
    env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "H$i" aceptado 2>/dev/null
  done
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --report test-judge
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "sin_datos"'* ]]
  rm -f "$cal_file" "$fn_file"
}

@test "SE269-S4: FP counted as descartado-*" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  for i in $(seq 1 20); do
    env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "H$i" aceptado 2>/dev/null
  done
  for i in $(seq 21 25); do
    env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "H$i" descartado-nimiedad 2>/dev/null
  done
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --report test-judge2
  [ "$status" -eq 0 ]
  rm -f "$cal_file" "$fn_file"
}

# ── FN recording (AC-4.4) ─────────────────────────────────────────────────

@test "SE269-S4 AC-4.4: --fn-record writes to FN file" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --fn-record FN001 security-judge "bug en produccion"
  [ "$status" -eq 0 ]
  [[ -f "$fn_file" ]]
  run wc -l < "$fn_file"
  [[ "$output" -ge 1 ]]
  rm -f "$cal_file" "$fn_file"
}

@test "SE269-S4 AC-4.4: FN record links to specific judge" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --fn-record FN002 correctness-judge "fallo de logica"
  [ "$status" -eq 0 ]
  run grep -q "correctness-judge" "$fn_file"
  [[ "$status" -eq 0 ]]
  rm -f "$cal_file" "$fn_file"
}

# ── Publish operation (AC-4.5: anti-Goodhart) ─────────────────────────────

@test "SE269-S4 AC-4.5: --publish includes both FP and FN data" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  for i in $(seq 1 25); do
    env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "P$i" aceptado 2>/dev/null
  done
  env FN_FILE="$fn_file" bash "$SCRIPT" --fn-record FN001 pub-judge "escapo a prod" 2>/dev/null
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --publish pub-judge
  [ "$status" -eq 0 ]
  [[ "$output" == *'"fp_N"'* ]]
  rm -f "$cal_file" "$fn_file"
}

# ── Degrade / Restore (AC-4.3) ────────────────────────────────────────────

@test "SE269-S4 AC-4.3: --degrade records degradation" {
  local deg_file; deg_file="$(mktemp)"
  run env DEGRADATION_FILE="$deg_file" bash "$SCRIPT" --degrade test-judge "FP rate > 50%"
  [ "$status" -eq 0 ]
  [[ -f "$deg_file" ]]
  run grep -q '"accion": "degrade"' "$deg_file"
  [[ "$status" -eq 0 ]]
  rm -f "$deg_file"
}

@test "SE269-S4 AC-4.3: --restore records restoration" {
  local deg_file; deg_file="$(mktemp)"
  run env DEGRADATION_FILE="$deg_file" bash "$SCRIPT" --restore test-judge
  [ "$status" -eq 0 ]
  run grep -q '"accion": "restore"' "$deg_file"
  [[ "$status" -eq 0 ]]
  rm -f "$deg_file"
}

@test "SE269-S4 AC-4.3: degrade then restore is traceable" {
  local deg_file; deg_file="$(mktemp)"
  run env DEGRADATION_FILE="$deg_file" bash "$SCRIPT" --degrade cycle-judge "FP alta"
  [ "$status" -eq 0 ]
  run env DEGRADATION_FILE="$deg_file" bash "$SCRIPT" --restore cycle-judge
  [ "$status" -eq 0 ]
  run wc -l < "$deg_file"
  [[ "$output" -ge 2 ]]
  rm -f "$deg_file"
}

# ── Output JSON validity ──────────────────────────────────────────────────

@test "SE269-S4: --report output is valid JSON" {
  local cal_file; cal_file="$(mktemp)"
  local fn_file; fn_file="$(mktemp)"
  for i in $(seq 1 26); do
    env CALIBRATION_FILE="$cal_file" bash "$SCRIPT" --dispose "RJ$i" aceptado 2>/dev/null
  done
  run env CALIBRATION_FILE="$cal_file" FN_FILE="$fn_file" bash "$SCRIPT" --report json-judge
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool >/dev/null 2>&1
  [ "$?" -eq 0 ]
  rm -f "$cal_file" "$fn_file"
}

# ── Comportamiento: contenido de los registros, filtros por juez, umbrales ──

jc() { env CALIBRATION_FILE="$CAL" FN_FILE="$FN" DEGRADATION_FILE="$DEG" bash "$SCRIPT" "$@"; }

setup_files() {
  CAL="$BATS_TEST_TMPDIR/cal.jsonl"; FN="$BATS_TEST_TMPDIR/fn.jsonl"; DEG="$BATS_TEST_TMPDIR/deg.jsonl"
}

disponer() { # n disposicion juez
  local i
  for i in $(seq 1 "$1"); do jc --dispose "H-$3-$2-$i" "$2" "$3" > /dev/null; done
}

@test "dispose: la entrada guarda id, disposición, usuario, sello UTC y juez; y se imprime el JSON de estado" {
  setup_files
  run env USER=alguien CALIBRATION_FILE="$CAL" bash "$SCRIPT" --dispose H-9 descartado-nimiedad security-judge
  [ "$status" -eq 0 ]
  [ "$output" = '{"status": "disposed", "id": "H-9", "value": "descartado-nimiedad"}' ]
  [ "$(jq -r .hallazgo_id "$CAL")" = "H-9" ]
  [ "$(jq -r .disposicion "$CAL")" = "descartado-nimiedad" ]
  [ "$(jq -r .disposed_by "$CAL")" = "alguien" ]
  [ "$(jq -r .juez "$CAL")" = "security-judge" ]
  [[ "$(jq -r .timestamp "$CAL")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "dispose sin juez no escribe la clave juez" {
  setup_files
  jc --dispose H-1 aceptado > /dev/null
  [ "$(jq 'has("juez")' "$CAL")" = "false" ]
}

@test "dispose: una disposición que solo es prefijo válido ('descartado') se rechaza y no escribe" {
  setup_files
  run jc --dispose H-1 descartado
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposicion invalida: descartado"* ]]
  [ ! -s "$CAL" ] || [ ! -e "$CAL" ]
  run jc --dispose H-1 "aceptado descartado-nimiedad"
  [ "$status" -eq 1 ]
}

@test "dispose: id vacío o disposición vacía salen con 1 y mensaje de requisito" {
  setup_files
  run jc --dispose "" aceptado
  [ "$status" -eq 1 ]
  [[ "$output" == *"--dispose requiere id y disposicion"* ]]
}

@test "dispose acumula: cada llamada añade una línea JSON válida" {
  setup_files
  jc --dispose A aceptado > /dev/null
  jc --dispose B descartado-malentendido > /dev/null
  [ "$(wc -l < "$CAL")" -eq 2 ]
  [ "$(jq -s 'map(.hallazgo_id) | join(",")' "$CAL" | tr -d '"')" = "A,B" ]
}

@test "dispose con comillas y caracteres de shell en el id no inyecta código" {
  setup_files
  run jc --dispose "x'; import os; os.system('touch $BATS_TEST_TMPDIR/pwned') #" aceptado
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  [[ "$(jq -r .hallazgo_id "$CAL")" == "x'; import os;"* ]]
}

@test "fn-record: guarda id, juez, descripción (con comillas y ñ) y quién; imprime el estado" {
  setup_files
  run env USER=otra FN_FILE="$FN" bash "$SCRIPT" --fn-record FN-7 correctness-judge "no vió el 'null' en ñandú"
  [ "$status" -eq 0 ]
  [ "$output" = '{"status": "fn_recorded", "id": "FN-7", "juez": "correctness-judge"}' ]
  [ "$(jq -r .fn_id "$FN")" = "FN-7" ]
  [ "$(jq -r .descripcion "$FN")" = "no vió el 'null' en ñandú" ]
  [ "$(jq -r .recorded_by "$FN")" = "otra" ]
}

@test "fn-record: descripción opcional queda vacía; sin juez falla con 1" {
  setup_files
  run jc --fn-record FN-1 j
  [ "$status" -eq 0 ]
  [ "$(jq -r .descripcion "$FN")" = "" ]
  run jc --fn-record FN-2 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"requiere id, juez, y descripcion"* ]]
}

@test "degrade: pasa a modo asesor con el motivo dado; sin motivo usa 'FP elevado'" {
  setup_files
  run jc --degrade j1 "demasiados FP"
  [ "$status" -eq 0 ]
  [ "$output" = '{"status": "degraded", "juez": "j1", "modo": "asesor"}' ]
  jc --degrade j2 > /dev/null
  [ "$(jq -r 'select(.juez=="j1") | .motivo' "$DEG")" = "demasiados FP" ]
  [ "$(jq -r 'select(.juez=="j2") | .motivo' "$DEG")" = "FP elevado" ]
  [ "$(jq -r 'select(.juez=="j1") | .modo_destino' "$DEG")" = "asesor" ]
}

@test "degrade con motivo con comillas se guarda íntegro" {
  setup_files
  jc --degrade j "FP > 50% y 'ruido' \"alto\"" > /dev/null
  [ "$(jq -r .motivo "$DEG")" = "FP > 50% y 'ruido' \"alto\"" ]
}

@test "restore: modo activo, motivo recalibrado; sin juez falla con 1" {
  setup_files
  run jc --restore j1
  [ "$output" = '{"status": "restored", "juez": "j1", "modo": "activo"}' ]
  [ "$(jq -r .modo_destino "$DEG")" = "activo" ]
  [ "$(jq -r .motivo "$DEG")" = "recalibrado" ]
  run jc --restore ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--restore requiere juez"* ]]
}

@test "report sin datos: sin_datos con N 0 y nº de FN del juez" {
  setup_files
  jc --fn-record F1 j1 d > /dev/null
  jc --fn-record F2 otro d > /dev/null
  run jc --report j1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .status)" = "sin_datos" ]
  [ "$(echo "$output" | jq -r .N)" = "0" ]
  [ "$(echo "$output" | jq -r .fn_N)" = "1" ]
}

@test "report con 24 disposiciones: sin_datos y mensaje con el N actual; con 25 ya hay tasa" {
  setup_files
  disponer 24 aceptado j1
  run jc --report j1
  [ "$(echo "$output" | jq -r .status)" = "sin_datos" ]
  [ "$(echo "$output" | jq -r .N)" = "24" ]
  [[ "$(echo "$output" | jq -r .message)" == "N<25 (actual=24)"* ]]
  disponer 1 descartado-nimiedad j1
  run jc --report j1
  [ "$(echo "$output" | jq -r .status)" = "datos_suficientes" ]
  [ "$(echo "$output" | jq -r .N)" = "25" ]
}

@test "report: tasa de FP = descartados/total con un decimal; cuenta aceptados y FN" {
  setup_files
  disponer 17 aceptado j1
  disponer 4 descartado-nimiedad j1
  disponer 3 descartado-malentendido j1
  disponer 2 descartado-inexistente j1
  jc --fn-record F1 j1 d > /dev/null
  jc --fn-record F2 j1 d > /dev/null
  run jc --report j1
  [ "$(echo "$output" | jq -r .N)" = "26" ]
  [ "$(echo "$output" | jq -r .aceptados)" = "17" ]
  [ "$(echo "$output" | jq -r .falsos_positivos)" = "9" ]
  [ "$(echo "$output" | jq -r .fp_rate_pct)" = "34.6" ]
  [ "$(echo "$output" | jq -r .falsos_negativos)" = "2" ]
  [ "$(echo "$output" | jq -r .fn_status)" = "registrados" ]
}

@test "report sin FN registrados: fn_status sin_datos_fn" {
  setup_files
  disponer 25 aceptado j1
  run jc --report j1
  [ "$(echo "$output" | jq -r .fn_status)" = "sin_datos_fn" ]
  [ "$(echo "$output" | jq -r .fp_rate_pct)" = "0.0" ]
}

@test "report filtra por juez: las disposiciones de otro juez no cuentan; 'all' las suma" {
  setup_files
  disponer 25 aceptado j1
  disponer 10 descartado-nimiedad j2
  run jc --report j2
  [ "$(echo "$output" | jq -r .status)" = "sin_datos" ]
  [ "$(echo "$output" | jq -r .N)" = "10" ]
  run jc --report all
  [ "$(echo "$output" | jq -r .N)" = "35" ]
  run jc
  [ "$(echo "$output" | jq -r .juez)" = "all" ]
}

@test "report ignora líneas corruptas y vacías del fichero de calibración" {
  setup_files
  disponer 25 aceptado j1
  printf 'no es json\n\n' >> "$CAL"
  run jc --report j1
  [ "$(echo "$output" | jq -r .N)" = "25" ]
}

@test "publish con menos de 25: sin_datos_suficientes con fp_N, fn_N y mensaje" {
  setup_files
  disponer 3 aceptado j1
  jc --fn-record F1 j1 d > /dev/null
  run jc --publish j1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .status)" = "sin_datos_suficientes" ]
  [ "$(echo "$output" | jq -r .fp_N)" = "3" ]
  [ "$(echo "$output" | jq -r .fn_N)" = "1" ]
  [[ "$(echo "$output" | jq -r .message)" == *">=25"* ]]
}

@test "publish con 25 o más: tasas FP y FN juntas con nota anti-Goodhart" {
  setup_files
  disponer 20 aceptado j1
  disponer 5 descartado-inexistente j1
  run jc --publish j1
  [ "$(echo "$output" | jq -r .status)" = "datos_publicados" ]
  [ "$(echo "$output" | jq -r .fp_count)" = "5" ]
  [ "$(echo "$output" | jq -r .fp_rate_pct)" = "20.0" ]
  [ "$(echo "$output" | jq -r .aceptados)" = "20" ]
  [ "$(echo "$output" | jq -r .fn_status)" = "sin_datos_fn" ]
  [ "$(echo "$output" | jq -r .modo_actual)" = "activo" ]
  [[ "$(echo "$output" | jq -r .nota_anti_goodhart)" == *"cold-start"* ]]
  jc --fn-record F1 j1 d > /dev/null
  run jc --publish j1
  [ "$(echo "$output" | jq -r .fn_status)" = "fn_registrados" ]
  [ "$(echo "$output" | jq -r .fn_N)" = "1" ]
}

@test "publish: el filtro por juez aísla los datos de cada juez" {
  setup_files
  disponer 25 aceptado j1
  disponer 25 descartado-nimiedad j2
  run jc --publish j2
  [ "$(echo "$output" | jq -r .fp_rate_pct)" = "100.0" ]
  run jc --publish j1
  [ "$(echo "$output" | jq -r .fp_rate_pct)" = "0.0" ]
}

@test "publish sin juez falla con 1" {
  setup_files
  run jc --publish ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--publish requiere juez"* ]]
}

@test "--help imprime el uso y sale 0; sin operación equivale a report de todos" {
  setup_files
  run jc --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Uso: judge-calibration.sh --report"* ]]
  run jc
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .status)" = "sin_datos" ]
}

@test "los ficheros de salida se crean con sus directorios" {
  local d="$BATS_TEST_TMPDIR/a/b"
  run env CALIBRATION_FILE="$d/cal.jsonl" bash "$SCRIPT" --dispose H aceptado j
  [ "$status" -eq 0 ]
  [ -f "$d/cal.jsonl" ]
}

@test "registros con acentos y eñes se guardan literales (no escapados)" {
  setup_files
  jc --dispose H-1 aceptado "juéz-ñ" > /dev/null
  jc --fn-record FN-1 "juéz-ñ" "descripción ñandú" > /dev/null
  jc --degrade "juéz-ñ" "motivo: señal" > /dev/null
  jc --restore "juéz-ñ" > /dev/null
  grep -q 'juéz-ñ' "$CAL"
  grep -q 'descripción ñandú' "$FN"
  grep -q 'motivo: señal' "$DEG"
  [ "$(grep -c 'juéz-ñ' "$DEG")" -eq 2 ]
}

@test "ficheros de salida con nombre sin directorio (en el cwd) funcionan" {
  cd "$BATS_TEST_TMPDIR"
  run env CALIBRATION_FILE=cal.jsonl FN_FILE=fn.jsonl DEGRADATION_FILE=deg.jsonl bash "$BATS_TEST_DIRNAME/../$SCRIPT" --dispose H aceptado j
  [ "$status" -eq 0 ]
  run env CALIBRATION_FILE=cal.jsonl FN_FILE=fn.jsonl DEGRADATION_FILE=deg.jsonl bash "$BATS_TEST_DIRNAME/../$SCRIPT" --fn-record F j d
  [ "$status" -eq 0 ]
  run env CALIBRATION_FILE=cal.jsonl FN_FILE=fn.jsonl DEGRADATION_FILE=deg.jsonl bash "$BATS_TEST_DIRNAME/../$SCRIPT" --degrade j m
  [ "$status" -eq 0 ]
  run env CALIBRATION_FILE=cal.jsonl FN_FILE=fn.jsonl DEGRADATION_FILE=deg.jsonl bash "$BATS_TEST_DIRNAME/../$SCRIPT" --restore j
  [ "$status" -eq 0 ]
  [ -s cal.jsonl ] && [ -s fn.jsonl ] && [ "$(wc -l < deg.jsonl)" -eq 2 ]
}

@test "degrade sin juez falla con 1 y mensaje, sin escribir" {
  setup_files
  run jc --degrade ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"--degrade requiere juez y motivo"* ]]
  [ ! -e "$DEG" ]
}
