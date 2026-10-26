#!/usr/bin/env bash
# rule-usage-analyzer.sh — Analyze domain rule usage across the workspace
# Outputs JSON manifest mapping rules to their consumers.
# Usage: ./scripts/rule-usage-analyzer.sh [--root DIR] [--output FILE] [--summary]
# ─────────────────────────────────────────────────────────────────────
set -uo pipefail
cat /dev/stdin > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
RULES_DIR="${ROOT}/docs/rules/domain"
OUTPUT_FILE=""
SUMMARY_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ -n "${2:-}" && -d "$2" ]] || { echo "ERROR: --root requiere un directorio existente" >&2; exit 2; }
      ROOT="$2"; RULES_DIR="${ROOT}/docs/rules/domain"; shift 2 ;;
    --output)
      [[ -n "${2:-}" ]] || { echo "ERROR: --output requiere una ruta" >&2; exit 2; }
      OUTPUT_FILE="$2"; shift 2 ;;
    --summary) SUMMARY_ONLY=true; shift ;;
    *) shift ;;
  esac
done

# ── Collect all rule files ──
mapfile -t RULES < <(ls "$RULES_DIR"/*.md 2>/dev/null | sort)
TOTAL=${#RULES[@]}

# ── Tier 1: Referenced from CLAUDE.md (loaded at startup) ──
mapfile -t TIER1 < <(
  grep -oP '@docs/rules/domain/[a-z0-9_-]+\.md' "$ROOT/CLAUDE.md" 2>/dev/null \
    | sed 's|@docs/rules/domain/||' | sort -u
)

# ── Tier 2: Referenced from commands, skills, agents (on-demand) ──
mapfile -t TIER2 < <(
  grep -roP '@docs/rules/domain/[a-z0-9_-]+\.md' \
    "$ROOT/.opencode/commands/" "$ROOT/.opencode/skills/" "$ROOT/.opencode/agents/" 2>/dev/null \
    | sed 's|.*@docs/rules/domain/||' | sort -u
)

# ── Build maps ──
declare -A TIER_MAP
for r in "${TIER1[@]}"; do TIER_MAP["$r"]="tier1"; done
for r in "${TIER2[@]}"; do
  [[ -z "${TIER_MAP[$r]:-}" ]] && TIER_MAP["$r"]="tier2"
done

tier1_count=0
tier2_count=0
dormant_count=0

for rule_path in "${RULES[@]}"; do
  rule=$(basename "$rule_path")
  if [[ -z "${TIER_MAP[$rule]:-}" ]]; then
    TIER_MAP["$rule"]="dormant"
    dormant_count=$((dormant_count + 1))
  elif [[ "${TIER_MAP[$rule]}" == "tier1" ]]; then
    tier1_count=$((tier1_count + 1))
  elif [[ "${TIER_MAP[$rule]}" == "tier2" ]]; then
    tier2_count=$((tier2_count + 1))
  fi
done

if $SUMMARY_ONLY; then
  echo "Rules: $TOTAL total | $tier1_count tier1 | $tier2_count tier2 | $dormant_count dormant"
  exit 0
fi

# ── Generate JSON manifest ──
# --output FILE: el manifiesto va al fichero (antes se aceptaba y se ignoraba).
[[ -n "$OUTPUT_FILE" ]] && exec > "$OUTPUT_FILE"
echo "{"
echo "  \"generated\": \"$(date -Iseconds)\","
echo "  \"total\": $TOTAL,"
echo "  \"tier1_count\": $tier1_count,"
echo "  \"tier2_count\": $tier2_count,"
echo "  \"dormant_count\": $dormant_count,"
echo "  \"rules\": {"

first=true
for rule_path in "${RULES[@]}"; do
  rule=$(basename "$rule_path")
  tier="${TIER_MAP[$rule]:-dormant}"
  $first && first=false || echo ","
  # Find consumers
  consumers=$(grep -rl "@docs/rules/domain/${rule}" \
    "$ROOT/CLAUDE.md" "$ROOT/.opencode/commands/" "$ROOT/.opencode/skills/" "$ROOT/.opencode/agents/" 2>/dev/null \
    | sed "s|${ROOT}/||g" | sort -u | tr '\n' ',' | sed 's/,$//')
  printf '    "%s": {"tier": "%s", "consumers": "%s"}' "$rule" "$tier" "$consumers"
done

echo ""
echo "  }"
echo "}"
