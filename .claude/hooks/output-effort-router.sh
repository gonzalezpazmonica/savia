#!/usr/bin/env bash
set -uo pipefail
# SE-224 Slice 2 — effort router
# PreToolUse hook. Classifies the upcoming turn and emits effort level hint.
#
# MECHANICAL turns: emit budget hint (concise response sufficient)
# NEW_ASK / ERROR turns: no hint (full reasoning preserved)
#
# Allowlist (always NEW_ASK regardless of output length):
#   Edit, Write, Task — quality-sensitive tools, never reduce effort
#
# Classification mirrors output-verbosity-sentinel.sh (structural, zero LLM):
#   MECHANICAL: TOOL_OUTPUT short (< 100 chars) and no error signals
#   ERROR:      TOOL_RESULT_IS_ERROR=true or output contains ERROR:/FAIL:/FATAL
#   NEW_ASK:    substantial output / unknown / allowlisted tool
#
# Output: emits hint to stderr for observability.
# Telemetry: output/verbosity-telemetry.jsonl — {ts, hook, classification, tool}
#
# Master switch: SAVIA_EFFORT_ROUTER=on|off  (default: on)
# Always exit 0. Never blocks. Pure observability hook.


# ── Master switch ─────────────────────────────────────────────────────────────
if [[ "${SAVIA_EFFORT_ROUTER:-on}" == "off" ]]; then
    exit 0
fi

# ── Resolve workspace ─────────────────────────────────────────────────────────
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WORKSPACE="${CLAUDE_PROJECT_DIR:-$(cd "$_HOOK_DIR/../.." && pwd)}"

# ── Read stdin (PreToolUse JSON payload) ──────────────────────────────────────
INPUT=""
if [[ ! -t 0 ]]; then
    INPUT=$(cat)
fi

# ── Quality-sensitive tool allowlist (always NEW_ASK) ───────────────────────
CURRENT_TOOL="${TOOL_NAME:-}"

# Also attempt to extract tool from JSON input
if [[ -z "$CURRENT_TOOL" ]] && command -v jq &>/dev/null && [[ -n "$INPUT" ]]; then
    CURRENT_TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // ""' 2>/dev/null || true)
fi

case "$CURRENT_TOOL" in
    Edit|Write|Task|Agent)
        # Allowlist: always NEW_ASK — skip effort reduction
        exit 0
        ;;
esac

# ── Extract previous tool output for classification ──────────────────────────
IS_ERROR=""
OUTPUT_CONTENT=""

if [[ -n "$INPUT" ]] && command -v jq &>/dev/null; then
    IS_ERROR=$(printf '%s' "$INPUT" | jq -r '.previous_tool_result.is_error // .is_error // false' 2>/dev/null || echo "false")
    OUTPUT_CONTENT=$(printf '%s' "$INPUT" | jq -r '.previous_tool_result.output // .output // ""' 2>/dev/null || true)
fi

# Fall back to env vars (set by OpenCode for the previous turn)
if [[ -z "$OUTPUT_CONTENT" ]]; then
    OUTPUT_CONTENT="${TOOL_OUTPUT:-}"
fi
if [[ -z "$IS_ERROR" ]] || [[ "$IS_ERROR" == "false" && -n "${TOOL_RESULT_IS_ERROR:-}" ]]; then
    IS_ERROR="${TOOL_RESULT_IS_ERROR:-false}"
fi

OUTPUT_LEN="${#OUTPUT_CONTENT}"

# ── Classify ──────────────────────────────────────────────────────────────────
CLASSIFICATION="NEW_ASK"

if [[ "$IS_ERROR" == "true" ]] || printf '%s' "$OUTPUT_CONTENT" | grep -qE '(^|\s)(ERROR:|FAIL:|FATAL)'; then
    CLASSIFICATION="ERROR"
elif [[ $OUTPUT_LEN -lt 100 ]]; then
    CLASSIFICATION="MECHANICAL"
fi

# ── Emit effort hint for MECHANICAL turns only ───────────────────────────────
if [[ "$CLASSIFICATION" == "MECHANICAL" ]]; then
    printf '[SE-224] effort=low tool=%s — mechanical turn, brief response sufficient\n' "${CURRENT_TOOL:-unknown}" >&2
    printf '[EFFORT: low — mechanical turn, brief response sufficient]\n' >&2
fi

# ── Telemetry ─────────────────────────────────────────────────────────────────
TELEMETRY_DIR="${_WORKSPACE}/output"
if [[ -d "$TELEMETRY_DIR" ]]; then
    TELEMETRY_FILE="${TELEMETRY_DIR}/verbosity-telemetry.jsonl"
    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"ts":"%s","hook":"effort-router","classification":"%s","output_len":%d,"tool":"%s"}\n' \
        "$TS" "$CLASSIFICATION" "$OUTPUT_LEN" "${CURRENT_TOOL:-unknown}" \
        >> "$TELEMETRY_FILE" 2>/dev/null || true
fi

exit 0
