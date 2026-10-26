#!/usr/bin/env bash
set -euo pipefail
# scripts/doc-counts-check.sh — SE-253 Slice 5
# Verifica que los counts declarados en docs coincidan con los reales en disco.
#
# Usage:
#   bash scripts/doc-counts-check.sh [--check|--warn|--fix]
#   --check  Exit 1 si algún count difiere (default CI mode)
#   --warn   Exit 0 pero imprime diferencias (default)
#   --fix    Actualiza los números en los docs (solo números, no texto)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:---warn}"

case "$MODE" in
  --check|--warn|--fix) ;;
  *) echo "ERROR: unknown mode '$MODE' (use --check, --warn or --fix)" >&2; exit 2 ;;
esac

HOOKS_STRATEGY="$REPO_ROOT/.opencode/HOOKS-STRATEGY.md"
SETTINGS="$REPO_ROOT/.claude/settings.json"
AGENTS_DIR="$REPO_ROOT/.opencode/agents"

errors=0

# ── Count hooks in settings.json ──────────────────────────────────────────
# ── Count hooks — two metrics ─────────────────────────────────────────────
# HOOKS-STRATEGY.md refers to .sh files in .claude/hooks/, not settings.json registrations
real_hooks=$(ls "$REPO_ROOT/.claude/hooks/"*.sh 2>/dev/null | wc -l || true)
real_registrations=$(python3 -c "
import json, sys
d = json.load(open('$SETTINGS'))
total = sum(len(v) for v in d.get('hooks', {}).values() if isinstance(v, list))
print(total)
" 2>/dev/null || echo "0")

# ── Count declared hooks in HOOKS-STRATEGY.md ─────────────────────────────
if [[ -f "$HOOKS_STRATEGY" ]]; then
  # Look for patterns like "N hooks" or "N registered hooks"
  declared_hooks=$(grep -oE '[0-9]+ (registered )?hooks' "$HOOKS_STRATEGY" 2>/dev/null \
    | grep -oE '[0-9]+' | head -1 || echo "unknown")
else
  declared_hooks="unknown"
fi

if [[ "$declared_hooks" != "unknown" ]]; then
  diff_hooks=$(( real_hooks - declared_hooks ))
  diff_abs=${diff_hooks#-}
  if [[ "$diff_abs" -gt 2 ]]; then
    echo "DIFF: HOOKS-STRATEGY.md declares $declared_hooks hooks, disk has $real_hooks (diff: $diff_hooks)"
    if [[ "$MODE" == "--fix" ]]; then
      sed -i -E "0,/[0-9]+ (registered )?hooks/s//${real_hooks} \1hooks/" "$HOOKS_STRATEGY"
      echo "FIXED: HOOKS-STRATEGY.md now declares $real_hooks hooks"
    else
      errors=1
    fi
  else
    echo "OK: hooks count — declared=$declared_hooks real=$real_hooks (within tolerance ±2)"
  fi
fi

# ── Count agents ──────────────────────────────────────────────────────────
real_agents=$(find "$AGENTS_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)

# Check AGENTS.md if exists
agents_md="$REPO_ROOT/AGENTS.md"
if [[ -f "$agents_md" ]]; then
  declared_agents=$(grep -oE '[0-9]+ agents' "$agents_md" 2>/dev/null \
    | grep -oE '[0-9]+' | head -1 || echo "unknown")
  if [[ "$declared_agents" != "unknown" ]]; then
    diff_agents=$(( real_agents - declared_agents ))
    diff_abs_a=${diff_agents#-}
    if [[ "$diff_abs_a" -gt 2 ]]; then
      echo "DIFF: AGENTS.md declares $declared_agents agents, disk has $real_agents (diff: $diff_agents)"
      if [[ "$MODE" == "--fix" ]]; then
        sed -i -E "0,/[0-9]+ agents/s//${real_agents} agents/" "$agents_md"
        echo "FIXED: AGENTS.md now declares $real_agents agents"
      else
        errors=1
      fi
    else
      echo "OK: agents count — declared=$declared_agents real=$real_agents (within tolerance ±2)"
    fi
  fi
fi

# ── Result ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "--check" && "$errors" -gt 0 ]]; then
  exit 1
fi

exit 0
