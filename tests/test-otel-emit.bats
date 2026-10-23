#!/usr/bin/env bats
# BATS tests for scripts/otel-emit.sh
# SE-313 S1 — emisor de eventos de telemetría estándar (savia.event/1.0).
# Ref: docs/propuestas/SE-313-observabilidad-trazabilidad-agentes-eu-ai-act.md

SCRIPT="scripts/otel-emit.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export SAVIA_TELEMETRY_FILE="${BATS_TEST_TMPDIR:-/tmp}/telemetry-events.jsonl"
  rm -f "$SAVIA_TELEMETRY_FILE" 2>/dev/null || true
}

teardown() {
  rm -f "${SAVIA_TELEMETRY_FILE:-}" 2>/dev/null || true
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

@test "emite evento válido con trace_id y span_id" {
  run bash "$SCRIPT" agent.started agent_name=drift-auditor tier=heavy duration_ms=42
  [ "$status" -eq 0 ]
  [[ -f "$SAVIA_TELEMETRY_FILE" ]]
  run jq -e '.schema == "savia.event/1.0" and .event == "agent.started" and .trace_id and .span_id' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "campos numéricos se emiten sin comillas" {
  run bash "$SCRIPT" agent.completed agent_name=test exit_code=0 duration_ms=1234
  [ "$status" -eq 0 ]
  run jq -e '.duration_ms == 1234' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
  # exit_code debe ser entero, no string
  run jq -e '.exit_code | type == "number"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "empty event name writes nothing and fails with 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ ! -f "$SAVIA_TELEMETRY_FILE" ]]
}

@test "hereda traceparent si se propaga" {
  export SAVIA_TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  run bash "$SCRIPT" dispatch.resolved agent_name=x
  [ "$status" -eq 0 ]
  run jq -e '.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736" and .parent_span_id == "00f067aa0ba902b7"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
  unset SAVIA_TRACEPARENT
}

@test "escape de comillas en valores string" {
  run bash "$SCRIPT" dispatch.failed agent_name=x error="Model not found: deepseek/deepseek-v4-pro"
  [ "$status" -eq 0 ]
  run jq -e '.error == "Model not found: deepseek/deepseek-v4-pro"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "SAVIA_TELEMETRY_REDACT=1 degrada a solo ts+event (SE-313 S5)" {
  export SAVIA_TELEMETRY_REDACT=1
  run bash "$SCRIPT" agent.completed agent_name=secret-user gen_ai_request_model=deepseek/deepseek-v4-pro
  [ "$status" -eq 0 ]
  [[ -f "$SAVIA_TELEMETRY_FILE" ]]
  run jq -e '.schema == "savia.event/1.0" and .event == "agent.completed" and (has("agent_name") | not) and (has("gen_ai_request_model") | not)' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
  unset SAVIA_TELEMETRY_REDACT
}

@test "paths absolutos se redactan a placeholder {project} (SE-313 S5)" {
  run bash "$SCRIPT" tool.executed target="/home/monica/savia/scripts/savia-env.sh"
  [ "$status" -eq 0 ]
  # /home/<user>/ -> {project}/; el workspace root permanece como subruta relativa
  run jq -e '.target | startswith("{project}/") and (contains("/home/") | not)' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# Evento operation.started que cumple el contrato cerrado (SE-397 F4).
op_started() {
  local rev; rev="$(printf '0%.0s' $(seq 1 64))"
  bash "$SCRIPT" operation.started \
    operation_id=0123456789abcdef0123456789abcdef request_id=req-1 "flow_id=${1:-flow:read}" \
    "model_revision=$rev" frontend_id=test sequence=0 outcome=unknown
}

@test "usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "bad traceparent is ignored: new trace, no parent_span_id" {
  export SAVIA_TRACEPARENT="00-NOTHEX-00f067aa0ba902b7-01"
  run bash "$SCRIPT" dispatch.resolved agent_name=x
  [ "$status" -eq 0 ]
  run jq -e '(.trace_id | test("^[0-9a-f]{32}$")) and (has("parent_span_id") | not)' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "traceparent heredado genera span_id propio distinto del parent" {
  export SAVIA_TRACEPARENT="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  run bash "$SCRIPT" dispatch.resolved agent_name=x
  [ "$status" -eq 0 ]
  run jq -e '(.span_id | test("^[0-9a-f]{16}$")) and .span_id != "00f067aa0ba902b7"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "sin traceparent cada emisión genera trace_id distinto y se anexan dos líneas" {
  bash "$SCRIPT" agent.started agent_name=a
  bash "$SCRIPT" agent.started agent_name=b
  [ "$(wc -l < "$SAVIA_TELEMETRY_FILE")" -eq 2 ]
  [ "$(jq -r '.trace_id' "$SAVIA_TELEMETRY_FILE" | sort -u | wc -l)" -eq 2 ]
}

@test "null solo es JSON null para request_id y evidence_ref; otras claves lo emiten como texto" {
  run bash "$SCRIPT" tool.executed request_id=null evidence_ref=null note=null
  [ "$status" -eq 0 ]
  run jq -e '.request_id == null and .evidence_ref == null and .note == "null"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "claves de identidad numéricas se emiten como string, no como número" {
  run bash "$SCRIPT" tool.executed request_id=12345 phase=7 count=12345
  [ "$status" -eq 0 ]
  run jq -e '(.request_id | type == "string") and (.phase | type == "string") and (.count | type == "number")' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "numéricos negativos y decimales sin comillas; mezcla con letras queda string" {
  run bash "$SCRIPT" metric.sample delta=-5 ratio=0.75 build=12abc
  [ "$status" -eq 0 ]
  run jq -e '.delta == -5 and .ratio == 0.75 and (.build == "12abc")' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "comillas dobles y barras invertidas en el valor producen JSON válido y round-trip exacto" {
  run bash "$SCRIPT" dispatch.failed error='say "hi" C:\dir'
  [ "$status" -eq 0 ]
  run jq -e '.error == "say \"hi\" C:\\dir"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "session_id se trunca a 8 caracteres desde CLAUDE_SESSION_ID" {
  CLAUDE_SESSION_ID="abcdef0123456789" run bash "$SCRIPT" agent.started agent_name=x
  [ "$status" -eq 0 ]
  run jq -e '.session_id == "abcdef01"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "sin sesión no se emite session_id" {
  env -u CLAUDE_SESSION_ID -u OPENCODE_SESSION_ID bash "$SCRIPT" agent.started agent_name=x
  run jq -e 'has("session_id") | not' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "ruta absoluta bajo /home de cualquier usuario no deja el usuario en el valor" {
  run bash "$SCRIPT" tool.executed target="/home/otra.persona-1/proyecto/x.sh"
  [ "$status" -eq 0 ]
  # El glob de redacción es voraz: puede recortar también subdirectorios (sobre-redacta,
  # nunca filtra). Lo que se garantiza es que el usuario no aparece.
  run jq -e '(.target | startswith("{project}/")) and (.target | contains("otra.persona") | not) and (.target | endswith("x.sh"))' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "REDACT=1 no incluye trace_id ni span_id ni atributos" {
  SAVIA_TELEMETRY_REDACT=1 run bash "$SCRIPT" agent.completed agent_name=x
  [ "$status" -eq 0 ]
  run jq -e 'keys == ["event","schema","ts"]' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "write failure to an unwritable destination never blocks the flow (exit 0)" {
  export SAVIA_TELEMETRY_FILE="/proc/no-existe/telemetry.jsonl"
  run bash "$SCRIPT" agent.started agent_name=x
  [ "$status" -eq 0 ]
}

@test "invalid operation.* contract exits 2, warns and writes nothing" {
  run bash "$SCRIPT" operation.started operation_id=zzz flow_id=flow:read
  [ "$status" -eq 2 ]
  [[ "$output" == *"INVALID_OPERATION_EVENT"* ]]
  [[ ! -s "$SAVIA_TELEMETRY_FILE" ]]
}

@test "evento operation.started válido pasa el contrato y se escribe" {
  run op_started
  [ "$status" -eq 0 ]
  run jq -e '.event == "operation.started" and .sequence == 0 and .flow_id == "flow:read"' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "operation.started rejected when flow_id is not a golden flow" {
  run op_started flow:inventado
  [ "$status" -eq 2 ]
  [[ ! -s "$SAVIA_TELEMETRY_FILE" ]]
}

@test "SAVIA_FINGERPRINT=1 adjunta fingerprint con hash de 16 hex" {
  SAVIA_FINGERPRINT=1 run bash "$SCRIPT" dispatch.failed agent_name=x error="timeout after 30 seconds"
  [ "$status" -eq 0 ]
  run jq -e '.fingerprint.hash | test("^[0-9a-f]{16}$")' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "sin SAVIA_FINGERPRINT no hay campo fingerprint" {
  run bash "$SCRIPT" dispatch.failed agent_name=x error="timeout"
  [ "$status" -eq 0 ]
  run jq -e 'has("fingerprint") | not' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}

@test "empty value (key=) is emitted as empty string, not dropped nor numeric" {
  run bash "$SCRIPT" tool.executed note=
  [ "$status" -eq 0 ]
  run jq -e 'has("note") and .note == ""' "$SAVIA_TELEMETRY_FILE"
  [ "$status" -eq 0 ]
}
