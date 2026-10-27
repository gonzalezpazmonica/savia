#!/bin/bash
set -uo pipefail

# validate-agent-permissions.sh — Verify agent permission_level matches tools
# Usage: validate-agent-permissions.sh [AGENTS_DIR] [--verbose] [--baseline FILE]
# Returns: 0 if all match, 1 if errors found
#
# The level is a MAXIMUM (agent-permission-levels.md):
#   - a tool ABOVE the level (excess)  -> ERROR, exit 1
#   - a tool of the level not declared -> WARNING (fewer tools is allowed)
# Known excesses pending an operator decision live in a TRANSIENT baseline
# (one "agent tool owner YYYY-MM-DD" entry per line). Listed pairs are
# reported as BASELINE, not errors, only until their expiry date; after it the
# entry stops absorbing and the excess fails. An entry without owner or a valid
# date is an error, and a listed pair that is no longer an excess is a STALE
# error, so the baseline can only shrink. The default baseline applies only to
# the repo's own .claude/agents; other dirs need --baseline explicitly.
# AGENT_PERMS_TODAY (YYYY-MM-DD) moves today's date FORWARD (tests); an
# invalid or past date is an error, so it can never extend an expiry.
#
# Frontmatter is parsed as real YAML (python3 + PyYAML, fail-closed if absent).
# Fail-closed cases (ERROR): unparseable frontmatter, duplicate keys, missing
# `tools:` (the agent inherits every tool), tool values that are not
# true/false, and a missing AGENTS_DIR. An agent without permission_level
# warns and is held to L0, so dropping the level cannot hide an excess.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_BASELINE="$REPO_ROOT/docs/agent-permissions-excess-baseline.txt"

AGENTS_DIR=""
VERBOSE=0
BASELINE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose) VERBOSE=1 ;;
    --baseline)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "ERROR: --baseline needs a file" >&2
        exit 2
      fi
      BASELINE="$2"; shift ;;
    *) [[ -z "$AGENTS_DIR" ]] && AGENTS_DIR="$1" ;;
  esac
  shift
done
AGENTS_DIR="${AGENTS_DIR:-.claude/agents}"

if [[ ! -d "$AGENTS_DIR" ]]; then
  echo "ERROR: agents directory not found: $AGENTS_DIR"
  echo ""
  echo "Agent Permission Validation"
  echo "==========================="
  echo "  Checked: 0 agents"
  echo "  Errors:  1"
  exit 1
fi
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "ERROR: python3 with PyYAML is required to parse agent frontmatter"
  exit 1
fi

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

