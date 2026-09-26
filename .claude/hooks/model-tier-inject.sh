#!/usr/bin/env bash
set -uo pipefail
# model-tier-inject.sh — Claude Code adapter for provider-agnostic model tiers
# SPEC: SPEC-127 (model-alias-schema.md) · PV-06 cero vendor lock-in
# opencode-binding: NOT_EXPOSED — OpenCode resolves model_tier in the savia-foundation plugin config hook
#
# Agents declare `model_tier: heavy|mid|fast` (never a vendor model). Claude Code
# only accepts its own selectors in the Agent tool `model` parameter, so this
# PreToolUse hook reads the agent's tier and injects the selector declared in the
# LOCAL tier definition (~/.savia/preferences.yaml):
#
#   tiers:
#     claude-code:
#       heavy: opus
#       mid: sonnet
#       fast: haiku
#
# Default when the local definition lacks a tier: heavy→opus, mid→sonnet,
# fast→haiku (Claude Code's own selectors). Never falls back to top-level
# model_<tier>: those belong to other providers.
# An explicit per-invocation `model` always wins. Never blocks (exit 0).
# Master switch: SAVIA_MODEL_TIER_INJECT=off

[[ "${SAVIA_MODEL_TIER_INJECT:-on}" == "off" ]] && exit 0

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(timeout 3 cat 2>/dev/null) || true
fi
[[ -z "$INPUT" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PREFS_FILE="${SAVIA_PREFS_FILE:-$HOME/.savia/preferences.yaml}"

HOOK_INPUT="$INPUT" PROJECT_DIR="$PROJECT_DIR" PREFS_FILE="$PREFS_FILE" python3 - <<'PY' || true
import json, os, re, sys

VALID = {"opus", "sonnet", "haiku", "fable"}
DEFAULTS = {"heavy": "opus", "mid": "sonnet", "fast": "haiku"}

try:
    data = json.loads(os.environ["HOOK_INPUT"])
except ValueError:
    sys.exit(0)
if data.get("tool_name") not in ("Agent", "Task"):
    sys.exit(0)
tool_input = data.get("tool_input") or {}
agent = tool_input.get("subagent_type") or ""
if tool_input.get("model") or not re.fullmatch(r"[\w.-]+", agent):
    sys.exit(0)

def agent_tier(name):
    for base in (os.path.join(os.environ["PROJECT_DIR"], ".claude", "agents"),
                 os.path.expanduser("~/.claude/agents")):
        try:
            raw = open(os.path.join(base, name + ".md"), encoding="utf-8").read()
        except OSError:
            continue
        fm = re.match(r"^---\r?\n(.*?)\r?\n---", raw, re.S)
        m = fm and re.search(r"^model_tier:\s*(heavy|mid|fast)\s*$", fm.group(1), re.M)
        return m.group(1) if m else None
    return None

def local_selector(tier, frontend="claude-code"):
    try:
        lines = open(os.environ["PREFS_FILE"], encoding="utf-8").read().splitlines()
    except OSError:
        return None
    in_tiers = in_frontend = False
    for line in lines:
        if re.match(r"^\s*(#|$)", line):
            continue
        top = re.match(r"^([\w-]+)\s*:", line)
        if top:
            in_tiers, in_frontend = top.group(1) == "tiers", False
            continue
        if not in_tiers:
            continue
        fe = re.match(r"^ {2}([\w-]+)\s*:\s*$", line)
        if fe:
            in_frontend = fe.group(1) == frontend
            continue
        t = re.match(r"^ {4}(heavy|mid|fast)\s*:\s*(.+)$", line)
        if t and in_frontend and t.group(1) == tier:
            return re.sub(r"\s+#.*$", "", t.group(2)).strip().strip("\"'")
    return None

tier = agent_tier(agent)
if not tier:
    sys.exit(0)
selector = local_selector(tier)
if selector and selector not in VALID:
    print(f"[model-tier-inject] tiers.claude-code.{tier}={selector!r} no es un selector de Claude Code "
          f"({'|'.join(sorted(VALID))}); se usa el default {DEFAULTS[tier]}", file=sys.stderr)
    selector = None
selector = selector or DEFAULTS[tier]

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": {**tool_input, "model": selector},
}}))
PY
exit 0
