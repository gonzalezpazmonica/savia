#!/bin/bash
set -uo pipefail
# token-estimator.sh — Estimate token cost before execution
# Usage: token-estimator.sh [file|dir] [--budget N] [--model MODEL] [--provider copilot|anthropic|deepseek]
#
# Token estimation: chars / 4 (industry standard approximation)
# Providers: copilot (GitHub Copilot, flat-fee) / anthropic (Claude API) / deepseek (DeepSeek V4)
# Pricing source: anthropic.com/pricing, api-docs.deepseek.com/quick_start/pricing/

TARGET="${1:-.}"
BUDGET=""
MODEL="opus-4.7"
PROVIDER="copilot"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

# === Pricing per 1M tokens (USD) ===
# Format: INPUT_MISS / INPUT_CACHE_HIT / OUTPUT
#
# DeepSeek V4 — pricing at 2026-05-02
#   v4-pro: 75% discount extended until 2026-05-31 15:59 UTC
#   v4-flash: base price (no discount)
#
# Anthropic — April 2026 list prices
#   opus/sonnet/haiku: no cache-hit discounts documented

declare -A PRICE_INPUT_MISS
declare -A PRICE_INPUT_HIT
declare -A PRICE_OUTPUT

# DeepSeek V4 (current pricing, 2026-05-02)
PRICE_INPUT_MISS[v4-pro]=0.435       # $1.74 base, 75% off
PRICE_INPUT_HIT[v4-pro]=0.003625     # $0.0145 base, 75% off
PRICE_OUTPUT[v4-pro]=0.87            # $3.48 base, 75% off
PRICE_INPUT_MISS[v4-flash]=0.14
PRICE_INPUT_HIT[v4-flash]=0.0028
PRICE_OUTPUT[v4-flash]=0.28

# Anthropic Claude (April 2026)
PRICE_INPUT_MISS[opus]=15.00
PRICE_INPUT_HIT[opus]=15.00
PRICE_OUTPUT[opus]=75.00
PRICE_INPUT_MISS[sonnet]=3.00
PRICE_INPUT_HIT[sonnet]=3.00
PRICE_OUTPUT[sonnet]=15.00
PRICE_INPUT_MISS[haiku]=0.80
PRICE_INPUT_HIT[haiku]=0.80
PRICE_OUTPUT[haiku]=4.00

# GitHub Copilot (flat-fee subscription, no per-token billing)
# Cost is informational only — the actual cost is the monthly subscription.
PRICE_INPUT_MISS[opus-4.7]=0
PRICE_INPUT_HIT[opus-4.7]=0
PRICE_OUTPUT[opus-4.7]=0
PRICE_INPUT_MISS[sonnet-4.5]=0
PRICE_INPUT_HIT[sonnet-4.5]=0
PRICE_OUTPUT[sonnet-4.5]=0

INPUT_COST=${PRICE_INPUT_MISS[$MODEL]:-${PRICE_INPUT_MISS[opus-4.7]}}
OUTPUT_COST=${PRICE_OUTPUT[$MODEL]:-${PRICE_OUTPUT[opus-4.7]}}
CACHE_COST=${PRICE_INPUT_HIT[$MODEL]:-$INPUT_COST}

# Auto-detect provider from model name if not specified
if [[ "$PROVIDER" == "copilot" ]] && [[ "$MODEL" =~ ^(opus|sonnet|haiku)$ ]]; then
  PROVIDER="anthropic"
elif [[ "$PROVIDER" == "copilot" ]] && [[ "$MODEL" =~ ^v4 ]]; then
  PROVIDER="deepseek"
fi

# Usually: output_tokens ~ 0.3 * input_tokens (heuristic)
OUTPUT_RATIO=0.3

estimate_tokens() {
  local file="$1"
  local chars
  chars=$(wc -c < "$file" 2>/dev/null || echo 0)
  echo $(( chars / 4 ))
}

calc_cost() {
  local tokens=$1
  local in_cost=$2
  local out_cost=$3
  local out_tokens
  out_tokens=$(awk "BEGIN {printf \"%.0f\", $tokens * $OUTPUT_RATIO}")
  awk "BEGIN {printf \"%.4f\", ($tokens * $in_cost + $out_tokens * $out_cost) / 1000000}"
}

