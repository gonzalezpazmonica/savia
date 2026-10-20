#!/bin/bash
set -uo pipefail
# repeat-tool-guard.sh — SE-326 S1 PostToolUse hook
#
# Detecta llamadas de tool repetidas idénticas (tool + args canonicalizados)
# y emite recordatorio escalonado a stderr.
#
# Dos modos segun hook_event_name del payload:
#   PostToolUse (SE-326)  recordatorios; NUNCA bloquea; OFF salvo SAVIA_LOOP_GUARD=1.
#   PreToolUse  (SE-445)  BLOQUEA la 3a llamada identica (exit 2) solo en modos autonomos:
#                         rama agent/* de CLAUDE_PROJECT_DIR o SAVIA_AUTONOMOUS_RUN=1.
#                         Fuera de modos autonomos no hace nada. SAVIA_LOOP_BLOCK=off lo apaga;
#                         SAVIA_LOOP_EXCLUDE exime herramientas; SAVIA_LOOP_WINDOW_SECONDS (600).
#                         Sin stdout (OpenCode trata stdout no JSON como bloqueo).
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
# Exit: 0 salvo el bloqueo PreToolUse en modo autonomo (2)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
GUARD="$PROJECT_DIR/scripts/repeat-tool-guard.py"
[[ -f "$GUARD" ]] || exit 0

INPUT=""
if ! INPUT=$(timeout 3 cat 2>/dev/null); then
  exit 0
fi
[[ -z "$INPUT" ]] && exit 0

EVENT=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('hook_event_name', ''))
except Exception:
    print('')
" 2>/dev/null || true)

if [[ "$EVENT" == "PreToolUse" ]]; then
  [[ "${SAVIA_LOOP_BLOCK:-on}" == "off" ]] && exit 0
  AUTONOMOUS=0
  [[ "${SAVIA_AUTONOMOUS_RUN:-}" == "1" ]] && AUTONOMOUS=1
  if [[ $AUTONOMOUS -eq 0 ]]; then
    BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
    [[ "$BRANCH" == agent/* ]] && AUTONOMOUS=1
  fi
  [[ $AUTONOMOUS -eq 1 ]] || exit 0
  PRE=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('session_id') or '')
    print(d.get('agent_id') or '')
    print(d.get('tool_name', d.get('name', '')))
    print(json.dumps(d.get('tool_input', d.get('input', {}))))
except Exception:
    pass
" 2>/dev/null) || exit 0
  { IFS= read -r P_SESSION; IFS= read -r P_AGENT; IFS= read -r P_TOOL; IFS= read -r P_ARGS; } <<<"$PRE"
  [[ -z "$P_TOOL" ]] && exit 0
  ARGS=(--mode pre --session "${P_SESSION:-${CLAUDE_SESSION_ID:-default}}" --tool "$P_TOOL" --args "${P_ARGS:-{\}}"
        --state-dir "$PROJECT_DIR/output/loop-guard")
  [[ -n "$P_AGENT" ]] && ARGS+=(--agent "$P_AGENT")
  [[ -n "${SAVIA_LOOP_EXCLUDE:-}" ]] && ARGS+=(--exclude "$SAVIA_LOOP_EXCLUDE")
  [[ -n "${SAVIA_LOOP_WINDOW_SECONDS:-}" ]] && ARGS+=(--window "$SAVIA_LOOP_WINDOW_SECONDS")
  python3 "$GUARD" "${ARGS[@]}" >&2
  RC=$?
  [[ $RC -eq 2 ]] && exit 2
  exit 0
fi

# Modo post (SE-326): OFF por defecto — solo con SAVIA_LOOP_GUARD=1; nunca bloquea.
[[ "${SAVIA_LOOP_GUARD:-}" == "1" ]] || exit 0
[[ "$EVENT" == "PostToolUse" || -z "$EVENT" ]] || exit 0

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
