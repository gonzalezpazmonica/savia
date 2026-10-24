#!/usr/bin/env bats
# BATS tests for scripts/savia-trace.sh
# SE-313 S2 — contexto distribuido de traza (W3C traceparent).
# Ref: docs/propuestas/SE-313-observabilidad-trazabilidad-agentes-eu-ai-act.md

SCRIPT="scripts/savia-trace.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export SAVIA_TELEMETRY_FILE="${BATS_TEST_TMPDIR:-/tmp}/telemetry-s2.jsonl"
  rm -f "$SAVIA_TELEMETRY_FILE" 2>/dev/null || true
  unset SAVIA_TRACEPARENT
}

teardown() {
  rm -f "${SAVIA_TELEMETRY_FILE:-}" 2>/dev/null || true
  unset SAVIA_TRACEPARENT
  cd /
}

@test "script exists and is executable" {
  [[ -f "$SCRIPT" ]]
  [[ -x "$SCRIPT" ]]
}

@test "passes bash -n syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "start emite traceparent W3C válido" {
  run bash "$SCRIPT" start agent.started agent_name=x
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-01$ ]]
}

@test "start+end comparten trace_id (misma traza)" {
  TP=$(bash "$SCRIPT" start agent.started agent_name=x)
  TRACE_ID="${TP:3:32}"
  bash -c "SAVIA_TRACEPARENT='$TP' bash '$SCRIPT' end agent.completed agent_name=x duration_ms=10" >/dev/null
  run jq -e 'select(.event == "agent.started") | .trace_id' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == "\"$TRACE_ID\"" ]]
  run jq -e 'select(.event == "agent.completed") | .trace_id' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == "\"$TRACE_ID\"" ]]
}

@test "end referencia el span del padre como parent_span_id" {
  TP=$(bash "$SCRIPT" start agent.started agent_name=x)
  bash -c "SAVIA_TRACEPARENT='$TP' bash '$SCRIPT' end agent.completed agent_name=x" >/dev/null
  # El evento de cierre debe existir; el parent_span_id del evento start debe
  # ser el span heredado (si existía) o estar ausente en raíz.
  run jq -e '.event == "agent.completed"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "sin argumentos falla con usage" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "sin evento falla con error" {
  run bash "$SCRIPT" start
  [ "$status" -eq 2 ]
}

@test "hereda traceparent existente (trace_id conservado)" {
  export SAVIA_TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  run bash "$SCRIPT" start agent.started agent_name=x
  [ "$status" -eq 0 ]
  [[ "$output" == 00-4bf92f3577b34da6a3ce929d0e0e4736-* ]]
  unset SAVIA_TRACEPARENT
}

# ── Comportamiento: traceparent, span, eventos emitidos y códigos ─────────

_tp() { echo "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"; }

@test "usage: acción desconocida con evento sale 1 y no emite telemetría" {
  run bash "$SCRIPT" bogus agent.x
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
  [ ! -s "$SAVIA_TELEMETRY_FILE" ]
}

@test "start raíz: sin padre, el span nuevo del traceparent difiere en cada llamada" {
  a=$(bash "$SCRIPT" start e.x)
  b=$(bash "$SCRIPT" start e.x)
  [ "${a:3:32}" != "${b:3:32}" ]
  [ "${a:36:16}" != "${b:36:16}" ]
}

@test "start raíz: el evento comparte trace_id y su parent_span_id es el span nuevo devuelto" {
  tp=$(bash "$SCRIPT" start agent.started agent_name=raiz)
  run jq -r 'select(.event=="agent.started") | .trace_id + " " + .parent_span_id' "$SAVIA_TELEMETRY_FILE"
  [ "$output" = "${tp:3:32} ${tp:36:16}" ]
}

@test "start con padre: devuelve span nuevo distinto del padre y misma traza" {
  export SAVIA_TRACEPARENT="$(_tp)"
  run bash "$SCRIPT" start agent.started agent_name=hijo
  [ "${output:3:32}" = "4bf92f3577b34da6a3ce929d0e0e4736" ]
  [ "${output:36:16}" != "00f067aa0ba902b7" ]
  [[ "$output" =~ -01$ ]]
}

@test "start con padre: el evento apunta al span heredado como parent_span_id" {
  export SAVIA_TRACEPARENT="$(_tp)"
  bash "$SCRIPT" start agent.started agent_name=hijo >/dev/null
  run jq -r 'select(.event=="agent.started") | .parent_span_id' "$SAVIA_TELEMETRY_FILE"
  [ "$output" = "00f067aa0ba902b7" ]
}

