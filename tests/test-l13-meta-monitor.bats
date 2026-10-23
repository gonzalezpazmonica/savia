#!/usr/bin/env bats
# L13 F1 — meta-monitor + meta-recalibrate (juicio metacognitivo)
# Linea: labs/hypotheses/l13-savia-metacognition.md

MONITOR="scripts/meta-monitor.sh"
RECAL="scripts/meta-recalibrate.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
  CAL="$FIXDIR/cal.json"
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "existe, bash -n, sin vendor cloud names, PURE_BASH" {
  [[ -x "$MONITOR" ]] && [[ -x "$RECAL" ]]
  bash -n "$MONITOR" && bash -n "$RECAL"
  run grep -niE "api\.openai\.com|api\.anthropic\.com|api\.deepseek\.com|api\.google\.com|api\.mistral\.ai" "$MONITOR" "$RECAL"
  [[ "$status" -ne 0 ]]
}

@test "M1: monitor SIN curva (calibracion default 0.5) + divergencia baja → ajusta" {
  cal_file="$FIXDIR/cal0.json"
  run bash "$MONITOR" --calibration-file "$cal_file" --task t --confidence 80 --divergence 0.2 --evidence 0.9
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'confidence_adjusted' in d
assert d['confidence_adjusted'] < d['confidence_declared']  # siempre ajusta por calibration default 0.5
"
}

@test "M1b: con calibracion 1.0 y buena evidencia → adjusted razonable (>=60)" {
  # curva perfecta: 3 success
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 80 --outcome success >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 85 --outcome success >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 90 --outcome success >/dev/null
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80 --divergence 0.1 --evidence 0.9
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['calibration'] == 1.0
assert d['confidence_adjusted'] >= 60
"
}

@test "M1c: sobreconfianza + divergencia alta → POSTPONE (ajuste fuerte)" {
  # curva baja: 1 success 1 fail -> 0.5
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 80 --outcome success >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 80 --outcome fail >/dev/null
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 90 --divergence 0.8 --evidence 0.3
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'POSTPONE' in d['action_hint']
assert d['confidence_adjusted'] < 60
"
}

@test "recalibra: curva mejora con los resultados (accuracy sube al anadir success)" {
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome fail >/dev/null
  r1=$(bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome success 2>&1 | grep -oP 'accuracy=\K[0-9.]+')
  r2=$(bash "$RECAL" --calibration-file "$CAL" --task t --predicted 80 --outcome success 2>&1 | grep -oP 'accuracy=\K[0-9.]+')
  echo "acc tras 1: $r1 ; tras 2: $r2"
  # 1 fail + 1 success = 0.5 ; +1 success = 0.667
  python3 -c "assert abs(float('$r1')-0.5)<0.01, '$r1'"
  python3 -c "assert abs(float('$r2')-0.667)<0.01, '$r2'"
}

@test "recalibracion por tarea: tareas distintas no contaminan" {
  bash "$RECAL" --calibration-file "$CAL" --task alpha --predicted 50 --outcome fail >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task beta  --predicted 90 --outcome success >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task beta  --predicted 90 --outcome success >/dev/null
  # monitor beta: calibracion global (1 success/1 fail + 2 success = 3/4=0.75) ; por tarea beta n=2 correct=2
  run bash "$MONITOR" --calibration-file "$CAL" --task beta --confidence 85 --divergence 0.2 --evidence 0.9
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['calibration'] >= 0.7  # la curva global refleja la buena calibracion en beta
"
}

@test "input invalido → exit 2 (monitor sin args; outcome no valido)" {
  run bash "$MONITOR"
  [[ "$status" -eq 2 ]]
  run bash "$RECAL" --task x --predicted 80 --outcome nope
  [[ "$status" -eq 2 ]]
}