TODAY="$(date +%F)"
if [[ -n "${AGENT_PERMS_TODAY:-}" ]]; then
  if [[ ! "$AGENT_PERMS_TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
     || [[ "$(date -d "$AGENT_PERMS_TODAY" +%F 2>/dev/null)" != "$AGENT_PERMS_TODAY" ]]; then
    echo "ERROR: AGENT_PERMS_TODAY='$AGENT_PERMS_TODAY' is not a valid YYYY-MM-DD date"
    ERRORS=$((ERRORS + 1))
  elif [[ "$AGENT_PERMS_TODAY" < "$TODAY" ]]; then
    echo "ERROR: AGENT_PERMS_TODAY=$AGENT_PERMS_TODAY is before today ($TODAY); it may only move the date forward"
    ERRORS=$((ERRORS + 1))
  else
    echo "NOTE: AGENT_PERMS_TODAY override in effect: $AGENT_PERMS_TODAY"
    TODAY="$AGENT_PERMS_TODAY"
  fi
fi
declare -A BASE_PAIRS
declare -A BASE_EXPIRES
declare -A SEEN_PAIRS
if [[ -n "$BASELINE" ]]; then
  if [[ ! -f "$BASELINE" ]]; then
    echo "ERROR: baseline file not found: $BASELINE"
    ERRORS=$((ERRORS + 1))
  else
    while read -r b_agent b_tool b_owner b_expires _ || [[ -n "${b_agent:-}" ]]; do
      [[ -z "$b_agent" || "$b_agent" == \#* ]] && continue
      if [[ -z "$b_tool" || -z "$b_owner" || ! "$b_expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
         || [[ "$(date -d "$b_expires" +%F 2>/dev/null)" != "$b_expires" ]]; then
        echo "ERROR: malformed baseline entry '$b_agent ${b_tool:-?}' — needs 'agent tool owner YYYY-MM-DD' (owner and expiry are mandatory)"
        ERRORS=$((ERRORS + 1))
        continue
      fi
      if [[ -n "${BASE_PAIRS["$b_agent $b_tool"]:-}" ]]; then
        echo "ERROR: duplicate baseline entry '$b_agent $b_tool'"
        ERRORS=$((ERRORS + 1))
        continue
      fi
      BASE_PAIRS["$b_agent $b_tool"]=1
      BASE_EXPIRES["$b_agent $b_tool"]="$b_expires"
    done < "$BASELINE"
  fi
fi

# parse_agents FILE... — one line per agent, fields split by \x1f (US), parsed as real YAML:
#   OK <name> <level|""> <tool tool ...>   (tools canonical; "*" = no tools:
#                                           key, the agent inherits all tools)
#   ERR <name> <reason>                    (fail-closed: counted as an error)
# Supports inline/flow lists, block lists (indented or not), comma strings and
# maps whose values are booleans (true/yes/!!bool); any other value is ERR.
parse_agents() {
  python3 - "$@" <<'PY'
import os, re, sys, yaml

CANON = {t.lower(): t for t in ("Read", "Write", "Edit", "Bash", "Glob", "Grep",
         "Task", "MultiEdit", "WebFetch", "WebSearch", "Skill", "NotebookEdit")}

class UniqueLoader(yaml.SafeLoader):
    pass

def unique_mapping(loader, node, deep=False):
    keys = set()
    for k, _ in node.value:
        key = loader.construct_object(k, deep=deep)
        if key in keys:
            raise yaml.constructor.ConstructorError(None, None, "duplicate key %r" % (key,), k.start_mark)
        keys.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)

def canon(t):
    t = re.sub(r"\s+", "_", t.strip())
    return CANON.get(t.lower(), t)

def tools_of(v):
    if v is None:
        return ["*"]
    if isinstance(v, str):
        return [canon(x) for x in v.split(",") if x.strip()] or ["*"]
    if isinstance(v, list):
        if not all(isinstance(x, str) for x in v):
            raise ValueError("tools list holds a non-string item")
        return [canon(x) for x in v if x.strip()]
    if isinstance(v, dict):
        out = []
        for k, on in v.items():
            if not isinstance(on, bool):
                raise ValueError("tools map value for %r is not true/false" % (k,))
            if on:
                out.append(canon(str(k)))
        return out
    raise ValueError("tools has unsupported type %s" % type(v).__name__)

for path in sys.argv[1:]:
    name = os.path.basename(path)[:-3]
    try:
        text = open(path, encoding="utf-8-sig").read().replace("\r\n", "\n")
        m = re.match(r"---\n(.*?)\n---[ \t]*(\n|$)", text, re.S)
        if not m:
            raise ValueError("no frontmatter block at the start of the file")
        doc = yaml.load(m.group(1), Loader=UniqueLoader)
        if not isinstance(doc, dict):
            raise ValueError("frontmatter is not a mapping")
        level = doc.get("permission_level")
        level = "" if level is None else str(level).strip()
        tools = tools_of(doc["tools"]) if "tools" in doc else ["*"]
        print("OK\x1f%s\x1f%s\x1f%s" % (name, level, " ".join(tools)))
    except Exception as e:
        reason = " ".join(str(e).split())
        print("ERR\x1f%s\x1f%s" % (name, reason or type(e).__name__))
PY
}

shopt -s nullglob
AGENT_FILES=("$AGENTS_DIR"/*.md)
shopt -u nullglob

while IFS=$'\x1f' read -r p_status agent_name p_level p_tools; do
  CHECKED=$((CHECKED + 1))

  if [[ "$p_status" != "OK" ]]; then
    echo "ERROR: $agent_name — unparseable frontmatter: $p_level"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  level="$p_level"
  if [[ -z "$level" ]]; then
    WARNINGS=$((WARNINGS + 1))
    if [[ $VERBOSE -eq 1 ]]; then
      echo "WARN: $agent_name — no permission_level in frontmatter (held to L0)"
    fi
    level="L0"
  fi

  expected="${LEVEL_TOOLS[$level]:-}"

  if [[ -z "$expected" ]]; then
    echo "ERROR: $agent_name — unknown level: $level"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  if [[ " $p_tools " == *" * "* ]]; then
    echo "ERROR: $agent_name ($level) — no tools: list, the agent inherits every tool"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  read -ra tool_list <<< "$p_tools"
  tools_clean=" ${tool_list[*]} "

  # Missing: a tool of the level not declared (allowed, warning only)
  for tool in $expected; do
    if [[ "$tools_clean" != *" $tool "* ]]; then
      if [[ $VERBOSE -eq 1 ]]; then
        echo "WARN: $agent_name ($level) — missing tool: $tool"
      fi
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  # Excess: a declared tool above the level (error unless baselined)
  for tool in "${tool_list[@]}"; do
    [[ " $expected " == *" $tool "* ]] && continue
    pair="$agent_name $tool"
    if [[ -n "${BASE_PAIRS[$pair]:-}" ]]; then
      SEEN_PAIRS["$pair"]=1
      if [[ "${BASE_EXPIRES[$pair]}" < "$TODAY" ]]; then
        echo "ERROR: $agent_name ($level) — excess tool: $tool (baseline entry expired ${BASE_EXPIRES[$pair]}; decide: raise the level or drop the tool)"
        ERRORS=$((ERRORS + 1))
        continue
      fi
      BASELINED=$((BASELINED + 1))
      if [[ $VERBOSE -eq 1 ]]; then
        echo "BASELINE: $agent_name ($level) — excess tool: $tool (pending decision)"
      fi
    else
      echo "ERROR: $agent_name ($level) — excess tool: $tool (above level)"
      ERRORS=$((ERRORS + 1))
    fi
  done
done < <( ((${#AGENT_FILES[@]})) && parse_agents "${AGENT_FILES[@]}" )

# The parser must answer for every file, or the run is not a full validation
if [[ $CHECKED -ne ${#AGENT_FILES[@]} ]]; then
  echo "ERROR: parsed $CHECKED of ${#AGENT_FILES[@]} agent files"
  ERRORS=$((ERRORS + 1))
fi

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
