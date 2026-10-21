#!/usr/bin/env bash
# twin-posttooluse.sh — Hook PostToolUse: dispara refresh de twins en eventos relevantes
# Spec: SPEC-169 AC-4
set -uo pipefail
# Profile tier: standard
# Hook: PostToolUse (mcp__github__*)
# Eventos: cierre de sprint (branch merge), cambio de estado de work item,
#          merge de PR que toque projects/*/
# Wire-ready: TWIN_HOOK_ENABLED=true activa el refresh automático.
# Sin esa variable, el hook es no-op (safe by default).

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"
REFRESH_SCRIPT="${ROOT_DIR}/scripts/twin-refresh.sh"

# Guard: no-op unless explicitly enabled
TWIN_HOOK_ENABLED="${TWIN_HOOK_ENABLED:-false}"
[[ "$TWIN_HOOK_ENABLED" != "true" ]] && exit 0

# Read PostToolUse input
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(timeout 3 cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

command -v jq &>/dev/null || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit twin-posttooluse; }

# Detect affected project from tool output
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
OUTPUT=$(printf '%s' "$INPUT" | jq -r '.tool_result // empty' 2>/dev/null || true)

# Extract project slug from any projects/* path in output
SLUG=$(printf '%s' "$OUTPUT" | grep -oE 'projects/[a-z][a-z0-9_-]+/' | head -1 | sed 's|projects/||;s|/$||' || true)

[[ -z "$SLUG" ]] && exit 0

TWIN_FILE="${ROOT_DIR}/projects/${SLUG}/twin.md"
[[ ! -f "$TWIN_FILE" ]] && exit 0

# Only trigger on relevant tool events
case "$TOOL_NAME" in
  mcp__github__create_pull_request|\
  mcp__github__merge_pull_request|\
  mcp__azuredevops__update_work_item)
    bash "$REFRESH_SCRIPT" "$SLUG" >/dev/null 2>&1 || true
    ;;
esac

exit 0