@test "CRIT-031: ningun script escribe a CRITERIO ni CONSTITUCION (hash invariante)" {
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 80 --outcome success >/dev/null
  bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80 --divergence 0.2 --evidence 0.9 >/dev/null
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}
# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# Curva perfecta para la tarea t (cal=1.0) escrita a mano: aísla la fórmula.
perfect_curve() { printf '{"runs":[],"by_task":{"t":{"n":2,"correct":2}}}\n' > "$CAL"; }

# confidence_adjusted de meta-monitor con curva perfecta
adj() { bash "$MONITOR" --calibration-file "$CAL" --task t --confidence "$1" --divergence "$2" --evidence "$3" | jq -r '.confidence_adjusted'; }

@test "usa modo estricto de bash en monitor y recalibrate (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$MONITOR"
  grep -q '^set -uo pipefail' "$RECAL"
}

@test "formula: con calibración 1, evidencia total y divergencia 0 la confianza no cambia" {
  perfect_curve
  [ "$(adj 80 0 1)" = "80.0" ]
}

@test "formula: divergencia <= 0.6 penaliza a mitad de peso (0.2 sobre 80 → 72)" {
  perfect_curve
  [ "$(adj 80 0.2 1)" = "72.0" ]
}

@test "formula: divergencia > 0.6 penaliza a peso completo (0.7 sobre 100 → 30), 0.6 aún a mitad (→ 70)" {
  perfect_curve
  [ "$(adj 100 0.7 1)" = "30.0" ]
  [ "$(adj 100 0.6 1)" = "70.0" ]
}

@test "formula: sin evidencia resta el 30% de la confianza (100 → 70)" {
  perfect_curve
  [ "$(adj 100 0 0)" = "70.0" ]
}

@test "formula: calibración 0.25 deja el 25% de la confianza (100 → 25)" {
  printf '{"runs":[],"by_task":{"t":{"n":4,"correct":1}}}\n' > "$CAL"
  [ "$(adj 100 0 1)" = "25.0" ]
}

@test "zero floor: penalizaciones acumuladas nunca bajan de 0" {
  printf '{"runs":[],"by_task":{"t":{"n":4,"correct":0}}}\n' > "$CAL"
  [ "$(adj 100 0.9 0)" = "0.0" ]
}

@test "las bandas de acción cambian en 60 y 75 (boundary)" {
  perfect_curve
  hint() { bash "$MONITOR" --calibration-file "$CAL" --task t --confidence "$1" --divergence 0 --evidence 1 | jq -r '.action_hint'; }
  [[ "$(hint 59.9)" == POSTPONE* ]]
  [[ "$(hint 60)" == CAUTIOUS* ]]
  [[ "$(hint 74.9)" == CAUTIOUS* ]]
  [[ "$(hint 75)" == EMIT* ]]
}

@test "la calibración por tarea manda sobre la global" {
  printf '{"runs":[{"outcome":"success"},{"outcome":"success"}],"by_task":{"t":{"n":4,"correct":1}}}\n' > "$CAL"
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80
  [ "$(jq -r .calibration <<< "$output")" = "0.25" ]
}

@test "sin entrada por tarea usa la global y cuenta partial como medio acierto" {
  printf '{"runs":[{"outcome":"success"},{"outcome":"partial"},{"outcome":"fail"},{"outcome":"fail"}],"by_task":{}}\n' > "$CAL"
  run bash "$MONITOR" --calibration-file "$CAL" --task otra --confidence 80
  [ "$(jq -r .calibration <<< "$output")" = "0.375" ]
}

@test "curva corrupta, no-objeto o vacía degradan a calibración 0.5 sin fallar" {
  echo 'esto no es json' > "$CAL"
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80
  [ "$status" -eq 0 ]
  [ "$(jq -r .calibration <<< "$output")" = "0.5" ]
  echo '[1,2,3]' > "$CAL"
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80
  [ "$(jq -r .calibration <<< "$output")" = "0.5" ]
  echo '{}' > "$CAL"
  run bash "$MONITOR" --calibration-file "$CAL" --task t --confidence 80
  [ "$(jq -r .calibration <<< "$output")" = "0.5" ]
}

