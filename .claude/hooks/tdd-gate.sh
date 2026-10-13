#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# tdd-gate.sh — Verifica que existen tests antes de permitir edición de código de producción
# Usado por: developer agents (PreToolUse hook)
# Lógica: Si el agente intenta editar un fichero de producción (.cs, .py, .ts, .go, .rs, .rb, .php, .java)
#         y NO existe un fichero de test correspondiente, BLOQUEA con exit 2.
# Excepción: ficheros de config, migrations, DTOs, y el propio test se permiten siempre.
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

# Read stdin with timeout to avoid hanging if no input arrives
# Uses timeout+cat to handle input that may lack trailing newline
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# Parse tool name and file path from JSON
TOOL=""
FILE_PATH=""
if [[ -n "$INPUT" ]]; then
  if command -v jq &>/dev/null; then
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL=""
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
  else
    TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"\s*:\s*"[^"]*' | head -1 | sed 's/.*"//' || true)
    FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"\s*:\s*"[^"]*' | head -1 | sed 's/.*"//' || true)
  fi
fi

# Solo aplica a Edit y Write
if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then
  exit 0
fi

[ -z "$FILE_PATH" ] && exit 0

# Obtener extensión
EXT="${FILE_PATH##*.}"

# Solo verificar extensiones de código de producción
case "$EXT" in
  cs|py|ts|tsx|js|jsx|go|rs|rb|php|java|kt|swift|dart) ;;
  *) exit 0 ;;
esac

# Excluir ficheros que no necesitan TDD gate
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  *Test*|*test*|*Spec*|*spec*|*_test.*|*.test.*|*.spec.*) exit 0 ;;
  *Migration*|*migration*|*.dto.*|*DTO*|*.config.*|*Config.*) exit 0 ;;
  *Program.cs|*Startup.cs|*appsettings*|*.csproj|*.sln) exit 0 ;;
  *.d.ts|*.config.ts|*.config.js|tsconfig*|package.json) exit 0 ;;
  Dockerfile|docker-compose*|*.tf|*.tfvars|*.yml|*.yaml) exit 0 ;;
  *.md|*.txt|*.json|*.xml|*.html|*.css|*.scss) exit 0 ;;
esac

# Excluir paths que no son código de producción
case "$FILE_PATH" in
  */test/*|*/tests/*|*/Test/*|*/Tests/*|*/__tests__/*) exit 0 ;;
  */spec/*|*/specs/*|*/Spec/*|*/Specs/*) exit 0 ;;
  */fixtures/*|*/mocks/*|*/stubs/*|*/fakes/*) exit 0 ;;
  */migrations/*|*/Migrations/*|*/seeds/*) exit 0 ;;
  */config/*|*/Config/*|*/scripts/*) exit 0 ;;
esac

# Buscar test correspondiente
DIR=$(dirname "$FILE_PATH")
NAME_NO_EXT="${BASENAME%.*}"
# Try git first (from the edited file's dir, so files outside the workspace
# resolve to THEIR repo), but fall back to current dir or CLAUDE_PROJECT_DIR
# In tests, this will be the TEST_TMPDIR which has .git initialized
# The target directory may not exist yet (first file of a new folder): probe the
# nearest existing ancestor, otherwise `git -C` fails and the lookup silently
# falls back to the session repo and misses the tests that DO exist.
PROBE="$DIR"
while [ -n "$PROBE" ] && [ "$PROBE" != "/" ] && [ ! -d "$PROBE" ]; do
  PROBE=$(dirname "$PROBE")
done
if PROJECT_ROOT=$(git -C "$PROBE" rev-parse --show-toplevel 2>/dev/null); then
  :
elif PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  :
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
else
  PROJECT_ROOT="."
fi

# Buscar test files que coincidan
TESTS_FOUND=$(find "$PROJECT_ROOT" -type f \( \
  -name "${NAME_NO_EXT}Test.*" -o \
  -name "${NAME_NO_EXT}Tests.*" -o \
  -name "${NAME_NO_EXT}.test.*" -o \
  -name "${NAME_NO_EXT}.spec.*" -o \
  -name "${NAME_NO_EXT}_test.*" -o \
  -name "test_${NAME_NO_EXT}.*" \
  \) 2>/dev/null | head -1)

if [ -z "$TESTS_FOUND" ]; then
  echo "TDD GATE: No se encontraron tests para '$BASENAME'. Escribe los tests ANTES de implementar el código de producción. Busca o crea: ${NAME_NO_EXT}Test.${EXT} o ${NAME_NO_EXT}.test.${EXT}" >&2
  exit 2
fi

exit 0
