#!/usr/bin/env bats
# Ref: docs/rules/domain/code-review-court.md; docs/specs/SE-350-coherence-court.spec.md
# Estrategia: CLI real; controles positivos y límites; entradas numéricas inválidas
# y sustituciones aritméticas con efecto observable SOLO en BATS_TEST_TMPDIR.
# Los errores de bash no bastan: una entrada inválida debe rechazarse explícitamente.

setup() {
  set -o pipefail
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  COURT="$ROOT/scripts/court-review.sh"
  COHERENCE="$ROOT/scripts/coherence-court.sh"
  ROUTER="$ROOT/scripts/court-turn-router.sh"
  AGGREGATOR="$ROOT/scripts/court-score-aggregator.sh"
  TMPDIR_TEST="$BATS_TEST_TMPDIR/court con espacios"
  mkdir -p "$TMPDIR_TEST/bin"
  export COURT_TEST_MARKER="$TMPDIR_TEST/ejecutado"
  export COURT_TEST_ARRAY=0
  PAYLOAD='COURT_TEST_ARRAY[$(printf 0 > "$COURT_TEST_MARKER")]'
  export COURT_MAX_LOC=400 COURT_MAX_FIX_ROUNDS=1
  export COURT_SCORE_PASS=90 COURT_SCORE_CONDITIONAL=70
  export COHERENCE_SCORE_PASS=90 COHERENCE_SCORE_CONDITIONAL=70
  export COURT_ENERGY_THRESHOLD=0.2 COURT_CONDITIONAL_THRESHOLD=0.5
  export COURT_OUTPUT_FORMAT=json SAVIA_WORKSPACE_DIR="$TMPDIR_TEST"
  FINDINGS="$TMPDIR_TEST/findings.json"
  CRC="$TMPDIR_TEST/review.crc"
  printf '%s\n' '{"detail":"naming"}' > "$FINDINGS"
  printf '%s\n' 'rounds:' '  - round: 1' '  - round: 2' > "$CRC"
  # check necesita un diff, no el estado real del checkout ni otro worktree.
  cat > "$TMPDIR_TEST/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == 'diff origin/main..HEAD --stat' ]]; then
  printf '%s\n' ' 1 file changed, 1 insertion(+), 1 deletion(-)'
else
  exit 64
fi
SH
  chmod +x "$TMPDIR_TEST/bin/git"
  local script
  for script in "$COURT" "$COHERENCE" "$ROUTER" "$AGGREGATOR"; do
    [ -f "$script" ]
  done
  command -v python3 >/dev/null
}

# BATS elimina BATS_TEST_TMPDIR; no se borra ningún directorio del usuario.
teardown() { :; }

sin_ejecucion() {
  if [[ -e "$COURT_TEST_MARKER" ]]; then
    echo 'INYECCIÓN: se ejecutó la sustitución de comandos antes de rechazar la entrada'
  fi
  [ ! -e "$COURT_TEST_MARKER" ]
}

rechazo() {
  sin_ejecucion
  [ "$status" -ge 1 ]
  [ "$status" -le 3 ]
  [[ "$output" == *'ERROR:'* ]]
  [[ "$output" != *'verdict=pass'* && "$output" != *'PASS:'* ]]
}

contador_inyectado() {
  local slot="$1" script="$2"
  local args=(0 0 0 0)
  args[slot]="$PAYLOAD"
  run bash "$script" score "${args[@]}"
  rechazo
}

check_court() {
  run env PATH="$TMPDIR_TEST/bin:$PATH" "$@" bash "$COURT" check
}

@test "control de la sonda: bash vulnerable crea la marca incluso en ruta con espacios" {
  run bash -uc 'value=$1; printf "%s\n" "$((value))"' probe "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
  [ -f "$COURT_TEST_MARKER" ]
  [ "$(cat "$COURT_TEST_MARKER")" = 0 ]
}

@test "court score: zero contadores y argumentos omitidos conservan 100 pass" {
  run bash "$COURT" score
  [ "$status" -eq 0 ]
  [ "$output" = 'score=100 verdict=pass (C=0 H=0 M=0 L=0)' ]
}

@test "court score: fórmula ponderada válida produce 61 fail" {
  run bash "$COURT" score 1 1 1 1
  [ "$status" -eq 0 ]
  [ "$output" = 'score=61 verdict=fail (C=1 H=1 M=1 L=1)' ]
}

@test "court score: boundary pass 90 y conditional 89" {
  run bash "$COURT" score 0 1 0 0
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=90 verdict=pass '* ]]
  run bash "$COURT" score 0 1 0 1
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=89 verdict=conditional '* ]]
}

@test "court score: boundary conditional 70 y fail 69" {
  run bash "$COURT" score 1 0 1 2
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=70 verdict=conditional '* ]]
  run bash "$COURT" score 1 0 2 0
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=69 verdict=fail '* ]]
}

