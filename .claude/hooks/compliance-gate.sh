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
# Entrada por stdin (Claude Code y OpenCode) o variable de respaldo; solo cuenta tool_input.command.
# JSON malformado → bloqueo (fallo cerrado). Sin entrada → «no medido» registrado y salida 0.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_read_command compliance-gate; _rc=$?
[[ $_rc -eq 2 ]] && exit 2
[[ $_rc -eq 3 ]] && exit 0
# Sin filtrar heredocs (revisión 2 de #1413): el filtro abría un falso verde. Un texto «git commit»
# dentro de un heredoc puede dar un bloqueo falso, que es el lado seguro de un gate de flujo.
INPUT="$HOOK_COMMAND"
CMD_AT="$HOOK_CMD_AT"
GIT_AT="$HOOK_GIT_AT"
if ! grep -qE "${GIT_AT}commit([[:space:]]|$)" <<<"$INPUT"; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
RUNNER="$PROJECT_DIR/.claude/compliance/runner.sh"

# Repo objetivo del commit (-C / cd previo / cwd de la sesión), no el del hook. Sin objetivo
# determinable se bloquea: los gates de flujo protegen contra errores, y evaluar el árbol equivocado
# da verdes falsos. Se corrige usando una ruta literal (git -C /ruta commit, cd /ruta && git commit).
if ! hook_git_targets "$INPUT" "${HOOK_SESSION_CWD:-$PWD}"; then
  echo "🛑 COMPLIANCE GATE: no se puede determinar en qué repo se hace el commit ($HOOK_TARGET_REASON)." >&2
  echo "   Usa una ruta literal: git -C /ruta/al/repo commit ... o cd /ruta/al/repo && git commit ..." >&2
  exit 2
fi

if [[ ! -x "$RUNNER" ]]; then
  chmod +x "$RUNNER" 2>/dev/null || true
fi

if [[ -f "$RUNNER" ]]; then
  for TARGET in "${HOOK_GIT_TARGETS[@]}"; do
    COMPLIANCE_TARGET_DIR="$TARGET" bash "$RUNNER" --staged
    EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
      echo "" >&2
      echo "🛑 COMPLIANCE GATE: Commit bloqueado por violación de reglas ($TARGET)." >&2
      echo "   Ejecuta: COMPLIANCE_TARGET_DIR=$TARGET bash .claude/compliance/runner.sh --all para diagnóstico completo." >&2
      exit 2
    fi
  done
fi

exit 0