calc_effort() {
  local tokens=$1
  local out_tokens
  out_tokens=$(awk "BEGIN {printf \"%.0f\", $tokens * $OUTPUT_RATIO}")
  # Agent reads ~500 t/s (with thinking), generates ~100 t/s
  # Effort (min) = (input/500 + output/100) / 60
  awk "BEGIN {printf \"%.1f\", ($tokens / 500 + $out_tokens / 100) / 60}"
}

# === Single file ===
if [[ -f "$TARGET" ]]; then
  TOKENS=$(estimate_tokens "$TARGET")
  COST=$(calc_cost "$TOKENS" "$INPUT_COST" "$OUTPUT_COST")
  CACHE_COST_VAL=$(calc_cost "$TOKENS" "$CACHE_COST" "$OUTPUT_COST")
  EFFORT=$(calc_effort "$TOKENS")
  echo "File:       $TARGET"
  echo "Chars:      $(wc -c < "$TARGET")"
  echo "Est.tokens: $TOKENS (~$((TOKENS * 4)) chars)"
  echo "Provider:   $PROVIDER | Model: $MODEL"
  echo "Agent time: ~${EFFORT} min"
  echo "Cost (cache miss):  \$${COST}"
  echo "Cost (cache hit):   \$${CACHE_COST_VAL}"
  if [[ -n "$BUDGET" ]] && [[ "$TOKENS" -gt "$BUDGET" ]]; then
    echo "WARNING: exceeds budget of $BUDGET tokens by $((TOKENS - BUDGET))"
    exit 1
  fi
  exit 0
fi

# === Directory — aggregate ===
if [[ -d "$TARGET" ]]; then
  TOTAL_TOKENS=0
  TOTAL_FILES=0
  MAX_FILE=""
  MAX_TOKENS=0

  while IFS= read -r -d '' file; do
    tokens=$(estimate_tokens "$file")
    TOTAL_TOKENS=$((TOTAL_TOKENS + tokens))
    TOTAL_FILES=$((TOTAL_FILES + 1))
    if [[ "$tokens" -gt "$MAX_TOKENS" ]]; then
      MAX_TOKENS=$tokens
      MAX_FILE="$file"
    fi
  done < <(find "$TARGET" -maxdepth 3 -type f \( -name "*.md" -o -name "*.sh" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.ts" -o -name "*.py" -o -name "*.cs" -o -name "*.go" -o -name "*.rs" \) -print0 2>/dev/null)

  COST=$(calc_cost "$TOTAL_TOKENS" "$INPUT_COST" "$OUTPUT_COST")
  CACHE_COST_VAL=$(calc_cost "$TOTAL_TOKENS" "$CACHE_COST" "$OUTPUT_COST")
  EFFORT=$(calc_effort "$TOTAL_TOKENS")
  AVG=$((TOTAL_FILES > 0 ? TOTAL_TOKENS / TOTAL_FILES : 0))

  echo "Directory:  $TARGET"
  echo "Files:       $TOTAL_FILES"
  echo "Total est.tokens: $TOTAL_TOKENS"
  echo "Avg tokens/file:  $AVG"
  echo "Largest:    $(basename "$MAX_FILE") ($MAX_TOKENS tokens)"
  echo "Provider:   $PROVIDER | Model: $MODEL"
  echo "Agent time: ~${EFFORT} min"
  echo "Cost (cache miss): \$${COST}"
  if [[ "$(awk "BEGIN {print ($CACHE_COST < $INPUT_COST) ? 1 : 0}")" -eq 1 ]]; then
    echo "Cost (cache hit):  \$${CACHE_COST_VAL}"
  fi

  if [[ -n "$BUDGET" ]] && [[ "$TOTAL_TOKENS" -gt "$BUDGET" ]]; then
    OVER=$((TOTAL_TOKENS - BUDGET))
    echo "WARNING: exceeds budget of $BUDGET tokens by $OVER"
    echo "Suggestion: load only the top files needed, not the full directory"
    exit 1
  fi
  exit 0
fi

echo "Error: $TARGET not found" >&2
exit 2
