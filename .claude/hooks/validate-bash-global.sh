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
  # Sin comillas ni barras: `gi''t co\mmit` es git commit para bash.
  COMMAND_LOWER_PLAIN=$(printf '%s' "$COMMAND_LOWER" | tr -d "\"'\\\\")
  RELEVANCE_ERE='(^|[^a-z0-9_])(git|rm|chmod|curl|gh|sudo|commit)([^a-z0-9_]|$)'
  # The legacy grep rules are intentionally not rewritten in F5A. Keep their
  # historical embedded-word matches on the full path as a conservative guard.
  LEGACY_RULE_ERE='git[[:space:]]+(commit|add)|rm[[:space:]]+-rf[[:space:]]+/|chmod[[:space:]]+777|curl[[:space:]]+.*\|[[:space:]]*(ba)?sh|gh[[:space:]]+pr[[:space:]]+review.*--approve|gh[[:space:]]+pr[[:space:]]+merge.*--admin|^[[:space:]]*sudo[[:space:]]'
  if ! [[ "$COMMAND_LOWER" =~ $RELEVANCE_ERE ]] \
    && ! [[ "$COMMAND_LOWER_PLAIN" =~ $RELEVANCE_ERE ]] \
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
  # SE-453 S2: sin jq degrada a grep; si no puede evaluar, sale 2.
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
  hook_extract_command "$INPUT" || exit 2
  COMMAND="$HOOK_COMMAND"
fi

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Bloquear git commit/add en main SOLO para savia/pm-workspace
# Sale con 2 si el repo savia/pm-workspace de $1 está en main/master.
guard_main_target() {
  local dir="$1" top name branch
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  name=$(basename "$top")
  [[ "$name" == "savia" || "$name" == "pm-workspace" ]] || return 0
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "BLOQUEADO: rama '$branch' en $dir. Cambia a feature branch." >&2
    exit 2
  fi
}
# Prefiltro amplio sobre el texto sin comillas ni barras (como el resolvedor y
# el guard TS: `gi''t co\mmit` también cuenta). `git` solo basta (un alias
# puede hacer commit) y `commit` solo también (`$x commit` con x=git). Qué es
# una orden real lo decide el resolvedor.
_PLAIN=$(printf '%s' "$COMMAND" | tr -d "\"'\\\\")
_HAS_GIT=""; _HAS_OP=""
echo "$_PLAIN" | grep -iqE '(^|[^[:alnum:]_])git([^[:alnum:]_]|$)' && _HAS_GIT=1
echo "$_PLAIN" | grep -iqE '(^|[^[:alnum:]_-])(commit(-tree)?|add)([^[:alnum:]_-]|$)' && _HAS_OP=1
if [[ -n "$_HAS_GIT" ]] || echo "$_PLAIN" | grep -iqE '(^|[^[:alnum:]_-])commit(-tree)?([^[:alnum:]_-]|$)'; then
  GIT_DIR_TARGET="${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$PWD}}"
  if git -C "$ENTRY_PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # SE-383 P8 (worktree-aware): el cwd de entrada manda sobre el proyecto.
    GIT_DIR_TARGET="$ENTRY_PWD"
  fi
  # El repo que importa es el DESTINO de cada `git commit|add` real (git -C,
  # cd encadenado con o sin comillas y con ~, variables literales); heredocs
  # y cadenas son texto. Destino no resoluble → GIT_DIR_TARGET (conservador).
  # Sin Python, sin resolvedor o si falla: BLOQUEAR lo que dice git y commit|add.
  RESOLVER="$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/git_op_targets.py"
  # `timeout` no viene de serie en macOS: sin él, el resolvedor corre sin límite.
  _TIMEOUT=(); command -v timeout >/dev/null 2>&1 && _TIMEOUT=(timeout 5)
  if command -v python3 >/dev/null 2>&1 \
     && OP_TARGETS=$(printf '%s' "$COMMAND" | "${_TIMEOUT[@]}" python3 "$RESOLVER" "$GIT_DIR_TARGET" 2>/dev/null); then
    while IFS=$'\t' read -r _op _dir; do
      [[ -n "$_op" ]] || continue
      if [[ -z "$_dir" ]]; then
        echo "BLOQUEADO: destino de git $_op no reconocido con certeza (fail-closed). Forma admitida: git -C <ruta> $_op …" >&2
        exit 2
      fi
      if git -C "$_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        guard_main_target "$_dir"
      else
        guard_main_target "$GIT_DIR_TARGET"
      fi
    done <<< "$OP_TARGETS"
  elif [[ -n "$_HAS_GIT" && -n "$_HAS_OP" ]]; then
    # Sin Python, timeout o fallo del resolvedor: fail-closed (solo lo que dice
    # git y commit|add; el prefiltro amplio dejaría sin servicio `git status`).
    echo "BLOQUEADO: resolvedor de destino no disponible para git commit/add (fail-closed). Forma admitida: git -C <ruta> commit …" >&2
    exit 2
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
# Al inicio de cualquier orden: tras separador o subshell, y con prefijos (VAR=valor, env…).
if echo "$COMMAND" | grep -iE '(^|[;&|(`]|\$\()[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|env|command|nohup|time|exec)[[:space:]]+)*sudo([[:space:]]|$)' > /dev/null; then
  echo "BLOQUEADO: sudo no permitido desde agentes. Solicita elevación al PM." >&2
  exit 2
fi

exit 0
