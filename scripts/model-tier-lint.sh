#!/usr/bin/env bash
# model-tier-lint.sh — Guard for provider-agnostic model tiers (SPEC-127 / PV-06).
#
# Sources (agents, commands, skills, opencode.json) declare `model_tier:
# heavy|mid|fast`. Concrete models live ONLY in the local tier definition
# (~/.savia/preferences.yaml → tiers.<frontend>.<tier>), resolved at runtime:
#   - Claude Code: .claude/hooks/model-tier-inject.sh
#   - OpenCode:    .opencode/plugins/savia-foundation.ts (config hook)
#   - scripts:     savia_resolve_model (scripts/savia-env.sh)
#
# Fails when a source frontmatter carries `model:` (any value) or an invalid
# `model_tier:`, or when opencode.json pins an agent `model`.
#
# Usage: bash scripts/model-tier-lint.sh [--quiet]
# Exit: 0 clean · 1 violations found
set -uo pipefail

ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

ROOT="$ROOT" QUIET="$QUIET" python3 - <<'PY'
import glob, json, os, re, sys

root = os.environ["ROOT"]
quiet = os.environ["QUIET"] == "true"
fm_rx = re.compile(r"^---\r?\n(.*?)\r?\n---", re.S)
violations = []

patterns = [".claude/agents/*.md", ".opencode/agents/*.md", ".claude/commands/*.md",
            ".claude/skills/*/SKILL.md"]
for pattern in patterns:
    for path in sorted(glob.glob(os.path.join(root, pattern))):
        with open(path, encoding="utf-8", errors="replace") as fh:
            m = fm_rx.match(fh.read())
        if not m:
            continue
        rel = os.path.relpath(path, root)
        for line in m.group(1).splitlines():
            if re.match(r"^model:", line):
                violations.append(f"{rel}: '{line.strip()}' → usa 'model_tier: heavy|mid|fast'")
            t = re.match(r"^model_tier:\s*(\S*)", line)
            if t and t.group(1) not in ("heavy", "mid", "fast"):
                violations.append(f"{rel}: model_tier inválido '{t.group(1)}'")

oc = os.path.join(root, "opencode.json")
if os.path.isfile(oc):
    cfg = json.load(open(oc, encoding="utf-8"))
    if "model" in cfg or "small_model" in cfg:
        violations.append("opencode.json: 'model'/'small_model' pertenece a la config local del usuario")
    for name, agent in (cfg.get("agent") or {}).items():
        if isinstance(agent, dict) and "model" in agent:
            violations.append(f"opencode.json: agent.{name}.model='{agent['model']}' → usa model_tier")

if violations:
    if not quiet:
        print("FAIL: modelos concretos en fuentes versionadas (deben ir en la definición local de tiers)")
        for v in violations:
            print("  " + v)
    else:
        print(f"FAIL: {len(violations)} violaciones de model tiers")
    sys.exit(1)
if not quiet:
    print("PASS: todas las fuentes declaran model_tier; sin modelos de proveedor")
PY
