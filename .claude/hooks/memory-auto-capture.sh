#!/bin/bash
# memory-auto-capture.sh — PostToolUse hook for automatic memory capture
set -uo pipefail
# Early exit before sourcing savia-env.sh (it forks git/dirname/basename):
# only Edit/Write trigger a capture, every other call returns without a fork.
TOOL_NAME="${TOOL_NAME:-}"
[[ "$TOOL_NAME" =~ ^(Edit|Write)$ ]] || exit 0

source "${BASH_SOURCE[0]%/*}/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-.}"
STORE_SCRIPT="$PROJECT_ROOT/scripts/memory-store.sh"
RATE_LIMIT_FILE="$HOME/.pm-workspace/memory-capture-last.ts"
RATE_LIMIT_MIN=5

[[ ! -f "$STORE_SCRIPT" ]] && exit 0

# Check rate limit (skip if < 5 min since last capture)
if [[ -f "$RATE_LIMIT_FILE" ]]; then
    last_ts=$(cat "$RATE_LIMIT_FILE")
    now=$(date +%s)
    elapsed=$((now - last_ts))
    [[ $elapsed -lt $((RATE_LIMIT_MIN * 60)) ]] && exit 0
fi

# Extract file path from tool context
file_path="${EDITED_FILE:-${FILE_PATH:-}}"
[[ -z "$file_path" ]] && exit 0

# Only capture if file is in special dirs
if ! [[ "$file_path" =~ (scripts/|docs/rules/|\.claude/rules/|\.opencode/commands/|tests/) ]]; then
    exit 0
fi

# Infer type from file path
infer_type() {
    local path="$1"
    [[ "$path" =~ tests/ ]] && echo "pattern" && return
    [[ "$path" =~ docs/rules/|\.claude/rules/ ]] && echo "convention" && return
    [[ "$path" =~ scripts/ ]] && echo "discovery" && return
    [[ "$path" =~ \.opencode/commands/ ]] && echo "convention" && return
    echo "discovery"
}

# Extract concepts from file path segments
infer_concepts() {
    local path="$1"
    local concepts=""
    for segment in $(echo "$path" | tr '/' ' '); do
        # Skip common keywords
        [[ "$segment" =~ (\.claude|scripts|tests|\.sh|\.md) ]] && continue
        concepts="$concepts,$segment"
    done
    echo "${concepts#,}"
}

type=$(infer_type "$file_path")
concepts=$(infer_concepts "$file_path")
title=$(basename "$file_path" | sed 's/\.[^.]*$//')

# Read first 200 chars of file as content preview
content=$(head -c 200 "$file_path" 2>/dev/null || echo "")

# Save to memory store
bash "$STORE_SCRIPT" save \
    --type "$type" \
    --title "$title" \
    --content "$content" \
    --concepts "$concepts" \
    --project "${PROJECT_NAME:-}" \
    2>/dev/null || true

# Update rate limit timestamp
mkdir -p "$HOME/.pm-workspace"
date +%s > "$RATE_LIMIT_FILE"

exit 0
