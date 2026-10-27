#!/usr/bin/env bash
set -uo pipefail
# android-adb-validate.sh — PreToolUse hook for ADB command safety
# Classifies ADB commands: safe → risky → blocked
# Hook protocol: exit 0 = allow, exit 2 = block
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# La orden llega por stdin (tool_input.command); TOOL_INPUT no lo define ningún runtime y leerla
# sola dejaba el guard inerte. Se conserva como respaldo.
TOOL_INPUT="${TOOL_INPUT:-}"
if [[ -z "$TOOL_INPUT" && ! -t 0 ]]; then
  _raw=$(timeout 3 cat 2>/dev/null || true)
  # shellcheck source=/dev/null
  source "$LIB_DIR/hook-input.sh"
  hook_extract_command "$_raw" || exit 2   # JSON malformado → bloqueo (fallo cerrado)
  TOOL_INPUT="$HOOK_COMMAND"
fi
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/android-adb.log"

mkdir -p "$LOG_DIR"

# Se compara la orden normalizada: sin comillas ni barras de escape y con espacios (tabuladores
# incluidos) colapsados, para que `"adb" shell 'rm -rf x'`, `a\db shell …` o `adb<TAB>shell …` no
# eludan ni el prefiltro ni los patrones. El prefiltro va DESPUÉS de normalizar.
ADB_CMD=$(tr -d "\"'\\\\" <<<"$TOOL_INPUT" | tr -s '[:space:]' ' ')

# Only process ADB commands
if ! grep -qE '(^|[^[:alnum:]_])adb( |_)' <<<"$ADB_CMD"; then
    exit 0
fi

# ─── Blocked operations (never allow) ──────────────────────────────────────
# rm recursivo con cualquier combinación y posición de opciones (-rf, -fr, -R -f, --recursive, o tras la ruta).
BLOCKED_PATTERNS=(
    "adb.*shell.*\\brm\\b.*\\s(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\\b"
    "adb.*shell format"
    "adb.*shell dd if="
    "adb.*shell su "
    "adb.*root"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if grep -qP "$pattern" <<<"$ADB_CMD"; then
        echo "BLOCKED: Destructive ADB operation: $ADB_CMD" >> "$LOG_FILE"
        echo "ADB operation blocked for safety: $pattern" >&2
        exit 2
    fi
done

# ─── Risky operations (allow + log) ────────────────────────────────────────
RISKY_PATTERNS=(
    "adb.*install "
    "adb.*uninstall "
    "adb.*shell pm clear"
    "adb.*push "
    "adb.*shell am force-stop"
    "adb.*shell monkey"
    "adb.*reboot"
    "adb_install"
    "adb_uninstall"
    "adb_clear_data"
)

for pattern in "${RISKY_PATTERNS[@]}"; do
    if grep -qP "$pattern" <<<"$ADB_CMD"; then
        echo "$(date -Iseconds) | RISKY | $ADB_CMD" >> "$LOG_FILE"
        exit 0
    fi
done

# ─── Safe operations (allow silently) ──────────────────────────────────────
echo "$(date -Iseconds) | SAFE | $ADB_CMD" >> "$LOG_FILE"
exit 0
