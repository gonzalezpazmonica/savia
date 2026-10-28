#!/usr/bin/env bash
set -uo pipefail
# memory-feedback-task.sh — PostToolUse hook: extracts Task outcomes and writes to auto-memory
# Spec: SPEC-164 (docs/propuestas/SPEC-164-memory-feedback-loop.md)
# Hook type: PostToolUse (tool_name == "Task")
# Master switch: SAVIA_MEMORY_FEEDBACK=on|off  (default: off — opt-in)

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$HOOK_DIR/../.." && pwd)}"

# ── Master switch ────────────────────────────────────────────────────────────
SAVIA_MEMORY_FEEDBACK="${SAVIA_MEMORY_FEEDBACK:-off}"
[[ "$SAVIA_MEMORY_FEEDBACK" != "on" ]] && exit 0

# ── Dependencies ─────────────────────────────────────────────────────────────
MEMORY_STORE="${ROOT_DIR}/scripts/memory-store.sh"
EXTRACTOR="${ROOT_DIR}/scripts/memory-feedback-extractor.py"
TELEMETRY="${ROOT_DIR}/output/memory-feedback-telemetry.jsonl"

[[ ! -f "$MEMORY_STORE" ]] && exit 0
command -v python3 &>/dev/null || exit 0

# ── Read stdin (PostToolUse payload) ─────────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
    INPUT=$(timeout 5 cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

# ── Only process Task tool calls ─────────────────────────────────────────────
TOOL_NAME=""
if command -v jq &>/dev/null; then
    TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
else
    TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
fi
[[ "$TOOL_NAME" != "Task" && "$TOOL_NAME" != "Agent" ]] && exit 0

# ── Run extractor ─────────────────────────────────────────────────────────────
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

EXTRACT_OUTPUT=""
EXTRACT_OUTPUT=$(printf '%s' "$INPUT" | python3 "$EXTRACTOR" 2>/dev/null) || true

if [[ -z "$EXTRACT_OUTPUT" ]]; then
    # Extractor failed silently — log and exit
    mkdir -p "$(dirname "$TELEMETRY")"
    printf '{"ts":"%s","source":"memory-feedback-task","outcome":"unknown","written":false,"reason_skip":"extractor_failed"}\n' \
        "$TS" >> "$TELEMETRY" 2>/dev/null || true
    exit 0
fi

# ── Parse extractor JSON output ───────────────────────────────────────────────
OUTCOME=""
AGENT_NAME=""
LESSON=""
SHOULD_WRITE=""

if command -v jq &>/dev/null; then
    OUTCOME=$(printf '%s' "$EXTRACT_OUTPUT" | jq -r '.outcome // "unknown"' 2>/dev/null || echo "unknown")
    AGENT_NAME=$(printf '%s' "$EXTRACT_OUTPUT" | jq -r '.agent_name // "unknown"' 2>/dev/null || echo "unknown")
    LESSON=$(printf '%s' "$EXTRACT_OUTPUT" | jq -r '.lesson // ""' 2>/dev/null || true)
    SHOULD_WRITE=$(printf '%s' "$EXTRACT_OUTPUT" | jq -r '.should_write // "false"' 2>/dev/null || echo "false")
else
    OUTCOME=$(printf '%s' "$EXTRACT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('outcome','unknown'))" 2>/dev/null || echo "unknown")
    AGENT_NAME=$(printf '%s' "$EXTRACT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_name','unknown'))" 2>/dev/null || echo "unknown")
    LESSON=$(printf '%s' "$EXTRACT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('lesson',''))" 2>/dev/null || true)
    SHOULD_WRITE=$(printf '%s' "$EXTRACT_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('should_write',False)).lower())" 2>/dev/null || echo "false")
fi

# ── Entropy filter: skip writes for trivial successes ────────────────────────
mkdir -p "$(dirname "$TELEMETRY")"

if [[ "$SHOULD_WRITE" != "true" ]]; then
    printf '{"ts":"%s","source":"memory-feedback-task","outcome":"%s","agent":"%s","written":false,"reason_skip":"entropy_below_threshold"}\n' \
        "$TS" "$OUTCOME" "$AGENT_NAME" >> "$TELEMETRY" 2>/dev/null || true
    exit 0
fi

# ── Build memory entry ────────────────────────────────────────────────────────
# Truncate lesson to 150 chars
LESSON="${LESSON:0:150}"
MEMORY_ENTRY="outcome:${OUTCOME} agent:${AGENT_NAME} lesson:${LESSON} [${TS}]"

# ── Write to memory-store ─────────────────────────────────────────────────────
WRITE_RESULT=0
bash "$MEMORY_STORE" save \
    --type "episode" \
    --title "outcome:${OUTCOME} agent:${AGENT_NAME}" \
    --content "$MEMORY_ENTRY" \
    --concepts "${AGENT_NAME},${OUTCOME}" \
    2>/dev/null || WRITE_RESULT=$?

# ── Telemetry ─────────────────────────────────────────────────────────────────
if [[ $WRITE_RESULT -eq 0 ]]; then
    printf '{"ts":"%s","source":"memory-feedback-task","outcome":"%s","agent":"%s","written":true,"reason_skip":null}\n' \
        "$TS" "$OUTCOME" "$AGENT_NAME" >> "$TELEMETRY" 2>/dev/null || true
else
    printf '{"ts":"%s","source":"memory-feedback-task","outcome":"%s","agent":"%s","written":false,"reason_skip":"memory_store_error"}\n' \
        "$TS" "$OUTCOME" "$AGENT_NAME" >> "$TELEMETRY" 2>/dev/null || true
fi

# Always exit 0 — hook must never block the pipeline
exit 0