@test "court score: contador grande válido satura a zero sin desbordamiento" {
  run bash "$COURT" score 999999 999999 999999 999999
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=0 verdict=fail '* ]]
}

@test "court score: rechaza inyección aritmética en C" { contador_inyectado 0 "$COURT"; }
@test "court score: rechaza inyección aritmética en H" { contador_inyectado 1 "$COURT"; }
@test "court score: rechaza inyección aritmética en M" { contador_inyectado 2 "$COURT"; }
@test "court score: rechaza inyección aritmética en L" { contador_inyectado 3 "$COURT"; }

@test "court score: HOME con subíndice tampoco ejecuta aunque bash aborte después" {
  run bash "$COURT" score 'HOME[$(printf 0 > "$COURT_TEST_MARKER")]' 0 0 0
  rechazo
}

@test "court score: rechaza referencia indirecta a variable con payload" {
  run env COURT_TEST_INDIRECT="$PAYLOAD" bash "$COURT" score COURT_TEST_INDIRECT 0 0 0
  rechazo
}

@test "court score: invalid expresiones aritméticas no son contadores" {
  local slot
  for slot in 0 1 2 3; do
    local args=(0 0 0 0)
    args[slot]='1+1'
    run bash "$COURT" score "${args[@]}"
    rechazo
  done
}

@test "court score: invalid contador negativo no puede subir score sobre 100" {
  run bash "$COURT" score -1 0 0 0
  rechazo
}

@test "court score: invalid decimal se rechaza con diagnóstico antes de la aritmética" {
  run bash "$COURT" score 1.5 0 0 0
  rechazo
}

@test "court score: invalid octal 08 se rechaza explícitamente" {
  run bash "$COURT" score 08 0 0 0
  rechazo
}

@test "court score: invalid entero enorme no puede envolver y generar score 200" {
  run bash "$COURT" score 18446744073709551612 0 0 0
  rechazo
}

@test "court score: umbrales válidos personalizados conservan la frontera" {
  run env COURT_SCORE_PASS=100 COURT_SCORE_CONDITIONAL=99 bash "$COURT" score 0 0 0 1
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=99 verdict=conditional '* ]]
}

@test "court score: rechaza inyección en COURT_SCORE_PASS" {
  run env COURT_SCORE_PASS="$PAYLOAD" bash "$COURT" score 0 0 0 0
  rechazo
}

@test "court score: rechaza inyección en COURT_SCORE_CONDITIONAL al alcanzar esa rama" {
  run env COURT_SCORE_CONDITIONAL="$PAYLOAD" bash "$COURT" score 4 0 0 0
  rechazo
}

@test "court score: valida también umbral conditional malicioso en rama pass" {
  run env COURT_SCORE_CONDITIONAL="$PAYLOAD" bash "$COURT" score 0 0 0 0
  rechazo
}

@test "court score: invalid umbral fuera de 0 a 100 nunca produce veredicto" {
  local name
  for name in COURT_SCORE_PASS COURT_SCORE_CONDITIONAL; do
    run env "$name=101" bash "$COURT" score 0 0 0 0
    rechazo
  done
}

@test "court check: boundary dos LOC se aceptan con máximo dos" {
  check_court COURT_MAX_LOC=2
  [ "$status" -eq 0 ]
  [ "$output" = 'PASS: 2 LOC (max 2)' ]
}

@test "court check: boundary dos LOC se rechazan con máximo uno" {
  check_court COURT_MAX_LOC=1
  [ "$status" -eq 1 ]
  [[ "$output" == 'FAIL: diff is 2 LOC (max 1)'* ]]
}

@test "court check: rechaza inyección en COURT_MAX_LOC" {
  check_court "COURT_MAX_LOC=$PAYLOAD"
  rechazo
}

@test "court validate: boundary dos rondas se aceptan con máximo dos" {
  run env COURT_MAX_FIX_ROUNDS=2 bash "$COURT" validate "$CRC"
  [ "$status" -eq 0 ]
  [ "$output" = 'PASS: 2 fix round(s) (max 2)' ]
}

@test "court validate: dos rondas superan el máximo uno" {
  run bash "$COURT" validate "$CRC"
  [ "$status" -eq 1 ]
  [[ "$output" == 'FAIL: 2 fix rounds '* ]]
}

@test "court validate: rechaza inyección en COURT_MAX_FIX_ROUNDS" {
  run env COURT_MAX_FIX_ROUNDS="$PAYLOAD" bash "$COURT" validate "$CRC"
  rechazo
}

@test "court check y validate: invalid expresiones tampoco son máximos" {
  check_court COURT_MAX_LOC=1+1
  rechazo
  run env COURT_MAX_FIX_ROUNDS=1+1 bash "$COURT" validate "$CRC"
  rechazo
}

@test "coherence score: rechaza inyección en cada uno de los cuatro contadores" {
  local slot
  for slot in 0 1 2 3; do
    contador_inyectado "$slot" "$COHERENCE"
  done
}

