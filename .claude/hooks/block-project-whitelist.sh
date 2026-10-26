#!/usr/bin/env bash
# block-project-whitelist.sh — Bloquea whitelist de proyectos en .gitignore
# Profile tier: standard
set -uo pipefail
# Capa de defensa adicional al pre-commit hook. Actúa a nivel de Claude Code.

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# Lee el input del hook
# Claude Code y OpenCode pasan la entrada del hook por stdin; CLAUDE_TOOL_INPUT no lo define ningún
# runtime y leerla sola dejaba el hook en fallo abierto (exit 0 siempre). Se conserva como respaldo.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" && ! -t 0 ]]; then INPUT=$(timeout 3 cat 2>/dev/null || true); fi

# Solo nos interesa si se está editando .gitignore
if ! echo "$INPUT" | grep -q "\.gitignore"; then
    exit 0
fi

# Detectar si el contenido incluye un whitelist de proyecto (!projects/)
if echo "$INPUT" | grep -qE '!projects/'; then
    echo "🛑 BLOQUEADO: Intento de añadir whitelist de proyecto en .gitignore" >&2
    echo "" >&2
    echo "La regla de privacidad de proyectos requiere confirmación humana explícita" >&2
    echo "antes de publicar cualquier proyecto nuevo en el repositorio." >&2
    echo "" >&2
    echo "Pide confirmación a la persona humana antes de modificar .gitignore." >&2
    echo "Si ya tienes confirmación, pide al humano que ejecute:" >&2
    echo "  bash scripts/protect-project-privacy.sh --authorize <nombre-proyecto>" >&2
    exit 2
fi

exit 0
