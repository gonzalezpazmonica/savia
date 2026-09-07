#!/usr/bin/env bash
# model-capability-resolver.sh — Resolve model capabilities from YAML registry
# Outputs SAVIA_* env vars for the given model. Unknown metadata is explicit:
# a plausible default context window is not evidence of a model capability.
# Usage: source <(./scripts/model-capability-resolver.sh [--model name])
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# Read stdin for hook compatibility
cat /dev/stdin > /dev/null 2>&1 || true

# ── Determine model (provider-agnostic) ────────────────────────────────────
MODEL="${SAVIA_MODEL:-${CLAUDE_MODEL_AGENT:-}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done
MODEL="${MODEL:-default}"
PROVIDER=""
MODEL_ID="$MODEL"
if [[ "$MODEL" == */* ]]; then
  PROVIDER="${MODEL%%/*}"
  MODEL_ID="${MODEL#*/}"
fi
QUALIFIED_MODEL="$MODEL"

# ── Locate config file ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/model-capabilities.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  # Missing metadata does not authorize optimistic planning.
  echo "export SAVIA_CONTEXT_WINDOW=0"
  echo "export SAVIA_MODEL_TIER=unknown"
  echo "export SAVIA_COMPACT_THRESHOLD=0"
  echo "export SAVIA_SUPPORTS_THINKING=false"
  echo "export SAVIA_DETECTED_MODEL=${QUALIFIED_MODEL}"
  echo "export SAVIA_MODEL_PROVIDER=${PROVIDER}"
  echo "export SAVIA_MODEL_ID=${MODEL_ID}"
  echo "export SAVIA_MODEL_METADATA_STATUS=unknown"
  exit 0
fi

# ── Parse YAML with grep/sed (no yq dependency) ─────────────────────────────
# Extract block for the target model, or fall back to default
extract_field() {
  local model="$1" field="$2" fallback="$3"
  local value=""
  # Try model-specific block first
  if [ "$model" != "default" ]; then
    value=$(sed -n "/^  ${model}:/,/^  [a-z]/p" "$CONFIG_FILE" \
      | grep "    ${field}:" | head -1 \
      | sed 's/.*: *//' | tr -d '[:space:]')
  fi
  # Fall back to default block
  if [ -z "$value" ]; then
    value=$(sed -n '/^default:/,/^[a-z]/p' "$CONFIG_FILE" \
      | grep "  ${field}:" | head -1 \
      | sed 's/.*: *//' | tr -d '[:space:]')
  fi
  echo "${value:-$fallback}"
}

if grep -Fqx "  ${MODEL_ID}:" "$CONFIG_FILE"; then
  CONTEXT_WINDOW=$(extract_field "$MODEL_ID" "context_window" "")
  TIER=$(extract_field "$MODEL_ID" "tier" "")
  COMPACT_PCT=$(extract_field "$MODEL_ID" "recommended_compact_threshold_pct" "")
  THINKING=$(extract_field "$MODEL_ID" "supports_extended_thinking" "")
else
  CONTEXT_WINDOW=""; TIER=""; COMPACT_PCT=""; THINKING=""
fi
STATUS=verified
if [ "$MODEL_ID" = "default" ] || [ -z "$CONTEXT_WINDOW" ] || [ -z "$TIER" ] || [ -z "$COMPACT_PCT" ] || [ -z "$THINKING" ]; then
  CONTEXT_WINDOW=0; TIER=unknown; COMPACT_PCT=0; THINKING=false; STATUS=unknown
fi

# ── Output env vars ──────────────────────────────────────────────────────────
echo "export SAVIA_CONTEXT_WINDOW=${CONTEXT_WINDOW}"
echo "export SAVIA_MODEL_TIER=${TIER}"
echo "export SAVIA_COMPACT_THRESHOLD=${COMPACT_PCT}"
echo "export SAVIA_SUPPORTS_THINKING=${THINKING}"
echo "export SAVIA_DETECTED_MODEL=${QUALIFIED_MODEL}"
echo "export SAVIA_MODEL_PROVIDER=${PROVIDER}"
echo "export SAVIA_MODEL_ID=${MODEL_ID}"
echo "export SAVIA_MODEL_METADATA_STATUS=${STATUS}"
