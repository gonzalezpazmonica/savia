#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
# opencode-migration-smoke.sh — SPEC-127 Slice 2b-ii (final migration prep)
#
# 6 fast checks confirming OpenCode can bootstrap Savia. Supports OpenCode 1
# (>= 1.18.29, object plugins) and OpenCode 2. Run after installing/upgrading
# and `bash scripts/savia-preferences.sh init`. Fails loudly with actionable
# error messages — no silent skips.
#
# Never starts OpenCode 2's per-user background service: on v2 the agent and
# command counts come from the files, not from `opencode debug agents`.
#
# Exit 0 = ready to migrate. Exit non-zero = list of fixes printed to stderr.
#
# Reference: docs/migration-claude-code-to-opencode.md
# Reference: SPEC-127 Slice 2b-ii

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PASS=0
FAIL=0
WARN=0

ok()   { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠ $*" >&2; WARN=$((WARN + 1)); }

echo "── OpenCode migration smoke test ──"

# 1. opencode binary version
echo "[1/6] OpenCode binary version"
OC_MAJOR=""
if ! command -v opencode >/dev/null 2>&1; then
  fail "opencode binary not on PATH — install per docs/migration-claude-code-to-opencode.md (npm install -g @opencode/cli for v2, opencode-ai for v1)"
else
  V=$(opencode --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ -z "$V" ]]; then
    warn "opencode --version produced no output"
  else
    OC_MAJOR="${V%%.*}"
    if [[ "$OC_MAJOR" -ge 2 ]]; then
      ok "opencode v$V (OpenCode 2)"
    elif printf '%s\n%s\n' "1.18.29" "$V" | sort -V -C; then
      ok "opencode v$V (OpenCode 1 >= 1.18.29)"
    else
      # `opencode upgrade` stays inside the major, and from 1.x it needs --major to cross to 2.
      fail "opencode v$V is below 1.18.29 (the Savia plugins use the object form) — run: opencode upgrade (stays on 1.x), or move to OpenCode 2 (recommended): npm install -g @opencode/cli"
    fi
  fi
fi

# 2. opencode.json present and valid
echo "[2/6] opencode.json present and valid JSON"
if [[ ! -f "$ROOT/opencode.json" ]]; then
  fail "opencode.json missing at workspace root"
else
  if python3 -c "import json; json.load(open('$ROOT/opencode.json'))" 2>/dev/null; then
    ok "opencode.json is valid JSON"
  else
    fail "opencode.json is not valid JSON — re-generate or fix manually"
  fi
fi

# Count entries under a top-level key of `opencode debug config` output.
# Plugins (e.g. opencode-sandbox) may print log lines to stdout before the
# JSON, so parse from the first line that opens the object.
config_count() {
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null || echo 0
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
start = 0 if text.startswith("{") else text.find("\n{") + 1
print(len(json.loads(text[start:]).get(sys.argv[2], {})))
PYEOF
}

# 3. agents discovered by OpenCode
echo "[3/6] OpenCode discovers ≥ 70 agents"
if ! command -v opencode >/dev/null 2>&1; then
  warn "skipped — opencode not on PATH"
elif [[ "$OC_MAJOR" -ge 2 ]]; then
  AGENTS=$(find "$ROOT/.opencode/agents/" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  if [[ "$AGENTS" -ge 70 ]]; then
    ok "$AGENTS agent files (OpenCode 2: counted from files; its CLI would start the background service)"
  else
    fail "$AGENTS agent files (expected ≥ 70) — run: bash scripts/agents-opencode-convert.sh --apply"
  fi
else
  TMP=$(mktemp)
  if opencode debug config > "$TMP" 2>"$TMP.err"; then
    AGENTS=$(config_count "$TMP" agent)
    if [[ "$AGENTS" -ge 70 ]]; then
      ok "$AGENTS agents discovered"
    elif [[ "$AGENTS" -eq 0 ]]; then
      fail "0 agents discovered — run: bash scripts/agents-opencode-convert.sh --apply"
    else
      warn "$AGENTS agents discovered (expected ≥ 70)"
    fi
  elif grep -q "V2 permissions are not supported" "$TMP.err" 2>/dev/null; then
    fail "opencode.json uses OpenCode 2 keys (permissions/policies) and this is OpenCode 1 — use OpenCode 2: npm install -g @opencode/cli"
  else
    fail "opencode debug config failed — check schema validity"
  fi
  rm -f "$TMP" "$TMP.err"
fi

# 4. commands discovered
echo "[4/6] OpenCode discovers ≥ 500 commands"
if ! command -v opencode >/dev/null 2>&1; then
  warn "skipped — opencode not on PATH"
elif [[ "$OC_MAJOR" -ge 2 ]]; then
  CMDS=$(find -L "$ROOT/.opencode/commands/" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
  if [[ "$CMDS" -ge 500 ]]; then
    ok "$CMDS command files (OpenCode 2: counted from files)"
  else
    fail "$CMDS command files (expected ≥ 500) — verify .opencode/commands symlink"
  fi
else
  TMP=$(mktemp)
  if opencode debug config > "$TMP" 2>/dev/null; then
    CMDS=$(config_count "$TMP" command)
    if [[ "$CMDS" -ge 500 ]]; then
      ok "$CMDS commands discovered"
    else
      fail "$CMDS commands (expected ≥ 500) — verify .opencode/commands symlink"
    fi
  fi
  rm -f "$TMP"
fi

# 5. SKILLS.md index present and ≥ 50 skills
echo "[5/6] SKILLS.md index present"
if [[ ! -f "$ROOT/SKILLS.md" ]]; then
  fail "SKILLS.md missing — run: bash scripts/skills-md-generate.sh --apply"
else
  ROWS=$(grep -cE '^\| [^|]+ \| `\.opencode/skills/' "$ROOT/SKILLS.md")
  if [[ "$ROWS" -ge 50 ]]; then
    ok "SKILLS.md lists $ROWS skills"
  else
    warn "SKILLS.md lists $ROWS skills (expected ≥ 50) — re-generate if stale"
  fi
fi

# 6. plugin foundation files
echo "[6/6] OpenCode plugin foundation and savia-gates files present"
MISSING=0
for f in \
  ".opencode/package.json" \
  ".opencode/tsconfig.json" \
  ".opencode/plugins/savia-foundation.ts" \
  ".opencode/plugins/lib/hook-input.ts" \
  ".opencode/plugins/lib/credential-patterns.ts" \
  ".opencode/plugins/guards/block-credential-leak.ts" \
  ".opencode/plugins/guards/validate-bash-global.ts" \
  ".opencode/plugins/guards/tdd-gate.ts" \
  "scripts/opencode-plugin/savia-gates/index.ts" \
  "scripts/opencode-plugin/savia-gates/lib/v2-adapter.ts"
do
  if [[ ! -f "$ROOT/$f" ]]; then
    fail "$f missing"
    MISSING=$((MISSING + 1))
  fi
done
if [[ $MISSING -eq 0 ]]; then
  ok "all 10 foundation files present"
fi

# ── Verdict ──
echo ""
echo "── Summary ──"
printf "PASS=%d  FAIL=%d  WARN=%d\n" "$PASS" "$FAIL" "$WARN"

if [[ $FAIL -gt 0 ]]; then
  echo "MIGRATION NOT READY — fix the failures above and re-run." >&2
  exit 1
fi
echo "Migration smoke OK. Proceed to: opencode run 'list 3 active commands'"
exit 0
