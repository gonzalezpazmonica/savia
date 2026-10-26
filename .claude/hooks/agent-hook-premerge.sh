#!/usr/bin/env bash
set -uo pipefail
# ── Agent Hook: Pre-Merge Security & Quality Gate ──
# Runs lightweight security checks on staged files before merge.
# Does NOT invoke LLM — uses deterministic pattern matching.
# Full agent-based review is triggered via /pr-review command.
# Profile tier: standard

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

AGENT_HOOKS_ENABLED="${AGENT_HOOKS_ENABLED:-true}"
AGENT_HOOKS_MODE="${AGENT_HOOKS_MODE:-warning}"
TIMEOUT_SECS=30

[[ "$AGENT_HOOKS_ENABLED" != "true" ]] && exit 0

# Only run on merge-related commands
# Claude Code y OpenCode pasan la entrada del hook por stdin; CLAUDE_TOOL_INPUT no lo define ningún
# runtime y leerla sola dejaba el hook en fallo abierto (exit 0 siempre). Se conserva como respaldo.
INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$INPUT" && ! -t 0 ]]; then INPUT=$(timeout 3 cat 2>/dev/null || true); fi
if ! echo "$INPUT" | grep -qE "git merge|gh pr merge"; then
  exit 0
fi

ISSUES=""
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || \
               git diff HEAD~1 --name-only 2>/dev/null || true)

[[ -z "$STAGED_FILES" ]] && exit 0

# Check 1: No secrets in staged files
SECRETS_PATTERN='(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|-----BEGIN.*PRIVATE KEY)'
for f in $STAGED_FILES; do
  [[ -f "$f" ]] || continue
  if grep -qE "$SECRETS_PATTERN" "$f" 2>/dev/null; then
    ISSUES+="Possible secret in $f. "
  fi
done

# Check 2: No TODO without ticket reference
for f in $STAGED_FILES; do
  [[ -f "$f" ]] || continue
  BARE_TODOS=$(grep -n 'TODO\|FIXME\|HACK' "$f" 2>/dev/null \
    | grep -v 'AB#\|@\|#[0-9]' || true)
  if [[ -n "$BARE_TODOS" ]]; then
    ISSUES+="TODOs without ticket in $f. "
  fi
done

# Check 3: No merge conflict markers
for f in $STAGED_FILES; do
  [[ -f "$f" ]] || continue
  if grep -qE '^\s*(<{7}|>{7}|={7})' "$f" 2>/dev/null; then
    ISSUES+="Merge conflict markers in $f. "
  fi
done

# Check 4: File size limit (150 lines for workspace files)
for f in $STAGED_FILES; do
  [[ -f "$f" ]] || continue
  case "$f" in
    .opencode/commands/*|.claude/rules/*|docs/rules/*|.opencode/agents/*|.opencode/skills/*)
      LINES=$(awk 'END{print NR}' "$f")
      if [[ "$LINES" -gt 150 ]]; then
        ISSUES+="$f exceeds 150 lines ($LINES). "
      fi
      ;;
  esac
done

if [[ -n "$ISSUES" ]]; then
  case "$AGENT_HOOKS_MODE" in
    "warning")
      echo "⚠️ Agent Hook: ${ISSUES}" >&2
      exit 0
      ;;
    "soft-block")
      echo "⚠️ Agent Hook (soft-block): ${ISSUES}" >&2
      exit 2
      ;;
    "hard-block")
      echo "❌ Agent Hook (blocked): ${ISSUES}" >&2
      exit 2
      ;;
  esac
fi

exit 0
