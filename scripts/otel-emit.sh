#!/usr/bin/env bash
# otel-emit.sh — SE-313 S1: emisor de eventos de telemetría estándar.
#
# Emite eventos `savia.event/1.0` a output/telemetry-events.jsonl con
# trace_id heredado (SAVIA_TRACEPARENT) o auto-generado (W3C traceparent).
#
# Uso:
#   otel-emit.sh <event> key=value [key=value ...]
#
# Ejemplos:
#   otel-emit.sh agent.started agent_name=drift-auditor tier=heavy
#   otel-emit.sh dispatch.failed agent_name=explore requested_model=deepseek-v4-pro
#     error="Model not found"
#
# Exit codes: 0 success (nunca bloquea), 1 evento vacío (solo validación).
# Nunca sale != 0 por fallo de disco — el telemetry nunca bloquea el flujo.
set -uo pipefail

EVENT_NAME="${1:-}"
[[ -z "$EVENT_NAME" ]] && exit 1
shift

# ── Destino ──────────────────────────────────────────────────────────────────
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUTPUT_FILE="${SAVIA_TELEMETRY_FILE:-$REPO_ROOT/output/telemetry-events.jsonl}"
mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true

# ── Timestamp ISO 8601 UTC ───────────────────────────────────────────────────
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── Trace context (W3C traceparent) ──────────────────────────────────────────
# Heredado de SAVIA_TRACEPARENT si el orquestador lo propagó; si no, genera
# un trace_id + span_id nuevos (versión-00).
TRACEPARENT="${SAVIA_TRACEPARENT:-}"
TRACE_ID=""
SPAN_ID=""
PARENT_SPAN_ID=""

if [[ "$TRACEPARENT" =~ ^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$ ]]; then
  TRACE_ID="${TRACEPARENT:3:32}"
  PARENT_SPAN_ID="${TRACEPARENT:36:16}"
  SPAN_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
else
  TRACE_ID="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  SPAN_ID="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
fi

# ── Sesión ───────────────────────────────────────────────────────────────────
SESSION_ID="$(python3 -c "
import os
s = os.environ.get('CLAUDE_SESSION_ID') or os.environ.get('OPENCODE_SESSION_ID') or ''
print(s[:8])
" 2>/dev/null)"

# ── SE-313 S5: redacción ─────────────────────────────────────────────────────
# SAVIA_TELEMETRY_REDACT=1 → solo {schema, ts, event}. Nunca contiene PII.
# Paths absolutos → {project} (reemplazo aplicado a valores string).
# session_id ya truncado a 8 chars arriba (config/telemetry-policies.yaml).
if [[ "${SAVIA_TELEMETRY_REDACT:-0}" == "1" ]]; then
  printf '{"schema":"savia.event/1.0","ts":"%s","event":"%s"}\n' "$TS" "$EVENT_NAME" >> "$OUTPUT_FILE" 2>/dev/null || true
  exit 0
fi

# ── Construir JSON (evento base + atributos) ────────────────────────────────
JSON="{\"schema\":\"savia.event/1.0\",\"ts\":\"${TS}\",\"event\":\"${EVENT_NAME}\""
[[ -n "$TRACE_ID" ]]  && JSON="${JSON},\"trace_id\":\"${TRACE_ID}\""
[[ -n "$SPAN_ID" ]]   && JSON="${JSON},\"span_id\":\"${SPAN_ID}\""
[[ -n "$PARENT_SPAN_ID" ]] && JSON="${JSON},\"parent_span_id\":\"${PARENT_SPAN_ID}\""
[[ -n "$SESSION_ID" ]] && JSON="${JSON},\"session_id\":\"${SESSION_ID}\""

for pair in "$@"; do
  KEY="${pair%%=*}"
  VAL="${pair#*=}"
  # SE-313 S5: paths absolutos -> {project} (redacción en emisión)
  VAL="${VAL//\/home\/[a-zA-Z0-9_.-]*\//\{project\}\/}"
  # Escape básico de comillas para valores string
  VAL_ESC="${VAL//\\/\\\\}"
  VAL_ESC="${VAL_ESC//\"/\\\"}"
  if [[ "$VAL" == "null" && "$KEY" =~ ^(request_id|evidence_ref)$ ]]; then
    JSON="${JSON},\"${KEY}\":null"
  elif [[ "$KEY" =~ ^(operation_id|request_id|flow_id|model_revision|frontend_id|phase|architecture_node_id|evidence_ref|outcome)$ ]]; then
    JSON="${JSON},\"${KEY}\":\"${VAL_ESC}\""
  elif [[ "$VAL" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    JSON="${JSON},\"${KEY}\":${VAL}"
  else
    JSON="${JSON},\"${KEY}\":\"${VAL_ESC}\""
  fi
done
JSON="${JSON}}"

# ── SE-397 F4: los eventos operacionales son un contrato cerrado ───────────
case "$EVENT_NAME" in
  operation.started|operation.segment|operation.completed)
    if ! printf '%s' "$JSON" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c '
import json, sys
from sam_trace import validate_operation_event
validate_operation_event(json.load(sys.stdin))
' >/dev/null 2>&1; then
      echo "INVALID_OPERATION_EVENT" >&2
      exit 2
    fi
    ;;
esac

# ── Append (async, nunca bloquea) ────────────────────────────────────────────
# SE-334 S1: --fingerprint adjunta huella normalizada para agrupación de issues
if [[ "${SAVIA_FINGERPRINT:-0}" == "1" || "${TEL_FP:-0}" == "1" ]]; then
  if [[ -x "$(dirname "${BASH_SOURCE[0]}")/telemetry-fingerprint.py" ]]; then
    FP_JSON=$(printf '%s' "$JSON" | python3 -c "
import json, sys
from importlib.machinery import SourceFileLoader
fp = SourceFileLoader('f', 'scripts/telemetry-fingerprint.py').load_module()
try:
    ev = json.loads(sys.stdin.read())
    r = fp.fingerprint(ev)
    print(json.dumps({'hash': r['hash'], 'bucket': r['bucket'], 'exception_type': r['exception_type']}))
except Exception:
    print('')
" 2>/dev/null)
    if [[ -n "$FP_JSON" ]]; then
      # el JSON base está cerrado con '}' → lo reabrimos, añadimos y cerramos
      JSON="${JSON%\}},\"fingerprint\":$FP_JSON}"
    fi
  fi
fi
printf '%s\n' "$JSON" >> "$OUTPUT_FILE" 2>/dev/null || true

exit 0
