#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# block-gitignored-references.sh — Bloquea publicación de rutas/contenido gitignored en ficheros N1
# Profile tier: security
# Hook: PreToolUse (Edit|Write)
# Detecta cuando se escribe contenido que referencia rutas gitignored
# (output/*, private-agent-memory/*, config.local/*, scores internos, etc.)
# en ficheros trackeados por git (N1 público).

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Read hook input from stdin
INPUT=""
if [[ ! -t 0 ]]; then
  if command -v timeout >/dev/null 2>&1; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
  else
    INPUT=$(cat 2>/dev/null) || true
  fi
fi
[[ -z "$INPUT" ]] && exit 0

# Require jq
command -v jq &>/dev/null || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit block-gitignored-references; }

# Extract file path
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# Skip if target IS a private destination (writing TO gitignored is fine)
case "$FILE_PATH" in
  */projects/*|projects/*|*.local.*|*/output/*|*private-agent-memory*|*/config.local/*|*/.savia/*|*/.claude/sessions/*|*settings.local.json*) exit 0 ;;
esac

# Skip test files and hook source (they legitimately reference gitignored patterns)
# Match both forward-slash (Unix) and backslash (Windows) path separators.
case "$FILE_PATH" in
  *tests/test-*|*tests/*.bats|*scripts/test-*) exit 0 ;;
  */.opencode/hooks/*|.opencode/hooks/*) exit 0 ;;
  *\\.claude\\hooks\\*) exit 0 ;;
esac

# Skip if file is gitignored (not N1)
if command -v git &>/dev/null; then
  if git check-ignore -q "$FILE_PATH" 2>/dev/null; then
    exit 0
  fi
fi

# Extract content being written
CONTENT=$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // .tool_input.new_string // "")[:30000]' 2>/dev/null) || exit 0
[[ -z "$CONTENT" ]] && exit 0

# === PATTERNS: gitignored paths that should never appear in N1 files ===

VIOLATIONS=""

# 1. Explicit output/ paths with dates (internal reports)
if echo "$CONTENT" | grep -qE 'output/[0-9]{8}'; then
  VIOLATIONS="${VIOLATIONS}\n  - Ruta output/ con fecha (informe interno)"
fi

# 2. Private agent memory paths
if echo "$CONTENT" | grep -qE 'private-agent-memory/[a-z]'; then
  VIOLATIONS="${VIOLATIONS}\n  - Referencia a private-agent-memory/ (N2 gitignored)"
fi

# 3. config.local/ paths
if echo "$CONTENT" | grep -qE 'config\.local/'; then
  VIOLATIONS="${VIOLATIONS}\n  - Referencia a config.local/ (secrets, N2)"
fi

# 4. User profile paths with real slugs (not template)
if echo "$CONTENT" | grep -qE '\.claude/profiles/users/[a-z][a-z0-9-]+/' | grep -qvE 'template|{slug}|\{usuario\}'; then
  VIOLATIONS="${VIOLATIONS}\n  - Ruta de perfil de usuario real (N3)"
fi

# 5. Audit scores (internal metrics: X.Y/10, XX/100)
if echo "$CONTENT" | grep -qE '[0-9]+\.[0-9]/10 score|score [0-9]+/100|([0-9]+/100)'; then
  VIOLATIONS="${VIOLATIONS}\n  - Score de auditoría interna (métrica derivada)"
fi

# 6. Debt-score with concrete values per project
if echo "$CONTENT" | grep -qE 'debt-score: [0-9]+/10'; then
  VIOLATIONS="${VIOLATIONS}\n  - Debt-score concreto por proyecto (métrica interna)"
fi

# 7. Vulnerability counts (security audit results)
if echo "$CONTENT" | grep -qiE '[0-9]+ vulnerabilit(ies|y) found|[0-9]+ resolved.*score'; then
  VIOLATIONS="${VIOLATIONS}\n  - Conteo de vulnerabilidades (resultado de auditoría interna)"
fi

# 8. .human-maps with project-specific content
if echo "$CONTENT" | grep -qE 'projects/[a-z][a-z0-9-]+/\.human-maps/'; then
  VIOLATIONS="${VIOLATIONS}\n  - Ruta .human-maps/ de proyecto (contenido interno)"
fi

# 9. Dynamic: load gitignore patterns and check for project-specific paths
# Only for projects/ entries that are NOT whitelisted
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
  # Extract whitelisted projects from .gitignore (lines starting with !projects/)
  WHITELISTED=$(grep '^!projects/' "$PROJECT_DIR/.gitignore" 2>/dev/null | sed 's|^!projects/||;s|/$||' | tr '\n' '|')
  WHITELISTED="${WHITELISTED%|}"  # Remove trailing pipe

  # Check if content references non-whitelisted project paths
  if [[ -n "$WHITELISTED" ]]; then
    # Find project references in content that are NOT in the whitelist
    NON_WL=$(echo "$CONTENT" | grep -oE 'projects/[a-z][a-z0-9_-]+/' | sed 's|projects/||;s|/||' | sort -u | grep -vE "^($WHITELISTED)$" || true)
    if [[ -n "$NON_WL" ]]; then
      for proj in $NON_WL; do
        VIOLATIONS="${VIOLATIONS}\n  - Referencia a projects/$proj/ (proyecto no whitelisteado)"
      done
    fi
  fi
fi

# === VERDICT ===

if [[ -n "$VIOLATIONS" ]]; then
  echo "BLOQUEADO: Contenido gitignored detectado en fichero público ($FILE_PATH):" >&2
  printf "$VIOLATIONS\n" >&2
  echo "" >&2
  echo "Usa términos genéricos en lugar de rutas/métricas internas." >&2
  echo "Ver: docs/rules/domain/zero-project-leakage.md" >&2
  exit 2
fi

exit 0
