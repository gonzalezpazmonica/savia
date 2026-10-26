#!/bin/bash
set -uo pipefail

# validate-agent-permissions.sh — Verify agent permission_level matches tools
# Usage: validate-agent-permissions.sh [AGENTS_DIR] [--verbose] [--baseline FILE]
# Returns: 0 if all match, 1 if errors found
#
# The level is a MAXIMUM (agent-permission-levels.md):
#   - a tool ABOVE the level (excess)  -> ERROR, exit 1
#   - a tool of the level not declared -> WARNING (fewer tools is allowed)
# Known excesses pending an operator decision live in a ratchet baseline
# (one "agent tool" pair per line). Listed pairs are reported as BASELINE,
# not errors; a listed pair that is no longer an excess is a STALE error,
# so the baseline can only shrink. The default baseline applies only to the
# repo's own .claude/agents; other dirs need --baseline explicitly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_BASELINE="$REPO_ROOT/docs/agent-permissions-excess-baseline.txt"

AGENTS_DIR=""
VERBOSE=0
BASELINE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=1 ;;
    --baseline) BASELINE="${2:-}"; shift ;;
    *) [[ -z "$AGENTS_DIR" ]] && AGENTS_DIR="$1" ;;
  esac
  shift
done
AGENTS_DIR="${AGENTS_DIR:-.claude/agents}"

if [[ -z "$BASELINE" && -d "$AGENTS_DIR" ]]; then
  if [[ "$(cd "$AGENTS_DIR" && pwd -P)" == "$(cd "$REPO_ROOT/.claude/agents" 2>/dev/null && pwd -P)" ]]; then
    BASELINE="$DEFAULT_BASELINE"
  fi
fi

ERRORS=0
WARNINGS=0
CHECKED=0
BASELINED=0

# Define expected tools per level
declare -A LEVEL_TOOLS
LEVEL_TOOLS[L0]="Read Glob Grep"
LEVEL_TOOLS[L1]="Read Glob Grep Bash"
LEVEL_TOOLS[L2]="Read Write Edit Glob Grep"
LEVEL_TOOLS[L3]="Read Write Edit Bash Glob Grep"
LEVEL_TOOLS[L4]="Read Write Edit Bash Glob Grep Task"

declare -A BASE_PAIRS
declare -A SEEN_PAIRS
if [[ -n "$BASELINE" && -f "$BASELINE" ]]; then
  while read -r b_agent b_tool _; do
    [[ -z "$b_agent" || "$b_agent" == \#* ]] && continue
    BASE_PAIRS["$b_agent $b_tool"]=1
  done < "$BASELINE"
fi

# extract_tools FILE — print the agent's enabled tools, one per line.
# Reads only the `tools:` key of the first frontmatter block and supports
# inline lists ([A, B]), block lists (- A) and maps (a: true / a: false).
extract_tools() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    !fm { exit }
    /^tools:/ {
      v = $0; sub(/^tools:[ \t]*/, "", v)
      if (v != "") { gsub(/[][",'"'"']/, " ", v); n = split(v, a, /[ \t]+/); for (i = 1; i <= n; i++) if (a[i] != "") print a[i]; exit }
      in_tools = 1; next
    }
    in_tools {
      if ($0 !~ /^[ \t]/) exit
      line = $0; gsub(/["'"'"']/, "", line)
      if (line ~ /^[ \t]*-[ \t]*/) { sub(/^[ \t]*-[ \t]*/, "", line); sub(/[ \t]+$/, "", line); if (line != "") print line; next }
      if (line ~ /:/) {
        k = line; sub(/:.*/, "", k); gsub(/[ \t]/, "", k)
        val = line; sub(/^[^:]*:[ \t]*/, "", val); sub(/[ \t]+$/, "", val)
        if (tolower(val) == "true") print k
      }
    }
  ' "$1"
}

# canonical_tool NAME — map lower-case map keys (read, bash) to tool names.
canonical_tool() {
  local t="$1"
  case "${t,,}" in
    read) echo Read ;; write) echo Write ;; edit) echo Edit ;; bash) echo Bash ;;
    glob) echo Glob ;; grep) echo Grep ;; task) echo Task ;;
    multiedit) echo MultiEdit ;; webfetch) echo WebFetch ;; websearch) echo WebSearch ;;
    skill) echo Skill ;;
    *) echo "$t" ;;
  esac
}

for agent_file in "$AGENTS_DIR"/*.md; do
  [[ -f "$agent_file" ]] || continue
  CHECKED=$((CHECKED + 1))

  agent_name=$(basename "$agent_file" .md)

  # Extract permission_level from frontmatter
  level=$(sed -n '/^---$/,/^---$/{ /^permission_level:/{ s/.*: *//; p; } }' "$agent_file")

  if [[ -z "$level" ]]; then
    WARNINGS=$((WARNINGS + 1))
    if [[ $VERBOSE -eq 1 ]]; then
      echo "WARN: $agent_name — no permission_level in frontmatter"
    fi
    continue
  fi

  expected="${LEVEL_TOOLS[$level]:-}"

  if [[ -z "$expected" ]]; then
    echo "ERROR: $agent_name — unknown level: $level"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  tools_clean=""
  while IFS= read -r raw; do
    [[ -n "$raw" ]] && tools_clean+="$(canonical_tool "$raw") "
  done < <(extract_tools "$agent_file")

  # Missing: a tool of the level not declared (allowed, warning only)
  for tool in $expected; do
    if [[ " $tools_clean " != *" $tool "* ]]; then
      if [[ $VERBOSE -eq 1 ]]; then
        echo "WARN: $agent_name ($level) — missing tool: $tool"
      fi
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  # Excess: a declared tool above the level (error unless baselined)
  for tool in $tools_clean; do
    [[ " $expected " == *" $tool "* ]] && continue
    pair="$agent_name $tool"
    if [[ -n "${BASE_PAIRS[$pair]:-}" ]]; then
      SEEN_PAIRS["$pair"]=1
      BASELINED=$((BASELINED + 1))
      if [[ $VERBOSE -eq 1 ]]; then
        echo "BASELINE: $agent_name ($level) — excess tool: $tool (pending decision)"
      fi
    else
      echo "ERROR: $agent_name ($level) — excess tool: $tool (above level)"
      ERRORS=$((ERRORS + 1))
    fi
  done
done

# Ratchet: every baseline entry must still be a real excess
for pair in "${!BASE_PAIRS[@]}"; do
  if [[ -z "${SEEN_PAIRS[$pair]:-}" ]]; then
    echo "ERROR: stale baseline entry '$pair' — no longer an excess, remove it from $BASELINE"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "Agent Permission Validation"
echo "==========================="
echo "  Checked: $CHECKED agents"
echo "  Errors:  $ERRORS"
echo "  Warnings: $WARNINGS"
echo "  Baselined excess: $BASELINED"

if [[ $ERRORS -gt 0 ]]; then
  exit 1
fi
exit 0
