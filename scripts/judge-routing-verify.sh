#!/usr/bin/env bash
set -uo pipefail
# judge-routing-verify.sh — SE-273 S1: CI parity check
#
# Verifies that every judge agent in .opencode/agents/ has a row
# in config/judge-routing.yaml. Fails CI if any judge is missing.
# Every routing row must point to an existing agent file (stale row = error).
#
# Usage: bash scripts/judge-routing-verify.sh [--strict]
#   --strict: also fail if any judge has mode=on-demand without rationale

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AGENTS_DIR="${ROOT}/.opencode/agents"
ROUTING="${ROOT}/config/judge-routing.yaml"
STRICT="${1:-}"

# ── Helpers ─────────────────────────────────────────────────────────────
red()  { echo -e "\033[31m$*\033[0m" >&2; }
green(){ echo -e "\033[32m$*\033[0m"; }
yellow(){ echo -e "\033[33m$*\033[0m" >&2; }

# ── Collect judge agents from filesystem ────────────────────────────────
# Non-judicial orchestrators (planning, not safety) excluded from parity
NON_JUDICIAL=("dev-orchestrator")

get_judge_agents() {
  find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' \
    | while read -r f; do
        bn=$(basename "$f" .md)
        # Match judges, orchestrators, and tribunals
        if [[ "$bn" =~ (-judge|-orchestrator|-tribunal)$ ]]; then
          # Skip known non-judicial orchestrators
          for nj in "${NON_JUDICIAL[@]}"; do
            [[ "$bn" == "$nj" ]] && continue 2
          done
          echo "$bn"
        fi
      done | LC_ALL=C sort
}

# ── Extract agent names from routing YAML ───────────────────────────────
get_routed_agents() {
  grep -E '^\s+- agent:' "$ROUTING" 2>/dev/null \
    | sed 's/.*agent:\s*//' \
    | LC_ALL=C sort -u
}

# ── Main ────────────────────────────────────────────────────────────────
echo "=== Judge Routing Parity Check (SE-273 S1) ==="
echo ""

[[ ! -f "$ROUTING" ]] && red "FATAL: $ROUTING not found" && exit 2
[[ ! -d "$AGENTS_DIR" ]] && red "FATAL: $AGENTS_DIR not found" && exit 2

mapfile -t judge_agents < <(get_judge_agents)
mapfile -t routed_agents < <(get_routed_agents)

errors=0
warnings=0

# Check 1: every filesystem judge has a routing row
for agent in "${judge_agents[@]}"; do
  found=false
  for routed in "${routed_agents[@]}"; do
    [[ "$agent" == "$routed" ]] && found=true && break
  done
  if ! $found; then
    red "MISSING ROW: $agent has no entry in $ROUTING"
    errors=$((errors + 1))
  fi
done

echo ""

# Check 2: every routing row has a corresponding agent file
for routed in "${routed_agents[@]}"; do
  found=false
  for agent in "${judge_agents[@]}"; do
    [[ "$agent" == "$routed" ]] && found=true && break
  done
  if ! $found; then
    # SE-527 S1: a row without an agent file is a dangling reference, not a warning.
    red "STALE ROW: $routed in routing but no agent file in $AGENTS_DIR"
    errors=$((errors + 1))
  fi
done

echo ""

# Check 3: retired (SE-527 S1). The two tombstoned framing judges were retired
# with their rows; any disabled row left behind is now caught by Check 2.

# Check 4 (strict mode): every on-demand judge has a rationale
if [[ "$STRICT" == "--strict" ]]; then
  while IFS= read -r line; do
    agent=$(echo "$line" | sed 's/.*agent:\s*//')
    has_rationale=$(grep -A20 "agent: $agent" "$ROUTING" | grep -c 'rationale:')
    if [[ "$has_rationale" -eq 0 ]]; then
      red "NO RATIONALE: $agent has no rationale field"
      errors=$((errors + 1))
    fi
  done < <(grep -B1 'mode: on-demand' "$ROUTING" | grep 'agent:')
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo "=== Summary ==="
echo "Filesystem judges: ${#judge_agents[@]}"
echo "Routed judges:     ${#routed_agents[@]}"
echo "Errors:            $errors"
echo "Warnings:          $warnings"

if [[ $errors -gt 0 ]]; then
  red "FAIL: $errors routing parity error(s)"
  exit 1
fi

green "PASS: all judges have documented routing policy"
exit 0
