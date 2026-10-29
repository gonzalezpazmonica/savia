#!/bin/bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"
# ────────────────────────────────────────────────────────────────────────────
# PostToolUse Hook: bash-output-compress.sh
# Compresses verbose Bash output to reduce context token consumption.
# Inspired by rtk-ai/rtk (60-90% token reduction on dev commands).
# Async hook — NEVER blocks. Always exits 0.
# ────────────────────────────────────────────────────────────────────────────

# La entrada llega por stdin (JSON de Claude Code / OpenCode); las variables TOOL_* solo son respaldo.
# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_read_posttool bash-output-compress

# Only trigger for Bash tool
if [[ "$HOOK_TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

OUTPUT="$HOOK_TOOL_OUTPUT"
[[ -z "$OUTPUT" ]] && exit 0

# Count lines
LINE_COUNT=$(printf '%s\n' "$OUTPUT" | wc -l)

# SE-326 S2: spill oversized output to private file instead of truncating inline.
# Umbrales: >200 líneas O >16KB. Best-effort — si falla, sigue el flujo normal.
SPILL_MAX_LINES="${SPILL_MAX_INLINE_LINES:-200}"
SPILL_MAX_BYTES="${SPILL_MAX_INLINE_BYTES:-16384}"
OUTPUT_BYTES=${#OUTPUT}
PROJECT_DIR_HOOK="${CLAUDE_PROJECT_DIR:-.}"
SPILL_SCRIPT="$PROJECT_DIR_HOOK/scripts/spill-save.sh"
if [[ -x "$SPILL_SCRIPT" ]] && { [[ $LINE_COUNT -gt $SPILL_MAX_LINES ]] || [[ $OUTPUT_BYTES -gt $SPILL_MAX_BYTES ]]; }; then
    SPILLED=$(printf '%s\n' "$OUTPUT" | bash "$SPILL_SCRIPT" --session "${CLAUDE_SESSION_ID:-default}" --name "bash-output.txt" 2>/dev/null) || SPILLED=""
    if [[ -n "$SPILLED" ]]; then
        echo "$SPILLED"
        exit 0
    fi
fi

# Pass through short output (<=30 lines)
if [[ $LINE_COUNT -le 30 ]]; then
    exit 0
fi

# Extract command from TOOL_INPUT JSON
COMMAND=$(printf '%s' "$HOOK_TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && COMMAND="unknown"
COMMAND_BASE=$(printf '%s' "$COMMAND" | awk '{print $1}' 2>/dev/null || echo "unknown")

# ── Compress via standalone script (all filters moved to output-compress.sh) ─────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
COMPRESS_SCRIPT="$PROJECT_DIR/scripts/output-compress.sh"

if [[ -x "$COMPRESS_SCRIPT" ]]; then
    COMPRESSED=$(printf '%s\n' "$OUTPUT" | bash "$COMPRESS_SCRIPT" --command "$COMMAND" 2>/dev/null) || COMPRESSED=""
else
    COMPRESSED=""
fi
[[ -z "$COMPRESSED" ]] && exit 0

# ── Calculate metrics and log ─────────────────────────────────────────────
ORIGINAL_TOKENS=$((${#OUTPUT} / 4))
COMPRESSED_TOKENS=$((${#COMPRESSED} / 4))
TOKENS_SAVED=$((ORIGINAL_TOKENS - COMPRESSED_TOKENS))

if [[ $ORIGINAL_TOKENS -gt 0 ]]; then
    RATIO=$(( (TOKENS_SAVED * 100) / ORIGINAL_TOKENS ))
    if [[ $RATIO -gt 20 ]]; then
        TRACKER="$PROJECT_DIR/scripts/context-tracker.sh"
        if [[ -x "$TRACKER" ]]; then
            bash "$TRACKER" log "bash-compress" "$COMMAND_BASE" "$TOKENS_SAVED" 2>/dev/null || true
        fi
    fi
fi

# Emit compressed output to stdout (injected as additionalContext by Claude Code)
echo "$COMPRESSED"
exit 0
