#!/bin/bash
set -uo pipefail
# acm-turn-marker.sh — SE-063 Slice 2 PostToolUse hook
#
# Crea marker per-turn cuando el agente lee un fichero .acm o INDEX.acm,
# indicando que ha consultado el ACM del proyecto.
#
# Consumidor: .opencode/hooks/acm-enforcement.sh (PreToolUse)
#
# Input: JSON con tool_name=Read + tool_input.file_path via stdin
# Exit: siempre 0 (no-op si no aplica)
#
# Ref: docs/propuestas/SE-063-acm-enforcement-pretool-hook.md

# Profile gate
LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

if ! command -v jq &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit acm-turn-marker
fi

INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "Read" ]] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Only trigger on .acm files or .agent-maps paths inside projects/
case "$FILE_PATH" in
  */projects/*/.agent-maps/*)
    # Extract project name
    PROJECT_NAME=$(printf '%s' "$FILE_PATH" | sed -nE 's|.*/projects/([^/]+)/\.agent-maps/.*|\1|p')
    ;;
  *)
    exit 0
    ;;
esac

[[ -z "$PROJECT_NAME" ]] && exit 0

TURN_ID="${CLAUDE_TURN_ID:-${CLAUDE_SESSION_ID:-default}}"
MARKER_DIR="${TMPDIR:-/tmp}/savia-turn-${TURN_ID}"
mkdir -p "$MARKER_DIR" 2>/dev/null || exit 0

MARKER="$MARKER_DIR/acm-read-${PROJECT_NAME}"
: > "$MARKER" 2>/dev/null || exit 0

exit 0