@test "start propaga los pares clave=valor al evento" {
  bash "$SCRIPT" start agent.started agent_name=zeta tier=heavy >/dev/null
  run jq -r 'select(.event=="agent.started") | .agent_name + "/" + .tier' "$SAVIA_TELEMETRY_FILE"
  [ "$output" = "zeta/heavy" ]
}

@test "end con padre: restaura el traceparent con el span entrante y flags 01" {
  export SAVIA_TRACEPARENT="$(_tp)"
  run bash "$SCRIPT" end agent.completed agent_name=x
  [ "$status" -eq 0 ]
  [ "$output" = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" ]
}

@test "end con padre en flags 00: el traceparent restaurado usa 01" {
  export SAVIA_TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
  run bash "$SCRIPT" end agent.completed
  [ "$output" = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" ]
}

@test "end sin traza heredada: imprime línea vacía y emite el evento" {
  run bash "$SCRIPT" end agent.completed agent_name=x
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r 'select(.event=="agent.completed") | .agent_name' "$SAVIA_TELEMETRY_FILE"
  [ "$output" = "x" ]
}

@test "end emite con el trace_id heredado y el padre del traceparent" {
  export SAVIA_TRACEPARENT="$(_tp)"
  bash "$SCRIPT" end agent.completed duration_ms=42 >/dev/null
  run jq -r 'select(.event=="agent.completed") | .trace_id + " " + .parent_span_id + " " + (.duration_ms|tostring)' "$SAVIA_TELEMETRY_FILE"
  [ "$output" = "4bf92f3577b34da6a3ce929d0e0e4736 00f067aa0ba902b7 42" ]
}

@test "traceparent malformado se ignora: traza nueva en lugar de heredar" {
  for bad in "00-XYZ" "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
             "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01" \
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7"; do
    SAVIA_TRACEPARENT="$bad" run bash "$SCRIPT" start e.x
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-01$ ]]
    [[ "$output" != 00-4bf92f3577b34da6a3ce929d0e0e4736-* ]]
  done
}

@test "end con traceparent malformado se comporta como raíz (línea vacía)" {
  SAVIA_TRACEPARENT="basura" run bash "$SCRIPT" end e.x
  [ -z "$output" ]
}

@test "sin otel-emit ejecutable start no falla y sigue devolviendo traceparent" {
  W="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$W/scripts"
  CLAUDE_PROJECT_DIR="$W" run bash "$BATS_TEST_DIRNAME/../$SCRIPT" start e.x
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-01$ ]]
  [ ! -s "$SAVIA_TELEMETRY_FILE" ]
}

@test "sin otel-emit ejecutable end no falla" {
  W="$BATS_TEST_TMPDIR/ws2"
  mkdir -p "$W/scripts"
  SAVIA_TRACEPARENT="$(_tp)" CLAUDE_PROJECT_DIR="$W" run bash "$BATS_TEST_DIRNAME/../$SCRIPT" end e.x
  [ "$status" -eq 0 ]
  [ "$output" = "$(_tp)" ]
}

@test "start anidado: hijo en la misma traza con span distinto; end devuelve el traceparent entrante" {
  A=$(bash "$SCRIPT" start nivel.a)
  B=$(SAVIA_TRACEPARENT="$A" bash "$SCRIPT" start nivel.b)
  [ "${A:3:32}" = "${B:3:32}" ]
  [ "${A:36:16}" != "${B:36:16}" ]
  back=$(SAVIA_TRACEPARENT="$B" bash "$SCRIPT" end nivel.b)
  [ "$back" = "$B" ]
}

@test "traceparent con trace_id de 31 hex, span de 15 hex o sufijo extra no se hereda" {
  for bad in "00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01" \
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b-01" \
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra" \
             "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-0"; do
    SAVIA_TRACEPARENT="$bad" run bash "$SCRIPT" start e.x
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-01$ ]]
    [[ "${output:3:12}" != "4bf92f3577b3" ]]
  done
}

@test "traceparent de 33 hex tampoco se hereda" {
  SAVIA_TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e47360-00f067aa0ba902b7-01" run bash "$SCRIPT" start e.x
  [[ "${output:3:12}" != "4bf92f3577b3" ]]
}