@test "coherence score y gate: rechazan inyección en ambos umbrales de entorno" {
  local name
  for name in COHERENCE_SCORE_PASS COHERENCE_SCORE_CONDITIONAL; do
    run env "$name=$PAYLOAD" bash "$COHERENCE" score 0 0 0 0
    rechazo
    run env "$name=$PAYLOAD" bash "$COHERENCE" gate 100
    rechazo
  done
}

@test "coherence gate: rechaza inyección en score" {
  run bash "$COHERENCE" gate "$PAYLOAD"
  rechazo
}

@test "coherence gate: rechaza inyección en threshold" {
  run bash "$COHERENCE" gate 100 --threshold "$PAYLOAD"
  rechazo
}

@test "coherence gate: valida conditional malicioso incluso para score 100" {
  run bash "$COHERENCE" gate 100 --conditional "$PAYLOAD"
  rechazo
}

@test "coherence score: invalid referencias indirectas tampoco se evalúan" {
  run env COURT_TEST_INDIRECT="$PAYLOAD" bash "$COHERENCE" score COURT_TEST_INDIRECT 0 0 0
  rechazo
}

@test "coherence: límites válidos zero y 999999 no se rechazan indiscriminadamente" {
  run bash "$COHERENCE" score 999999 0 0 0
  [ "$status" -eq 0 ]
  [[ "$output" == 'score=0 verdict=fail '* ]]
  run bash "$COHERENCE" gate 100
  [ "$status" -eq 0 ]
  [[ "$output" == 'PASS: score=100 '* ]]
  run bash "$COHERENCE" gate 0
  [ "$status" -eq 1 ]
  [[ "$output" == 'FAIL: score=0 '* ]]
}

@test "coherence: invalid octal, negativos y enteros enormes se rechazan explícitamente" {
  local bad
  for bad in 08 -1 1+1 1.5 18446744073709551612; do
    run bash "$COHERENCE" score "$bad" 0 0 0
    rechazo
    run bash "$COHERENCE" gate "$bad"
    rechazo
  done
}

@test "router: ronda válida temprana conserva selección reducida" {
  run bash "$ROUTER" --findings "$FINDINGS" --round 1 --max-round 3
  [ "$status" -eq 0 ]
  [ "$output" = cognitive-judge ]
}

@test "router: boundary penúltima ronda selecciona las cinco juezas" {
  run bash "$ROUTER" --findings "$FINDINGS" --round 2 --max-round 3
  [ "$status" -eq 0 ]
  [ "$output" = $'security-judge\ncorrectness-judge\narchitecture-judge\ncognitive-judge\nspec-judge' ]
}

@test "router: rechaza inyección en round" {
  run bash "$ROUTER" --findings "$FINDINGS" --round "$PAYLOAD" --max-round 3
  rechazo
}

@test "router: rechaza inyección en max-round" {
  run bash "$ROUTER" --findings "$FINDINGS" --round 1 --max-round "$PAYLOAD"
  rechazo
}

@test "router: invalid expresión en round o max-round nunca llega a aritmética" {
  local option
  for option in --round --max-round; do
    run bash "$ROUTER" --findings "$FINDINGS" "$option" '1+1'
    rechazo
  done
}

@test "aggregator: JSONL numérico válido sigue produciendo PASS" {
  printf '%s\n' '{"judge":"test-judge","score":0.1,"weight":1}' > "$TMPDIR_TEST/judges.jsonl"
  run bash "$AGGREGATOR" "$TMPDIR_TEST/judges.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict": "PASS"'* ]]
  [[ "$output" == *'"total_energy": 0.1'* ]]
}

@test "aggregator: invalid payload en campos numéricos de stdin no ejecuta comandos" {
  local field
  for field in score weight blocking_threshold; do
    python3 - "$field" "$PAYLOAD" > "$TMPDIR_TEST/judges.jsonl" <<'PY'
import json, sys
row = dict(judge="test-judge", score=0.1, weight=1, blocking_threshold=0.5)
row[sys.argv[1]] = sys.argv[2]
print(json.dumps(row))
PY
    run bash "$AGGREGATOR" < "$TMPDIR_TEST/judges.jsonl"
    sin_ejecucion
    [ "$status" -eq 3 ]
    [[ "$output" == *'"error"'* ]]
    [[ "$output" != *'"verdict": "PASS"'* ]]
  done
}

@test "aggregator: invalid payload en ambos umbrales de entorno no se evalúa" {
  printf '%s\n' '{"judge":"test-judge","score":0.1}' > "$TMPDIR_TEST/judges.jsonl"
  local name
  for name in COURT_ENERGY_THRESHOLD COURT_CONDITIONAL_THRESHOLD; do
    run env "$name=$PAYLOAD" bash "$AGGREGATOR" "$TMPDIR_TEST/judges.jsonl"
    sin_ejecucion
    [ "$status" -ge 1 ]
    [ "$status" -le 3 ]
    [[ "$output" != *'"verdict": "PASS"'* ]]
  done
}
