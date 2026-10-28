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
# stdin es la fuente autorizada; la variable solo vale de respaldo si stdin llega vacío (una variable
# heredada en el entorno no puede sustituir a la entrada real y anular la evaluación).
INPUT=""
if [[ ! -t 0 ]]; then INPUT=$(timeout 3 cat 2>/dev/null || true); fi
[[ -z "$INPUT" ]] && INPUT="${CLAUDE_TOOL_INPUT:-}"

# Con JSON de stdin se evalúa el contenido RESULTANTE de .gitignore (lib/gitignore-whitelist-delta.py):
# bloquea si aparece alguna whitelist de proyecto que no estaba, incluida una edición parcial que solo
# cambia el nombre. Quitar una whitelist, o editar otro fichero, no bloquea. No evaluable → bloqueo.
# Sin JSON (respaldo por variable) se mantiene el filtro textual de antes. Here-strings: sin SIGPIPE.
_trim="${INPUT#"${INPUT%%[![:space:]]*}"}"
if [[ "$_trim" == \{* ]]; then
    printf '%s' "$_trim" | python3 "$(dirname "${BASH_SOURCE[0]}")/lib/gitignore-whitelist-delta.py"
    case $? in
        0) exit 0 ;;
        1) WHITELIST_NUEVA=1 ;;
        *) echo "BLOQUEADO [block-project-whitelist]: no se pudo evaluar la edición de .gitignore." >&2; exit 2 ;;
    esac
elif ! grep -q "\.gitignore" <<<"$INPUT"; then
    exit 0
fi

# Detectar si el contenido incluye un whitelist de proyecto (!projects/)
if [[ "${WHITELIST_NUEVA:-0}" == 1 ]] || grep -qE '!projects/' <<<"$INPUT"; then
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
