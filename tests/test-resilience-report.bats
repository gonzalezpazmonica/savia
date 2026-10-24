#!/usr/bin/env bats
# tests/test-resilience-report.bats — SE-348: agent resilience metrics report
# Ref: docs/propuestas/SE-348-resiliencia-baseline-capas.md
# Coverage: variance_class (nominal/exploratory/dysfunctional/external),
#   weighted_error, max_consec_errors, t_rec_s, recovered, JSON output, legacy compat.

LOGGER="${BATS_TEST_DIRNAME}/../scripts/agent-run-logger.sh"
REPORT="${BATS_TEST_DIRNAME}/../scripts/resilience-report.sh"

setup() {
  set -uo pipefail
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export AGENT_ACTUALS_LOG="$TMP_DIR/agent-actuals.jsonl"
  export SAVIA_WORKSPACE_DIR="$TMP_DIR"
  touch "$AGENT_ACTUALS_LOG"
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

detail_json() {
  local run_id="$1"
  bash "$REPORT" detail "$run_id" --json
}

@test "SE-348 exploratory: completed with error then ok → exploratory, recovered, t_rec != null" {
  RUN_ID="$(bash "$LOGGER" start "se348" "recovery")"
  bash "$LOGGER" tool-call "$RUN_ID" bash error
  bash "$LOGGER" tool-call "$RUN_ID" bash ok
  bash "$LOGGER" finish "$RUN_ID" completed
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.variance_class == "exploratory"'
  echo "$OUT" | jq -e '.recovered == true'
  echo "$OUT" | jq -e '.t_rec_s != null'
}

@test "SE-348 dysfunctional: error then finish error → dysfunctional" {
  RUN_ID="$(bash "$LOGGER" start "se348" "bad")"
  bash "$LOGGER" tool-call "$RUN_ID" bash error
  bash "$LOGGER" finish "$RUN_ID" error
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.variance_class == "dysfunctional"'
}

@test "SE-348 external: aborted with no prior error signals → external" {
  RUN_ID="$(bash "$LOGGER" start "se348" "cut")"
  bash "$LOGGER" finish "$RUN_ID" aborted
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.variance_class == "external"'
  echo "$OUT" | jq -e '.recovered == false'
}

@test "SE-348 nominal: completed with no error signals → nominal, recovered false" {
  RUN_ID="$(bash "$LOGGER" start "se348" "clean")"
  bash "$LOGGER" tool-call "$RUN_ID" read ok
  bash "$LOGGER" finish "$RUN_ID" completed
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.variance_class == "nominal"'
  echo "$OUT" | jq -e '.recovered == false'
}

@test "SE-348 weighted_error: one error (0.9) + one ok (0.0) over 2 calls → 0.45" {
  RUN_ID="$(bash "$LOGGER" start "se348" "weighted")"
  bash "$LOGGER" tool-call "$RUN_ID" bash error
  bash "$LOGGER" tool-call "$RUN_ID" read ok
  bash "$LOGGER" finish "$RUN_ID" completed
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.weighted_error == 0.45'
  echo "$OUT" | jq -e '.error_rate == 0.5'
}

@test "SE-348 max_consec_errors: ok,error,error,ok → 2" {
  RUN_ID="$(bash "$LOGGER" start "se348" "streak")"
  bash "$LOGGER" tool-call "$RUN_ID" a ok
  bash "$LOGGER" tool-call "$RUN_ID" b error
  bash "$LOGGER" tool-call "$RUN_ID" c error
  bash "$LOGGER" tool-call "$RUN_ID" d ok
  bash "$LOGGER" finish "$RUN_ID" completed
  OUT="$(detail_json "$RUN_ID")"
  echo "$OUT" | jq -e '.max_consec_errors == 2'
}

@test "SE-348 summary --json: emits runs and by_agent rollup" {
  RUN_ID="$(bash "$LOGGER" start "se348-agent" "rollup")"
  bash "$LOGGER" tool-call "$RUN_ID" bash error
  bash "$LOGGER" tool-call "$RUN_ID" bash ok
  bash "$LOGGER" finish "$RUN_ID" completed
  OUT="$(bash "$REPORT" summary --json)"
  echo "$OUT" | jq -e '.runs | length == 1'
  echo "$OUT" | jq -e '.by_agent["se348-agent"].variance_classes.exploratory == 1'
  echo "$OUT" | jq -e '.by_agent["se348-agent"].runs == 1'
}

@test "SE-348 empty log: exit 0 with no rows" {
  : > "$AGENT_ACTUALS_LOG"
  run bash "$REPORT" summary
  [ "$status" -eq 0 ]
  run bash "$REPORT" summary --json
  [ "$status" -eq 0 ]
}

@test "SE-348 legacy records (no tool_events) do not break the report" {
  echo '{"spec_id":"SE-001","category":"standard","verdict":"shipped"}' >> "$AGENT_ACTUALS_LOG"
  RUN_ID="$(bash "$LOGGER" start "compat" "legacy coexist")"
  bash "$LOGGER" tool-call "$RUN_ID" bash ok
  bash "$LOGGER" finish "$RUN_ID" completed
  run bash "$REPORT" summary
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "compat"
}

@test "SE-348 detail with unknown run_id: exit 0, message to stderr" {
  run bash "$REPORT" detail "does-not-exist-000"
  [ "$status" -eq 0 ]
}

@test "SE-348 invalid flag: exit 2" {
  run bash "$REPORT" --bogus-flag
  [ "$status" -eq 2 ]
}

# ── Comportamiento con registros construidos a mano (sin pasar por el logger) ──────────

# rec <run_id> <agent> <run_status> <events-json>   → una linea schema_version 2 en el log
rec() {
  python3 - "$AGENT_ACTUALS_LOG" "$@" <<'PY'
import json, sys
log, run_id, agent, status, events = sys.argv[1:6]
r = {"schema_version": "2", "run_id": run_id, "agent": agent, "run_status": status}
ev = json.loads(events)
if ev is not None:
    r["tool_events"] = ev
open(log, "a").write(json.dumps(r) + "\n")
PY
}
# ev <status> <reliability> <ts>
ev() { printf '{"tool":"t","status":"%s","reliability":%s,"ts":"%s"}' "$1" "$2" "$3"; }
T0="2026-01-01T00:00:00Z"; T1="2026-01-01T00:00:10Z"; T2="2026-01-01T00:00:40Z"; T3="2026-01-01T00:01:00Z"
# d <run_id> <expr-jq>: detalle JSON y asercion jq
d() { run bash "$REPORT" detail "$1" --json; [ "$status" -eq 0 ]; jq -e "$2" <<< "$output" >/dev/null || { echo "jq falso: $2 -> $output"; return 1; }; }
# s <expr-jq> [args]: resumen JSON y asercion jq
s() { run bash "$REPORT" summary --json "${@:2}"; [ "$status" -eq 0 ]; jq -e "$1" <<< "$output" >/dev/null || { echo "jq falso: $1 -> $output"; return 1; }; }

@test "clases: completed sin errores es nominal; con errores es exploratory" {
  rec r1 a completed "[$(ev ok 0.0 $T0)]"
  rec r2 a completed "[$(ev error 0.9 $T0),$(ev ok 0.0 $T1)]"
  d r1 '.variance_class=="nominal" and .error_rate==0 and .max_consec_errors==0'
  d r2 '.variance_class=="exploratory"'
}

@test "clases: finish abortado con errores previos es dysfunctional, sin errores es external" {
  for st in aborted timeout error; do
    rec "e-$st" a "$st" "[$(ev error 0.9 $T0)]"
    rec "x-$st" a "$st" "[$(ev ok 0.0 $T0)]"
    d "e-$st" '.variance_class=="dysfunctional"'
    d "x-$st" '.variance_class=="external"'
  done
}

@test "clases: running es in_progress, con o sin eventos" {
  rec rr a running "[$(ev error 0.9 $T0)]"
  rec rs a running "null"
  d rr '.variance_class=="in_progress"'
  d rs '.variance_class=="in_progress"'
}

@test "sin tool_events: usa tools_invoked para las llamadas y deja las metricas a null" {
  python3 -c '
import json,sys
open(sys.argv[1],"a").write(json.dumps({"schema_version":"2","run_id":"leg","agent":"a","run_status":"completed","tools_invoked":{"bash":3,"read":4}})+"\n")' "$AGENT_ACTUALS_LOG"
  d leg '.calls==7 and .variance_class=="nominal" and .error_rate==null and .weighted_error==null and .max_consec_errors==null and .t_rec_s==null and .recovered==false'
}

@test "sin tool_events y abortado es external" {
  rec ab a aborted "null"
  d ab '.variance_class=="external"'
}

@test "error_rate y weighted_error se redondean a 4 decimales y skipped no cuenta como error" {
  rec r a completed "[$(ev error 0.5 $T0),$(ev ok 0 $T0),$(ev skipped 0 $T0)]"
  d r '.calls==3 and .error_rate==0.3333 and .weighted_error==0.1667'
}

@test "cualquier estado distinto de ok y skipped cuenta como error" {
  rec r a completed "[$(ev timeout 0.4 $T0),$(ev denied 0.2 $T0),$(ev ok 0 $T0),$(ev ok 0 $T0)]"
  d r '.error_rate==0.5 and (.weighted_error-0.15|fabs)<0.0001'
}

@test "max_consec_errors: la racha mas larga, no la ultima ni la primera" {
  rec r a completed "[$(ev error 1 $T0),$(ev ok 0 $T0),$(ev error 1 $T0),$(ev error 1 $T0),$(ev error 1 $T0),$(ev ok 0 $T0),$(ev error 1 $T0)]"
  d r '.max_consec_errors==3'
}

@test "una racha de errores al final de la ejecucion tambien cuenta" {
  rec r a error "[$(ev ok 0 $T0),$(ev error 1 $T0),$(ev error 1 $T0)]"
  d r '.max_consec_errors==2'
}

@test "skipped corta la racha igual que ok" {
  rec r a completed "[$(ev error 1 $T0),$(ev skipped 0 $T0),$(ev error 1 $T0)]"
  d r '.max_consec_errors==1'
}

@test "t_rec_s: tiempo entre el primer error y el siguiente ok" {
  rec r a completed "[$(ev error 1 $T0),$(ev error 1 $T1),$(ev ok 0 $T2)]"
  d r '.t_rec_s==40 and .recovered==true'
}

@test "t_rec_s es la mediana de varias recuperaciones" {
  # recuperaciones: T0->T1 = 10 s, T1->T3 = 50 s, T0->T2 = 40 s; mediana 40
  rec r a completed "[$(ev error 1 $T0),$(ev ok 0 $T1),$(ev error 1 $T1),$(ev ok 0 $T3),$(ev error 1 $T0),$(ev ok 0 $T2)]"
  d r '.t_rec_s==40'
}

@test "t_rec_s con numero par de recuperaciones es la media de las dos centrales" {
  rec r a completed "[$(ev error 1 $T0),$(ev ok 0 $T1),$(ev error 1 $T0),$(ev ok 0 $T2)]"
  d r '.t_rec_s==25'
}

@test "un error sin recuperacion no genera t_rec_s ni recovered" {
  rec r a completed "[$(ev ok 0 $T0),$(ev error 1 $T1)]"
  d r '.t_rec_s==null and .recovered==false'
}

@test "una recuperacion solo cuenta si la racha termina en ok (skipped no recupera)" {
  rec r a completed "[$(ev error 1 $T0),$(ev skipped 0 $T1),$(ev ok 0 $T2)]"
  d r '.t_rec_s==null and .recovered==false'
}

@test "recovered exige que la ejecucion haya terminado completed" {
  rec r a error "[$(ev error 1 $T0),$(ev ok 0 $T1)]"
  d r '.t_rec_s==10 and .recovered==false'
}

@test "marcas de tiempo invalidas o ausentes no producen t_rec_s" {
  rec r1 a completed '[{"tool":"t","status":"error","reliability":1,"ts":"ayer"},{"tool":"t","status":"ok","reliability":0,"ts":"2026-01-01T00:00:10Z"}]'
  rec r2 a completed '[{"tool":"t","status":"error","reliability":1},{"tool":"t","status":"ok","reliability":0}]'
  d r1 '.t_rec_s==null and .recovered==false'
  d r2 '.t_rec_s==null'
}

@test "reliability ausente cuenta como 0.0 en el error ponderado" {
  rec r a completed '[{"tool":"t","status":"error","ts":"2026-01-01T00:00:00Z"},{"tool":"t","status":"ok","reliability":0,"ts":"2026-01-01T00:00:01Z"}]'
  d r '.weighted_error==0 and .error_rate==0.5'
}

@test "lineas ajenas se ignoran: JSON roto, vacias, sin run_id o con otro schema_version" {
  printf 'no es json\n\n{"run_id":"x","schema_version":"1","agent":"a","run_status":"completed"}\n{"schema_version":"2","agent":"a"}\n' >> "$AGENT_ACTUALS_LOG"
  rec ok1 a completed "[$(ev ok 0 $T0)]"
  s '(.runs|length)==1 and .runs[0].run_id=="ok1"'
}

@test "detail JSON incluye los eventos y la lista de runs del resumen no" {
  rec r a completed "[$(ev ok 0 $T0)]"
  d r '(.events|length)==1 and .events[0].status=="ok"'
  s '(.runs[0]|has("events"))==false'
}

@test "detail de texto: cabecera, metricas con 3 y 1 decimales y tabla de eventos" {
  rec r a completed "[$(ev error 0.5 $T0),$(ev ok 0 $T1)]"
  run bash "$REPORT" detail r
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_id: r"* ]]
  [[ "$output" == *"agent: a   status: completed   calls: 2"* ]]
  [[ "$output" == *"error_rate: 0.500   weighted_error: 0.250   max_consec_errors: 1"* ]]
  [[ "$output" == *"t_rec_s: 10.0   recovered: True   variance_class: exploratory"* ]]
  [[ "$output" == *"tool events:"* ]]
  echo "$output" | grep -Eq '^  t +error +rel=0\.5 ts=2026-01-01T00:00:00Z'
}

@test "detail de una ejecucion sin eventos muestra rayas en las metricas vacias" {
  rec r a aborted "null"
  run bash "$REPORT" detail r
  [[ "$output" == *"error_rate: —"* && "$output" == *"t_rec_s: —"* ]]
}

@test "detail con run_id desconocido avisa en stderr y sale con 0 sin stdout" {
  rec r a completed "[$(ev ok 0 $T0)]"
  run bash -c "bash '$REPORT' detail nada 2>&1 >/dev/null"
  [[ "$output" == *"(no run with run_id=nada)"* ]]
  run bash -c "bash '$REPORT' detail nada 2>/dev/null"
  [ -z "$output" ]
}

@test "detail sin run_id es un error de uso" {
  run bash "$REPORT" detail
  [ "$status" -ne 0 ]
}

@test "--agent filtra tanto el resumen como el detalle" {
  rec r1 alfa completed "[$(ev ok 0 $T0)]"
  rec r2 beta completed "[$(ev ok 0 $T0)]"
  s '(.runs|length)==1 and .runs[0].agent=="alfa" and (.by_agent|keys)==["alfa"]' --agent alfa
  run bash "$REPORT" detail r2 --agent alfa
  [ "$status" -eq 0 ]
  [[ "$output" != *"run_id: r2"* ]]
}

@test "resumen JSON por agente: medias, mediana de t_rec y recuento de clases" {
  rec r1 a completed "[$(ev error 1 $T0),$(ev ok 0 $T1)]"
  rec r2 a completed "[$(ev ok 0 $T0),$(ev ok 0 $T1)]"
  rec r3 a error "[$(ev error 1 $T0)]"
  s '.by_agent.a.runs==3 and (.by_agent.a.error_rate_avg-0.5|fabs)<0.0001 and (.by_agent.a.weighted_error_avg-0.5|fabs)<0.0001 and .by_agent.a.t_rec_s_median==10 and .by_agent.a.variance_classes=={"exploratory":1,"nominal":1,"dysfunctional":1}'
}

@test "resumen JSON: un agente sin ninguna metrica da null en las medias" {
  rec r1 a aborted "null"
  s '.by_agent.a.error_rate_avg==null and .by_agent.a.weighted_error_avg==null and .by_agent.a.t_rec_s_median==null and .by_agent.a.variance_classes=={"external":1}'
}

@test "un run sin agente se agrupa como unknown" {
  python3 -c '
import json,sys
open(sys.argv[1],"a").write(json.dumps({"schema_version":"2","run_id":"na","run_status":"completed","tool_events":[]})+"\n")' "$AGENT_ACTUALS_LOG"
  s '.by_agent|has("unknown")'
}

@test "resumen de texto: una fila por agente ordenada, con columnas calculadas" {
  rec r1 zeta completed "[$(ev error 1 $T0),$(ev ok 0 $T1),$(ev ok 0 $T1)]"
  rec r2 alfa completed "[$(ev ok 0 $T0)]"
  run bash "$REPORT" summary
  [ "$status" -eq 0 ]
  [[ "$(sed -n 1p <<< "$output")" == agent*runs*calls*err_rate*w_err*max_cons*t_rec_s*class ]]
  [[ "$(sed -n 2p <<< "$output")" == alfa* ]]
  [[ "$(sed -n 3p <<< "$output")" == zeta* ]]
  echo "$output" | grep -Eq '^zeta +1 +3 +0\.333 +0\.333 +1 +10\.0 +exploratory'
  echo "$output" | grep -Eq '^alfa +1 +1 +0\.000 +0\.000 +0 +— +nominal'
}

@test "resumen de texto: la clase dominante es la mas frecuente" {
  rec r1 a completed "[$(ev ok 0 $T0)]"
  rec r2 a completed "[$(ev ok 0 $T0)]"
  rec r3 a error "[$(ev error 1 $T0)]"
  run bash "$REPORT" summary
  echo "$output" | grep -Eq '^a +3 +3 .* nominal$'
}

@test "resumen de texto sin runs imprime (no runs)" {
  run bash "$REPORT" summary
  [[ "$output" == *"(no runs)"* ]]
}

@test "sin fichero de log: aviso en stderr y exit 0" {
  mv "$AGENT_ACTUALS_LOG" "$TMP_DIR/ausente.jsonl"
  run bash -c "bash '$REPORT' summary 2>&1 >/dev/null"
  [[ "$output" == *"(no agent-actuals log at $AGENT_ACTUALS_LOG)"* ]]
  run bash "$REPORT" summary
  [ "$status" -eq 0 ]
}

@test "--help imprime la cabecera de uso y sale con 0" {
  run bash "$REPORT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"resilience-report.sh"* && "$output" == *"variance_class"* ]]
}

@test "la bandera desconocida nombra el argumento" {
  run bash "$REPORT" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag '--nope'"* ]]
}

@test "AGENT_ACTUALS_LOG manda sobre la ruta por defecto del workspace" {
  mkdir -p "$TMP_DIR/data"
  echo '{"schema_version":"2","run_id":"dflt","agent":"zz","run_status":"completed","tool_events":[]}' > "$TMP_DIR/data/agent-actuals.jsonl"
  rec propio a completed "[$(ev ok 0 $T0)]"
  s '(.runs|map(.run_id))==["propio"]'
  unset AGENT_ACTUALS_LOG
  s '(.runs|map(.run_id))==["dflt"]'
}

@test "un registro sin run_status se considera en curso" {
  python3 -c '
import json,sys
open(sys.argv[1],"a").write(json.dumps({"schema_version":"2","run_id":"sinst","agent":"a","tool_events":[{"tool":"t","status":"ok","reliability":0,"ts":"2026-01-01T00:00:00Z"}]})+"\n")' "$AGENT_ACTUALS_LOG"
  d sinst '.run_status=="running" and .variance_class=="in_progress"'
}

@test "resumen JSON: varias ejecuciones de la misma clase se suman" {
  rec r1 a completed "[$(ev ok 0 $T0)]"
  rec r2 a completed "[$(ev ok 0 $T0)]"
  rec r3 a completed "[$(ev ok 0 $T0)]"
  s '.by_agent.a.variance_classes=={"nominal":3}'
}

@test "resumen de texto: max_cons es el maximo entre las ejecuciones del agente" {
  rec r1 a error "[$(ev error 1 $T0),$(ev error 1 $T0),$(ev error 1 $T0)]"
  rec r2 a completed "[$(ev error 1 $T0),$(ev ok 0 $T1)]"
  run bash "$REPORT" summary
  echo "$output" | grep -Eq '^a +2 +5 +0\.750 +0\.750 +3 +10\.0 '
}
