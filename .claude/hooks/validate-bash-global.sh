#!/bin/bash
set -uo pipefail
ENTRY_PWD="$PWD"  # SE-383 P8: cwd de entrada, capturado antes de que las libs puedan cambiarlo
# validate-bash-global.sh — Validación global de comandos Bash peligrosos
# Usado por: settings.json (PreToolUse hook para toda la sesión)
# Profile tier: standard
# hook-audit-detector: HOOK-03,HOOK-06
# (contiene regex de detección para `curl | bash` y `sudo`; SE-060 skip intencional)

# Read stdin JSON robustly — consume all available data with timeout
# Claude Code sends tool input as JSON on stdin to PreToolUse hooks.
# Uses timeout+cat instead of read -t (which requires trailing newline).
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# SE-397 F5A: parse before environment/profile setup. Only an unambiguous,
# non-empty string outside the closed lexical trigger set may use the fast exit.
COMMAND=""
STRING_COMMAND=0
if [[ -n "$INPUT" ]]; then
  PARSED=$(printf '%s' "$INPUT" | jq -r '
    if ((.tool_input.command? // null) | type) == "string" then
      "STRING\n" + .tool_input.command
    else
      "NON_STRING"
    end
  ' 2>/dev/null) || PARSED=""
  if [[ "$PARSED" == "STRING" ]]; then
    STRING_COMMAND=1
  elif [[ "$PARSED" == STRING$'\n'* ]]; then
    STRING_COMMAND=1
    COMMAND="${PARSED#*$'\n'}"
  fi
fi

if [[ "$STRING_COMMAND" -eq 1 && -n "$COMMAND" ]]; then
  COMMAND_LOWER="${COMMAND,,}"
  RELEVANCE_ERE='(^|[^a-z0-9_])(git|rm|chmod|curl|gh|sudo)([^a-z0-9_]|$)'
  # The legacy grep rules are intentionally not rewritten in F5A. Keep their
  # historical embedded-word matches on the full path as a conservative guard.
  LEGACY_RULE_ERE='git[[:space:]]+(commit|add)|rm[[:space:]]+-rf[[:space:]]+/|chmod[[:space:]]+777|curl[[:space:]]+.*\|[[:space:]]*(ba)?sh|gh[[:space:]]+pr[[:space:]]+review.*--approve|gh[[:space:]]+pr[[:space:]]+merge.*--admin|^[[:space:]]*sudo[[:space:]]'
  if ! [[ "$COMMAND_LOWER" =~ $RELEVANCE_ERE ]] \
    && ! [[ "$COMMAND_LOWER" =~ $LEGACY_RULE_ERE ]]; then
    exit 0
  fi
fi

source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# Preserve the legacy jq behavior for malformed, missing and non-string input.
if [[ "$STRING_COMMAND" -eq 0 && -n "$INPUT" ]]; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""
fi

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Bloquear git commit/add en main SOLO para savia/pm-workspace
if echo "$COMMAND" | grep -iE 'git[[:space:]]+(commit|add)' > /dev/null; then
  GIT_DIR_TARGET="${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$PWD}}"
  CD_PATH=$(echo "$COMMAND" | sed -n 's/^[[:space:]]*cd[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null)
  if [[ -n "$CD_PATH" ]] && [[ -e "$CD_PATH/.git" ]]; then  # -e: in a worktree .git is a file
    GIT_DIR_TARGET="$CD_PATH"
  elif git -C "$ENTRY_PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # SE-383 P8 (worktree-aware): si el cwd del comando pertenece a otro
    # worktree/repositorio, la rama relevante es la del cwd de entrada.
    # Comportamiento original preservado cuando cwd == CLAUDE_PROJECT_DIR.
    GIT_DIR_TARGET="$ENTRY_PWD"
  fi
  REPO_TOP=$(cd "$GIT_DIR_TARGET" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
  REPO_NAME=$(basename "$REPO_TOP" 2>/dev/null)
  if [[ "$REPO_NAME" == "savia" || "$REPO_NAME" == "pm-workspace" ]]; then
    CURRENT_BRANCH=$(cd "$GIT_DIR_TARGET" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
      echo "BLOQUEADO: rama '$CURRENT_BRANCH' en $GIT_DIR_TARGET. Cambia a feature branch." >&2
      exit 2
    fi
  fi
fi

# Bloquear rm -rf / (root)
if echo "$COMMAND" | grep -iE 'rm[[:space:]]+-rf[[:space:]]+/' > /dev/null; then
  echo "BLOQUEADO: rm -rf con ruta root. Operación potencialmente destructiva." >&2
  exit 2
fi

# Bloquear chmod 777
if echo "$COMMAND" | grep -iE 'chmod[[:space:]]+777' > /dev/null; then
  echo "BLOQUEADO: chmod 777 es inseguro. Usa permisos más restrictivos." >&2
  exit 2
fi

# Bloquear curl | bash (ejecución remota ciega)
if echo "$COMMAND" | grep -iE 'curl[[:space:]]+.*\|\s*(ba)?sh' > /dev/null; then
  echo "BLOQUEADO: curl | bash es inseguro. Descarga primero, revisa, luego ejecuta." >&2
  exit 2
fi

# Bloquear auto-aprobación de PRs (GitHub no lo permite y es mala práctica)
if echo "$COMMAND" | grep -iE 'gh[[:space:]]+pr[[:space:]]+review.*--approve' > /dev/null; then
  echo "BLOQUEADO: No puedes aprobar tu propio PR. Asigna un reviewer o usa branch protection." >&2
  exit 2
fi

# Bloquear merge directo sin revisión (bypass de branch protection)
if echo "$COMMAND" | grep -iE 'gh[[:space:]]+pr[[:space:]]+merge.*--admin' > /dev/null; then
  echo "BLOQUEADO: --admin bypass de protección de rama. Requiere revisión humana." >&2
  exit 2
fi

# Bloquear sudo sin excepción explícita
# FIX: \s not POSIX ERE. Use [[:space:]] instead.
if echo "$COMMAND" | grep -iE '^[[:space:]]*sudo[[:space:]]' > /dev/null; then
  echo "BLOQUEADO: sudo no permitido desde agentes. Solicita elevación al PM." >&2
  exit 2
fi

exit 0
