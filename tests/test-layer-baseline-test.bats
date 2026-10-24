#!/usr/bin/env bats
# tests/test-layer-baseline-test.bats — SE-348: criterion 7 baseline test
# Ref: docs/propuestas/SE-348-resiliencia-baseline-capas.md

BASELINE_TEST="${BATS_TEST_DIRNAME}/../scripts/layer-baseline-test.sh"

setup() {
  set -uo pipefail
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

write_metrics() {
  local file="$1"
  local content="$2"
  printf '%s' "$content" > "$file"
}

@test "SE-348 JUSTIFIED: delta above min-delta → exit 0" {
  FULL="$TMP_DIR/full.json"
  BASE="$TMP_DIR/base.json"
  write_metrics "$FULL" '{"a":0.8,"b":0.9}'
  write_metrics "$BASE" '{"a":0.7,"b":0.8}'
  run bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "JUSTIFIED"
}

@test "SE-348 UNJUSTIFIED: delta below min-delta → exit 1" {
  FULL="$TMP_DIR/full.json"
  BASE="$TMP_DIR/base.json"
  write_metrics "$FULL" '{"a":0.72}'
  write_metrics "$BASE" '{"a":0.70}'
  run bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "UNJUSTIFIED"
}

@test "SE-348 cost-multiplier 2.0: delta 0.11 JUSTIFIED, delta 0.10 UNJUSTIFIED (strict >)" {
  FULL="$TMP_DIR/full.json"
  BASE="$TMP_DIR/base.json"
  write_metrics "$BASE" '{"a":0.70}'
  write_metrics "$FULL" '{"a":0.81}'
  run bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05 --cost-multiplier 2.0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "JUSTIFIED"
  echo "$output" | grep -q "Effective threshold: 0.1"

  write_metrics "$FULL" '{"a":0.80}'
  run bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05 --cost-multiplier 2.0
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "UNJUSTIFIED"
}

@test "SE-348 missing file → exit 2" {
  run bash "$BASELINE_TEST" --full-metrics "$TMP_DIR/nope.json" --baseline-metrics "$TMP_DIR/also-nope.json"
  [ "$status" -eq 2 ]
}

@test "SE-348 --json emits schema {avg_delta, threshold, status, deltas}" {
  FULL="$TMP_DIR/full.json"
  BASE="$TMP_DIR/base.json"
  write_metrics "$FULL" '{"a":0.8}'
  write_metrics "$BASE" '{"a":0.7}'
  OUT="$(bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05 --json)"
  echo "$OUT" | jq -e '.status == "JUSTIFIED"'
  echo "$OUT" | jq -e '.avg_delta == 0.1'
  echo "$OUT" | jq -e '.threshold == 0.05'
  echo "$OUT" | jq -e '.deltas | length == 1'
}

@test "SE-348 null and string metrics are ignored" {
  FULL="$TMP_DIR/full.json"
  BASE="$TMP_DIR/base.json"
  write_metrics "$FULL" '{"a":0.8,"x":null,"s":"text"}'
  write_metrics "$BASE" '{"a":0.7,"x":0.9,"s":"other"}'
  OUT="$(bash "$BASELINE_TEST" --full-metrics "$FULL" --baseline-metrics "$BASE" --min-delta 0.05 --json)"
  echo "$OUT" | jq -e '.compared_metrics == 1'
  echo "$OUT" | jq -e '.deltas[0].metric == "a"'
}

@test "SE-348 invalid flag → exit 2" {
  run bash "$BASELINE_TEST" --bogus
  [ "$status" -eq 2 ]
}

# ── Comportamiento: umbral, promedio, filtrado de metricas y errores de entrada ─────────

# lbt <full-json> <base-json> [args...]: escribe los dos ficheros y ejecuta
lbt() {
  printf '%s' "$1" > "$TMP_DIR/f.json"; printf '%s' "$2" > "$TMP_DIR/b.json"; shift 2
  bash "$BASELINE_TEST" --full-metrics "$TMP_DIR/f.json" --baseline-metrics "$TMP_DIR/b.json" "$@"
}
# jq sobre la salida JSON de lbt
lj() { local f="$1" b="$2" e="$3" o; shift 3; o=$(lbt "$f" "$b" --json "$@" || true); jq -e "$e" <<< "$o" >/dev/null || { echo "jq falso: $e -> $o"; return 1; }; }

@test "un empate exacto con el umbral no justifica la capa (comparacion estricta)" {
  run lbt '{"a":0.75}' '{"a":0.5}' --min-delta 0.25
  [ "$status" -eq 1 ]
  [[ "$output" == *"Status: UNJUSTIFIED"* ]]
}

@test "un epsilon por encima del umbral si la justifica" {
  run lbt '{"a":0.76}' '{"a":0.5}' --min-delta 0.25
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: JUSTIFIED"* ]]
}

@test "el umbral por defecto es 0.05 y el multiplicador por defecto 1.0" {
  lj '{"a":1}' '{"a":0}' '.min_delta==0.05 and .cost_multiplier==1.0 and .threshold==0.05'
}

@test "el umbral efectivo es min-delta por multiplicador" {
  lj '{"a":1}' '{"a":0}' '.threshold-0.6|fabs<1e-9' --min-delta 0.2 --cost-multiplier 3
}

@test "el delta medio se promedia entre metricas con signos distintos" {
  lj '{"a":0.9,"b":0.5}' '{"a":0.5,"b":0.7}' '.avg_delta==0.1 and .compared_metrics==2'
}

@test "una metrica que empeora arrastra el promedio y puede invertir la decision" {
  run lbt '{"a":0.9,"b":0.1}' '{"a":0.7,"b":0.5}' --min-delta 0.05
  [ "$status" -eq 1 ]
  [[ "$output" == *"Average observed delta: -0.1"* ]]
}

@test "un delta negativo nunca justifica la capa" {
  run lbt '{"a":0.2}' '{"a":0.9}'
  [ "$status" -eq 1 ]
}

@test "min-delta cero: cualquier mejora estricta justifica y el empate no" {
  run lbt '{"a":0.51}' '{"a":0.5}' --min-delta 0
  [ "$status" -eq 0 ]
  run lbt '{"a":0.5}' '{"a":0.5}' --min-delta 0
  [ "$status" -eq 1 ]
}

@test "los deltas se redondean a 4 decimales" {
  lj '{"a":0.123456}' '{"a":0.1}' '.deltas[0].delta==0.0235 and .avg_delta==0.0235'
}

@test "cada delta lleva metrica, full, baseline y delta" {
  lj '{"lat":10,"acc":0.9}' '{"lat":4,"acc":0.8}' '(.deltas|length)==2 and (.deltas|map(.metric)|sort)==["acc","lat"] and ([.deltas[]|select(.metric=="lat")][0]|.full==10 and .baseline==4 and .delta==6)'
}

@test "los booleanos no son metricas numericas" {
  lj '{"a":0.8,"ok":true}' '{"a":0.7,"ok":false}' '.compared_metrics==1 and .deltas[0].metric=="a"'
}

@test "una metrica cuyo valor es cadena en un solo lado se ignora" {
  lj '{"a":0.8,"c":"7"}' '{"a":0.7,"c":3}' '.compared_metrics==1'
  lj '{"a":0.8,"c":7}' '{"a":0.7,"c":"3"}' '.compared_metrics==1'
}

@test "las metricas presentes en un solo fichero no cuentan" {
  lj '{"a":0.8,"solo_full":9}' '{"a":0.7,"solo_base":1}' '.compared_metrics==1 and .avg_delta==0.1'
}

@test "enteros y flotantes se comparan igual" {
  lj '{"n":3}' '{"n":1}' '.avg_delta==2'
}

@test "sin metricas comunes: UNJUSTIFIED, delta 0 y aviso legible" {
  run lbt '{"a":1}' '{"b":1}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Metrics compared: 0"* ]]
  [[ "$output" == *"(no common numeric metrics — cannot judge)"* ]]
  lj '{"a":1}' '{"b":1}' '.status=="UNJUSTIFIED" and .compared_metrics==0 and .avg_delta==0 and .deltas==[]' --min-delta 0
}

@test "la salida humana incluye cabecera, umbral y la tabla de metricas" {
  run lbt '{"acc":0.9}' '{"acc":0.7}' --min-delta 0.1 --cost-multiplier 1.5
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Layer Baseline Test (criterion 7) ==="* ]]
  [[ "$output" == *"Min delta: 0.1   Cost multiplier: 1.5   Effective threshold: 0.15"* ]]
  [[ "$output" == *"Metrics compared: 1   Average observed delta: 0.2"* ]]
  [[ "$output" == *"Metric "*"Full "*"Baseline "*"Delta"* ]]
  echo "$output" | grep -Eq '^  acc +0\.9 +0\.7 +0\.2'
}

@test "el modo --json imprime solo JSON y mantiene el exit code de la decision" {
  run lbt '{"a":0.5}' '{"a":0.5}' --json
  [ "$status" -eq 1 ]
  jq -e '.status=="UNJUSTIFIED"' <<< "$output" >/dev/null
  [[ "$output" != *"==="* ]]
}

@test "falta --full-metrics, falta --baseline-metrics: exit 2 con mensaje" {
  echo '{}' > "$TMP_DIR/x.json"
  run bash "$BASELINE_TEST" --baseline-metrics "$TMP_DIR/x.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--full-metrics required"* ]]
  run bash "$BASELINE_TEST" --full-metrics "$TMP_DIR/x.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--baseline-metrics required"* ]]
}

