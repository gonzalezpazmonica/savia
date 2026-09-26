#!/bin/bash
set -uo pipefail
# repeat-tool-guard.sh — SE-326 S1 PostToolUse hook
#
# Detecta llamadas de tool repetidas idénticas (tool + args canonicalizados)
# y emite recordatorio escalonado a stderr. NUNCA bloquea (exit 0 siempre).
#
# Inspirado en deepseek-harness packages/guard/repeat-tool-reminder (SE-326).
# Consumidor: scripts/repeat-tool-guard.py
#
# Config (env):
#   SAVIA_LOOP_GUARD=1        activar el guard (default: OFF — no molesta)
#   SAVIA_LOOP_THRESHOLDS=3,5,8
#   SAVIA_LOOP_EXCLUDE=todo_write,todowrite
#   SAVIA_LOOP_PREVIEW=500
#   SAVIA_LOOP_PERSIST=1      persistir estado a output/loop-guard/ (diagnostico)
#
# Input: JSON con tool_name/tool_input via stdin
# Exit: siempre 0
# El guard está OFF por defecto — solo se activa con SAVIA_LOOP_GUARD=1
[[ "${SAVIA_LOOP_GUARD:-}" == "1" ]] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
GUARD="$PROJECT_DIR/scripts/repeat-tool-guard.py"
[[ -f "$GUARD" ]] || exit 0

INPUT=""
if ! INPUT=$(timeout 3 cat 2>/dev/null); then
  exit 0
fi
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', d.get('name', '')))
except Exception:
    print('')
" 2>/dev/null || true)
[[ -z "$TOOL_NAME" ]] && exit 0

TOOL_ARGS=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(json.dumps(d.get('tool_input', d.get('input', {}))))
except Exception:
    print('{}')
" 2>/dev/null || echo '{}')

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
TURN_ID="${CLAUDE_TURN_ID:-${CLAUDE_SESSION_ID:-default}}"
EMIT="$PROJECT_DIR/scripts/otel-emit.sh"

ARGS=(--session "$SESSION_ID" --turn "$TURN_ID" --tool "$TOOL_NAME" --args "$TOOL_ARGS")
[[ -n "${SAVIA_LOOP_THRESHOLDS:-}" ]] && ARGS+=(--thresholds "$SAVIA_LOOP_THRESHOLDS")
[[ -n "${SAVIA_LOOP_EXCLUDE:-}" ]] && ARGS+=(--exclude "$SAVIA_LOOP_EXCLUDE")
[[ -n "${SAVIA_LOOP_PREVIEW:-}" ]] && ARGS+=(--preview "$SAVIA_LOOP_PREVIEW")
[[ -x "$EMIT" ]] && ARGS+=(--emit-telemetry "$EMIT")

python3 "$GUARD" "${ARGS[@]}" >&2 || true
exit 0