@test "la salida del monitor refleja task, confianza declarada, divergencia y evidencia" {
  run bash "$MONITOR" --calibration-file "$CAL" --task mi-tarea --confidence 70 --divergence 0.4 --evidence 0.8
  run jq -e '.task == "mi-tarea" and .confidence_declared == 70 and .divergence == 0.4 and .evidence == 0.8' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "invalid monitor: confianza no numérica, divergencia no numérica o sin tarea salen 2" {
  run bash "$MONITOR" --task t --confidence alta
  [ "$status" -eq 2 ]
  run bash "$MONITOR" --task t --confidence 50 --divergence mucha
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  run bash "$MONITOR" --task t --confidence 50 --evidence poca
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  run bash "$MONITOR" --confidence 50
  [ "$status" -eq 2 ]
  run bash "$MONITOR" --task t --confidence 50 --nope
  [ "$status" -eq 2 ]
}

@test "recalibrate crea el directorio de la curva y registra la ejecución con ts, tarea y predicción" {
  deep="$FIXDIR/a/b/cal.json"
  run bash "$RECAL" --calibration-file "$deep" --task t --predicted 77 --outcome success
  [ "$status" -eq 0 ]
  run jq -e '(.runs | length) == 1 and .runs[0].task == "t" and .runs[0].predicted == 77 and .runs[0].outcome == "success" and (.runs[0].ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$deep"
  [ "$status" -eq 0 ]
}

@test "recalibrate cuenta por tarea: success suma 1, partial 0.5, fail 0" {
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome success >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome partial >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome fail >/dev/null
  run jq -e '.by_task.t.n == 3 and .by_task.t.correct == 1.5' "$CAL"
  [ "$status" -eq 0 ]
}

@test "recalibrate informa accuracy con partial como medio acierto" {
  bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome success >/dev/null
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome partial
  [[ "$output" == *"runs=2 accuracy=0.75"* ]]
}

@test "recalibrate sobre curva corrupta la reinicia y registra solo la nueva ejecución" {
  echo 'basura' > "$CAL"
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome success
  [ "$status" -eq 0 ]
  run jq -e '(.runs | length) == 1 and .by_task.t.n == 1' "$CAL"
  [ "$status" -eq 0 ]
}

@test "recalibrate preserva las ejecuciones anteriores al añadir una nueva" {
  bash "$RECAL" --calibration-file "$CAL" --task a --predicted 10 --outcome fail >/dev/null
  bash "$RECAL" --calibration-file "$CAL" --task b --predicted 20 --outcome success >/dev/null
  run jq -r '[.runs[].task] | join(",")' "$CAL"
  [ "$output" = "a,b" ]
}

@test "invalid recalibrate: outcome, predicted no numérico y args ausentes salen 2 sin escribir curva" {
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted 50 --outcome nope
  [ "$status" -eq 2 ]
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted mucho --outcome success
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
  run bash "$RECAL" --calibration-file "$CAL" --task t --outcome success
  [ "$status" -eq 2 ]
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted 5 --outcome success --nope
  [ "$status" -eq 2 ]
  [[ ! -e "$CAL" ]]
}

@test "rango: evidence/divergence > 1, confidence > 100 y predicted > 100 → exit 2" {
  run bash "$MONITOR" --task t --confidence 70 --divergence 0.2 --evidence 7
  [ "$status" -eq 2 ]
  run bash "$MONITOR" --task t --confidence 70 --divergence 5 --evidence 0.5
  [ "$status" -eq 2 ]
  run bash "$MONITOR" --task t --confidence 170 --divergence 0.2 --evidence 0.5
  [ "$status" -eq 2 ]
  run bash "$RECAL" --calibration-file "$CAL" --task t --predicted 150 --outcome success
  [ "$status" -eq 2 ]
  [[ ! -e "$CAL" ]]
}
