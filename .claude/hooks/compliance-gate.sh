#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# compliance-gate.sh — Gate de compliance que bloquea commits con violaciones
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi
#
# Se ejecuta como PreToolUse hook antes de git commit.
# A diferencia de prompt-hook-commit.sh (warning), este BLOQUEA (exit 2).
#
# Verifica:
#   1. Links de comparación en CHANGELOG.md
#   2. Tamaño de ficheros (commands/rules/skills ≤ 150 líneas)
#   3. Frontmatter YAML en comandos nuevos
#   4. Sincronización de READMEs
set -uo pipefail

# Solo ejecutar en git commit
# Claude Code y OpenCode pasan la entrada del hook por stdin; CLAUDE_TOOL_INPUT no lo define ningún
# runtime y leerla sola dejaba el hook en fallo abierto (exit 0 siempre). Se conserva como respaldo.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" && ! -t 0 ]]; then INPUT=$(timeout 3 cat 2>/dev/null || true); fi
# Con JSON de stdin se evalúa solo tool_input.command: una mención en la descripción, en un grep o en un
# heredoc no es una orden. Las órdenes se anclan a su inicio (principio, ;, &, |, ( o prefijos VAR=x).
if [[ "$INPUT" == \{* ]]; then
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
  hook_extract_command "$INPUT" || exit 2
  INPUT="$HOOK_COMMAND"
fi
CMD_AT='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
GIT_AT="${CMD_AT}"'git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+'
if ! echo "$INPUT" | grep -qE "${GIT_AT}commit([[:space:]]|$)"; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
RUNNER="$PROJECT_DIR/.claude/compliance/runner.sh"

if [[ ! -x "$RUNNER" ]]; then
  chmod +x "$RUNNER" 2>/dev/null || true
fi

if [[ -f "$RUNNER" ]]; then
  bash "$RUNNER" --staged
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then
    echo "" >&2
    echo "🛑 COMPLIANCE GATE: Commit bloqueado por violación de reglas." >&2
    echo "   Ejecuta: bash .claude/compliance/runner.sh --all para diagnóstico completo." >&2
    exit 2
  fi
fi

exit 0
