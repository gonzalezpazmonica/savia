#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# PostToolUse Hook: agent-trace-log.sh
# Registra la ejecucion de agentes (Task tool) en trazas JSONL
# Includes per-agent token budget metering (SPEC-AGENT-METERING)
# NOTE: no set -e — script manages errors manually

# La entrada llega por stdin (JSON de Claude Code / OpenCode); las variables TOOL_* solo son respaldo.
# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_read_posttool agent-trace-log
TOOL_NAME="$HOOK_TOOL_NAME"
TOOL_INPUT="$HOOK_TOOL_INPUT"
TOOL_RESULT_STATUS="$HOOK_TOOL_STATUS"

# Only trigger for Task tool (subagent invocation)
if [[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "Agent" ]]; then
    exit 0
fi

# Extraer variables de entorno y TOOL_INPUT
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
# SE-313 S1: destino real = output/agent-traces.jsonl (no projects/{proj}/traces,
# directorio que nunca se creaba — inventario SE-313 G9).
TRACES_DIR="$PROJECT_DIR/output"

# Crear directorio si no existe
mkdir -p "$TRACES_DIR" 2>/dev/null || true

# Extraer datos de TOOL_INPUT (JSON)
AGENT_NAME=$(echo "$TOOL_INPUT" | grep -o '"agent":\s*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
# SE-313 S3: fallback a subagent_type/agent del hook input cuando el runtime no
# puebla el campo agent (corrige lifecycle "agent: unknown").
if [[ "$AGENT_NAME" == "unknown" ]]; then
    AGENT_NAME=$(printf '%s' "${TOOL_INPUT:-}" | grep -o '"subagent_type":\s*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
fi
[[ "$AGENT_NAME" == "unknown" ]] && AGENT_NAME=$(printf '%s' "${TOOL_INPUT:-}" | grep -o '"agent_type":\s*"[^"]*"' | cut -d'"' -f4 || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Estimar tokens (aproximado basado en longitud)
INPUT_LENGTH=${#TOOL_INPUT}
_TOOL_OUTPUT="$HOOK_TOOL_OUTPUT"
OUTPUT_LENGTH=${#_TOOL_OUTPUT}
TOKENS_IN=$((INPUT_LENGTH / 4))
TOKENS_OUT=$((OUTPUT_LENGTH / 4))

# Calcular duracion (en segundos, convertir a ms)
DURATION_MS="${HOOK_TOOL_DURATION_MS%%.*}"
[[ "$DURATION_MS" =~ ^[0-9]+$ ]] || DURATION_MS=0
DURATION_S=$((DURATION_MS / 1000))

# Determinar outcome
OUTCOME="success"
if [[ "$TOOL_RESULT_STATUS" == "error" ]] || [[ $DURATION_S -gt 120 ]]; then
    OUTCOME="failure"
elif [[ "$TOOL_RESULT_STATUS" == "partial" ]]; then
    OUTCOME="partial"
fi

# Budget metering (SPEC-AGENT-METERING)
# Use CLAUDE_PROJECT_DIR for lookup (test isolation), fallback to script location
LOOKUP_BASE="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOOKUP_SCRIPT="$LOOKUP_BASE/scripts/agent-budget-lookup.sh"
if [[ -f "$LOOKUP_SCRIPT" ]]; then
    TOKEN_BUDGET=$(bash "$LOOKUP_SCRIPT" "$AGENT_NAME" 2>/dev/null || echo "0")
else
    TOKEN_BUDGET="0"
fi
TOKEN_BUDGET=${TOKEN_BUDGET:-0}

TOTAL_TOKENS=$((TOKENS_IN + TOKENS_OUT))
BUDGET_EXCEEDED="false"
if [[ "$TOKEN_BUDGET" -gt 0 ]] && [[ "$TOTAL_TOKENS" -gt "$TOKEN_BUDGET" ]]; then
    BUDGET_EXCEEDED="true"
fi

# Construir linea JSONL
TRACE_LINE="{\"timestamp\":\"$TIMESTAMP\",\"agent\":\"$AGENT_NAME\",\"command\":\"task\",\"tokens_in\":$TOKENS_IN,\"tokens_out\":$TOKENS_OUT,\"token_budget\":$TOKEN_BUDGET,\"budget_exceeded\":$BUDGET_EXCEEDED,\"duration_ms\":$DURATION_MS,\"files_modified\":[],\"outcome\":\"$OUTCOME\",\"scope_violations\":[]}"

# Appendear a fichero de trazas (async, silent)
echo "$TRACE_LINE" >> "$TRACES_DIR/agent-traces.jsonl" 2>/dev/null || true

# SE-313 S1/S3: emitir evento estándar savia.event/1.0 al telemetry-events.jsonl
# (mismo schema que la capa OpenCode). Nunca bloquea (|| true).
EMIT="$PROJECT_DIR/scripts/otel-emit.sh"
if [[ -x "$EMIT" ]]; then
    MODEL="$(savia_resolve_model mid 2>/dev/null || echo "mid")"
    EVENT_NAME="agent.completed"
    OUTCOME="$OUTCOME"
    "$EMIT" "$EVENT_NAME" agent_name="$AGENT_NAME" kind=invoke_agent status="$OUTCOME" \
      gen_ai_request_model="$MODEL" duration_ms="$DURATION_MS" outcome="$OUTCOME" \
      retention_days=180 >/dev/null 2>&1 || true
fi

# Budget alert (only when exceeded and budget > 0)
if [[ "$BUDGET_EXCEEDED" == "true" ]]; then
    OVERAGE=$((TOTAL_TOKENS - TOKEN_BUDGET))
    OVERAGE_PCT=$(( (OVERAGE * 100) / TOKEN_BUDGET ))
    ALERT_LINE="{\"timestamp\":\"$TIMESTAMP\",\"agent\":\"$AGENT_NAME\",\"tokens_in\":$TOKENS_IN,\"tokens_out\":$TOKENS_OUT,\"token_budget\":$TOKEN_BUDGET,\"total\":$TOTAL_TOKENS,\"overage\":$OVERAGE,\"overage_pct\":$OVERAGE_PCT}"
    echo "$ALERT_LINE" >> "$TRACES_DIR/budget-alerts.jsonl" 2>/dev/null || true
fi

exit 0
