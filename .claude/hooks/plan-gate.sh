#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# plan-gate.sh — Warning si implementación sin spec aprobada
# ─────────────────────────────────────────────────────────────
# PreToolUse hook (Edit|Write) que advierte si se edita código sin spec
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# Timeout: 30 seconds max for entire spec search operation
TIMEOUT=30

# Solo verificar en ficheros de código fuente
# La ruta llega en tool_input.file_path por stdin; CLAUDE_TOOL_INPUT_FILE no lo define ningún runtime.
FILE="${CLAUDE_TOOL_INPUT_FILE:-}"
if [[ -z "$FILE" && ! -t 0 ]]; then
  FILE=$(timeout 3 cat 2>/dev/null | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
fi
[[ -z "$FILE" ]] && exit 0

case "$FILE" in
    *.cs|*.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.php|*.rb|*.java|*.kt|*.swift|*.dart|*.vb|*.cbl) ;;
    *) exit 0 ;;
esac

# Buscar spec activa en el proyecto
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
SPECS_DIR="$PROJECT_DIR/projects"

# Si no hay directorio de proyectos, skip
[[ ! -d "$SPECS_DIR" ]] && exit 0

# Buscar specs recientes (último sprint = últimos 14 días) with timeout
RECENT_SPECS=$(timeout $TIMEOUT find "$SPECS_DIR" -name "*.spec.md" -mtime -14 2>/dev/null | head -5)

if [[ -z "$RECENT_SPECS" ]]; then
    echo "" >&2
    echo "⚠️  Plan Gate: No se encontró spec aprobada reciente." >&2
    echo "   Considera ejecutar /spec-generate antes de implementar." >&2
    echo "   (Warning — no bloquea la edición)" >&2
    echo "" >&2
fi

exit 0
