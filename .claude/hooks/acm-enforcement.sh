#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# acm-enforcement.sh — SE-063 Slice 1 PreToolUse hook
#
# Bloquea Glob/Grep amplios dentro de projects/ si el agente no ha leido
# el INDEX.acm del proyecto en el turno actual.
#
# Input: JSON con tool_input.{pattern,path,glob,type} via stdin
# Exit codes:
#   0 — permitido (query acotada, exento, o ACM ya consultado)
#   2 — bloqueado (query amplia + ACM no consultado + existe INDEX.acm)
#
# Bypass:
#   SAVIA_ACM_ENFORCE=0      → hook desactivado globalmente
#   SAVIA_ACM_ENFORCE=warn   → emite a stderr pero no bloquea (default inicial)
#   SAVIA_ACM_ENFORCE=block  → modo enforcement (default tras Slice 2 marker)
#
# Slice 3 — bypass semántico:
#   SAVIA_ACM_LOG_LEVEL=silent → no log, no stderr (solo exit code)
#   SAVIA_ACM_LOG_LEVEL=warn   → log + stderr en warn/block (default)
#   SAVIA_ACM_LOG_LEVEL=debug  → log verbose con pattern, path, turn, marker dir
#   projects/{p}/.agent-maps/.acm-enforce-skip → opt-out per-project (fichero vacio)
#
# Ref: docs/propuestas/SE-063-acm-enforcement-pretool-hook.md
# Related: .opencode/hooks/acm-turn-marker.sh (PostToolUse marker writer)

# set -e omitted intentionally: fail-open on parsing errors to avoid blocking legitimate tools.

# Profile gate
LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# Global disable
ENFORCE_MODE="${SAVIA_ACM_ENFORCE:-warn}"
if [[ "$ENFORCE_MODE" == "0" || "$ENFORCE_MODE" == "off" ]]; then
  exit 0
fi

# Log verbosity (Slice 3)
LOG_LEVEL="${SAVIA_ACM_LOG_LEVEL:-warn}"

# Require jq for JSON parsing
if ! command -v jq &>/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit acm-enforcement
fi

# Read stdin with timeout
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi
[[ -z "$INPUT" ]] && exit 0

# Parse tool and input
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ -z "$TOOL_NAME" ]] && exit 0

# Only act on Glob/Grep
if [[ "$TOOL_NAME" != "Glob" && "$TOOL_NAME" != "Grep" ]]; then
  exit 0
fi

PATTERN=$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)
PATH_ARG=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
GLOB_ARG=$(printf '%s' "$INPUT" | jq -r '.tool_input.glob // empty' 2>/dev/null)
TYPE_ARG=$(printf '%s' "$INPUT" | jq -r '.tool_input.type // empty' 2>/dev/null)

# Detect "wide" query
is_wide=no
case "$PATTERN" in
  '**/*'|'**'|'*'|'.*'|'.'|'') is_wide=yes ;;
esac
# Grep without any filter (no path, no type, no glob) → wide
if [[ "$TOOL_NAME" == "Grep" && -z "$PATH_ARG" && -z "$TYPE_ARG" && -z "$GLOB_ARG" ]]; then
  is_wide=yes
fi
# Glob without path = wide
if [[ "$TOOL_NAME" == "Glob" && -z "$PATH_ARG" ]]; then
  is_wide=yes
fi

if [[ "$is_wide" == "no" ]]; then
  exit 0
fi

# Only care about queries targeting a project (not workspace infra)
PROJECT_NAME=""
case "$PATH_ARG" in
  projects/*)
    PROJECT_NAME=$(printf '%s' "$PATH_ARG" | awk -F/ '{print $2}')
    ;;
  .claude*|docs*|scripts*|tests*|output*|hooks*|.github*)
    exit 0
    ;;
  "")
    # No path means workspace-wide — skip (too many false positives)
    exit 0
    ;;
esac

[[ -z "$PROJECT_NAME" ]] && exit 0

# Check that the project has an INDEX.acm
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/projects/$PROJECT_NAME"
ACM_INDEX="$PROJECT_DIR/.agent-maps/INDEX.acm"
if [[ ! -f "$ACM_INDEX" ]]; then
  # Project has no ACM — nothing to enforce
  exit 0
fi

# Slice 3 — per-project opt-out
if [[ -f "$PROJECT_DIR/.agent-maps/.acm-enforce-skip" ]]; then
  exit 0
fi

# Check turn marker (Slice 2 creates it via PostToolUse acm-turn-marker.sh)
TURN_ID="${CLAUDE_TURN_ID:-${CLAUDE_SESSION_ID:-default}}"
MARKER_DIR="${TMPDIR:-/tmp}/savia-turn-${TURN_ID}"
MARKER="$MARKER_DIR/acm-read-${PROJECT_NAME}"

if [[ -f "$MARKER" ]]; then
  # ACM already consulted this turn
  exit 0
fi

# Log the detection (skip if silent)
if [[ "$LOG_LEVEL" != "silent" ]]; then
  LOG_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/output"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  LOG="$LOG_DIR/acm-enforcement.log"
  if [[ "$LOG_LEVEL" == "debug" ]]; then
    {
      printf '[%s] mode=%s level=debug tool=%s project=%s pattern=%q path=%q turn=%s marker_dir=%q\n' \
        "$(date -Iseconds)" "$ENFORCE_MODE" "$TOOL_NAME" "$PROJECT_NAME" "$PATTERN" "$PATH_ARG" "$TURN_ID" "$MARKER_DIR"
    } >> "$LOG" 2>/dev/null || true
  else
    {
      printf '[%s] mode=%s tool=%s project=%s pattern=%q path=%q\n' \
        "$(date -Iseconds)" "$ENFORCE_MODE" "$TOOL_NAME" "$PROJECT_NAME" "$PATTERN" "$PATH_ARG"
    } >> "$LOG" 2>/dev/null || true
  fi
fi

# Emit guidance
MSG="ACM enforcement: query amplia en projects/$PROJECT_NAME sin consultar .agent-maps/INDEX.acm.
Lee primero: projects/$PROJECT_NAME/.agent-maps/INDEX.acm
Opt-out proyecto: touch projects/$PROJECT_NAME/.agent-maps/.acm-enforce-skip
Bypass puntual: SAVIA_ACM_ENFORCE=0 (no recomendado).
Ref: SE-063."

if [[ "$ENFORCE_MODE" == "block" ]]; then
  [[ "$LOG_LEVEL" != "silent" ]] && printf '%s\n' "$MSG" >&2
  exit 2
fi

# Default: warn only
[[ "$LOG_LEVEL" != "silent" ]] && printf 'WARN: %s\n' "$MSG" >&2
exit 0
