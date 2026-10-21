#!/usr/bin/env bash
set -uo pipefail
# propuestas-index-refresh.sh — PostToolUse hook: regenerate docs/propuestas/INDEX.md
# when a file in docs/propuestas/ is modified.
#
# Spec: SE-222 S2 (index.md auto-generated)
# Trigger: PostToolUse on Edit|Write tools
# Rate-limit: at most 1 regeneration per 60s (via lock file timestamp)
#
# Wire-ready: safe by default (no-op if propuestas dir not found).


HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"
SCRIPT="$ROOT_DIR/scripts/propuestas-index-gen.sh"
PROPUESTAS_DIR="$ROOT_DIR/docs/propuestas"
LOCK_FILE="/tmp/propuestas-index-refresh.lock"

# ── read PostToolUse input ────────────────────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(timeout 3 cat 2>/dev/null) || true
fi

[[ -z "$INPUT" ]] && exit 0

command -v jq &>/dev/null || { source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"; hook_unmeasured_exit propuestas-index-refresh; }

# Detect the file that was modified
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
[[ -z "$FILE_PATH" ]] && exit 0

# Only trigger for files inside docs/propuestas/ (any depth)
case "$FILE_PATH" in
  *docs/propuestas/*)
    # Skip if it's the index itself
    case "$FILE_PATH" in
      */index.md|*/INDEX.md) exit 0 ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

# ── rate-limit: max 1 run per 60s ────────────────────────────────────────────
NOW=$(date +%s)
if [[ -f "$LOCK_FILE" ]]; then
  LAST=$(cat "$LOCK_FILE" 2>/dev/null || echo 0)
  DIFF=$(( NOW - LAST ))
  if [[ $DIFF -lt 60 ]]; then
    exit 0
  fi
fi
echo "$NOW" > "$LOCK_FILE"

# ── run script ────────────────────────────────────────────────────────────────
[[ ! -f "$SCRIPT" ]] && exit 0
[[ ! -d "$PROPUESTAS_DIR" ]] && exit 0

bash "$SCRIPT" >/dev/null 2>&1 || true

exit 0
