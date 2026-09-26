#!/usr/bin/env bash
# skill-listing-overrides.sh — Project the SE-253 load tier into Claude Code's
# skill listing. Commands with `tier: extended` (low usage) are listed
# name-only via `skillOverrides`, so the listing budget keeps the descriptions
# of `core` commands and skills. Still invocable by name and from the / menu.
#
# Usage:
#   bash scripts/skill-listing-overrides.sh --apply   # rewrite skillOverrides in .claude/settings.json
#   bash scripts/skill-listing-overrides.sh --check   # exit 1 if settings.json is stale
# Ref: https://code.claude.com/docs/en/skills (skillOverrides, listing budget)
set -uo pipefail

ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MODE="${1:-}"
[[ "$MODE" == "--apply" || "$MODE" == "--check" ]] || { echo "Usage: $0 --apply|--check" >&2; exit 2; }

ROOT="$ROOT" MODE="$MODE" python3 - <<'PY'
import glob, json, os, re, sys

root, mode = os.environ["ROOT"], os.environ["MODE"]
settings_path = os.path.join(root, ".claude", "settings.json")
wanted = {}
for path in sorted(glob.glob(os.path.join(root, ".claude", "commands", "*.md"))):
    with open(path, encoding="utf-8", errors="replace") as fh:
        m = re.match(r"^---\r?\n(.*?)\r?\n---", fh.read(), re.S)
    if m and re.search(r"^tier:\s*extended\s*$", m.group(1), re.M):
        wanted[os.path.basename(path)[:-3]] = "name-only"

with open(settings_path, encoding="utf-8") as fh:
    settings = json.load(fh)
current = settings.get("skillOverrides", {})
# Keep manual entries for non-extended skills (e.g. "off"); own only name-only ones.
merged = {k: v for k, v in current.items() if v != "name-only" or k in wanted}
merged.update(wanted)
merged = dict(sorted(merged.items()))

if mode == "--check":
    if merged == current:
        print(f"OK: skillOverrides in sync ({len(wanted)} extended commands name-only)")
        sys.exit(0)
    print("STALE: skillOverrides out of sync — run: bash scripts/skill-listing-overrides.sh --apply", file=sys.stderr)
    sys.exit(1)

settings["skillOverrides"] = merged
with open(settings_path, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(f"Applied: {len(wanted)} extended commands → name-only")
PY
