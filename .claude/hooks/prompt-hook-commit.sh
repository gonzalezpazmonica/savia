#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# ── Prompt Hook: Commit Message Semantic Validation ──
# Validates that commit messages accurately describe staged changes.
# Mode: warning (default) | soft-block | hard-block
# Uses Haiku model for fast semantic evaluation.
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

PROMPT_HOOKS_ENABLED="${PROMPT_HOOKS_ENABLED:-true}"
PROMPT_HOOKS_MODE="${PROMPT_HOOKS_MODE:-warning}"

[[ "$PROMPT_HOOKS_ENABLED" != "true" ]] && exit 0

# Only run on git commit commands
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

# Extract commit message from command
COMMIT_MSG=$(echo "$INPUT" | grep -oP '(?<=-m\s["\x27]).*?(?=["\x27])' || true)
[[ -z "$COMMIT_MSG" ]] && exit 0

# Get staged diff summary
DIFF_SUMMARY=$(git diff --cached --stat 2>/dev/null | tail -5)
[[ -z "$DIFF_SUMMARY" ]] && exit 0

# Semantic check: does the message match the changes?
# Count files by type to verify message accuracy
ADDED=$(git diff --cached --diff-filter=A --name-only 2>/dev/null | wc -l)
MODIFIED=$(git diff --cached --diff-filter=M --name-only 2>/dev/null | wc -l)
DELETED=$(git diff --cached --diff-filter=D --name-only 2>/dev/null | wc -l)

# Basic heuristic checks (no LLM needed for obvious mismatches)
ISSUES=""

# Check: "fix" in message but only additions
if echo "$COMMIT_MSG" | grep -qi "^fix" && [[ "$ADDED" -gt 0 && "$MODIFIED" -eq 0 ]]; then
  ISSUES+="Message says 'fix' but only new files added (no modifications). "
fi

# Check: "add" in message but only deletions
if echo "$COMMIT_MSG" | grep -qi "^feat\|^add" && [[ "$DELETED" -gt 0 && "$ADDED" -eq 0 ]]; then
  ISSUES+="Message says 'add/feat' but only deletions detected. "
fi

# Check: empty or too short message
if [[ ${#COMMIT_MSG} -lt 10 ]]; then
  ISSUES+="Message too short (<10 chars). "
fi

# Check: message exceeds 72 chars first line
FIRST_LINE=$(echo "$COMMIT_MSG" | head -1)
if [[ ${#FIRST_LINE} -gt 72 ]]; then
  ISSUES+="First line exceeds 72 characters. "
fi

# Check: CHANGELOG version links when CHANGELOG is staged
if git diff --cached --name-only 2>/dev/null | grep -q "CHANGELOG.md"; then
  VALIDATOR="${CLAUDE_PROJECT_DIR:-.}/scripts/validate-changelog-links.sh"
  if [[ -x "$VALIDATOR" ]]; then
    LINK_ERR=$("$VALIDATOR" "${CLAUDE_PROJECT_DIR:-.}/CHANGELOG.md" 2>&1) || \
      ISSUES+="CHANGELOG enlace faltante. "
  fi
fi

if [[ -n "$ISSUES" ]]; then
  case "$PROMPT_HOOKS_MODE" in
    "warning")
      echo "⚠️ Prompt Hook: ${ISSUES}" >&2
      exit 0
      ;;
    "soft-block")
      echo "⚠️ Prompt Hook (soft-block): ${ISSUES}" >&2
      echo "Override with PROMPT_HOOKS_MODE=warning" >&2
      exit 2
      ;;
    "hard-block")
      echo "❌ Prompt Hook (blocked): ${ISSUES}" >&2
      exit 2
      ;;
  esac
fi

exit 0