@test "fichero inexistente: exit 2 nombrando el fichero (cada lado por separado)" {
  echo '{}' > "$TMP_DIR/x.json"
  run bash "$BASELINE_TEST" --full-metrics "$TMP_DIR/nope.json" --baseline-metrics "$TMP_DIR/x.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"file not found: $TMP_DIR/nope.json"* ]]
  run bash "$BASELINE_TEST" --full-metrics "$TMP_DIR/x.json" --baseline-metrics "$TMP_DIR/nope2.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"file not found: $TMP_DIR/nope2.json"* ]]
}

@test "JSON mal formado: exit 2 y no una decision" {
  run lbt '{"a":' '{"a":1}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"Error loading metrics"* ]]
  [[ "$output" != *"JUSTIFIED"* ]]
}

@test "bandera desconocida: exit 2 nombrandola" {
  run bash "$BASELINE_TEST" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag '--nope'"* ]]
}

@test "--help y -h imprimen el uso y salen con 0" {
  for h in --help -h; do
    run bash "$BASELINE_TEST" "$h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"layer-baseline-test.sh"* ]]
    [[ "$output" == *"--cost-multiplier"* ]]
  done
}

@test "un valor no numerico de --min-delta falla sin dar una decision" {
  run lbt '{"a":1}' '{"a":0}' --min-delta abc
  [ "$status" -ne 0 ]
  [[ "$output" != *"Status:"* ]]
}

@test "un booleano en un solo lado tampoco es metrica comparable" {
  lj '{"a":0.8,"ok":true}' '{"a":0.7,"ok":3}' '.compared_metrics==1'
  lj '{"a":0.8,"ok":3}' '{"a":0.7,"ok":false}' '.compared_metrics==1'
}

@test "--json devuelve el multiplicador y el min-delta recibidos" {
  lj '{"a":1}' '{"a":0}' '.cost_multiplier==3 and .min_delta==0.2' --min-delta 0.2 --cost-multiplier 3
}
