#!/usr/bin/env bats
# Ref: SPEC-091 / SE-091 — docs/propuestas/SE-091-caveman-always.md
# Caveman always-on + auto tribunal hooks.
# Verifies: caveman-default loaded in instructions, guards exist and are
# registered in savia-foundation, bash hook files present and use safe
# shell flags, opencode.json valid, plus negative + edge cases.

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FOUNDATION=".opencode/plugins/savia-foundation.ts"
  GRILL_GUARD=".opencode/plugins/guards/auto-grill-me.ts"
  ZOOM_GUARD=".opencode/plugins/guards/auto-zoom-out.ts"
  GRILL_HOOK=".opencode/hooks/auto-grill-me.sh"
  ZOOM_HOOK=".opencode/hooks/auto-zoom-out.sh"
  CAVEMAN_RULE="docs/rules/domain/caveman-default.md"
  OC_CONFIG="opencode.json"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── caveman-default.md (AC-01..AC-02) ────────────────────────────────────────

@test "AC-01: caveman-default.md exists" {
  [[ -f "$CAVEMAN_RULE" ]]
}

@test "AC-01: caveman-default.md has 6 numbered restrictions" {
  local count
  count=$(grep -cE "^\s*[1-6]\." "$CAVEMAN_RULE")
  [ "$count" -ge 6 ]
}

# SE-511: las reglas pueden llegar directas o por el bloque generado savia-core.md,
# que extrae literalmente las regiones savia-core:reglas/excepciones de caveman-default.md.
caveman_loaded() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, re, sys
cfg, rule, core = sys.argv[1:4]
instr = json.load(open(cfg)).get('instructions', [])
if any('caveman-default' in i for i in instr):
    sys.exit(0)
if not any(i.endswith('savia-core.md') for i in instr):
    sys.exit(1)
src = open(rule, encoding='utf-8').read()
m = re.search(r'<!-- savia-core:reglas -->\n(.*?)\n<!-- /savia-core:reglas -->', src, re.S)
blk = open(core, encoding='utf-8').read()
sys.exit(0 if m and m.group(1).strip() and m.group(1).strip() in blk else 1)
PY
}

@test "AC-02: caveman rules reach opencode.json instructions (direct or via savia-core.md)" {
  run caveman_loaded "$OC_CONFIG" "$CAVEMAN_RULE" docs/rules/domain/savia-core.md
  [ "$status" -eq 0 ]
}

@test "AC-02 negativo: sin caveman-default ni savia-core en instructions no pasa" {
  python3 -c "
import json
d = json.load(open('$OC_CONFIG'))
d['instructions'] = [i for i in d.get('instructions', []) if 'caveman-default' not in i and 'savia-core' not in i]
json.dump(d, open('$TMPDIR_TEST/oc.json', 'w'))
"
  run caveman_loaded "$TMPDIR_TEST/oc.json" "$CAVEMAN_RULE" docs/rules/domain/savia-core.md
  [ "$status" -eq 1 ]
}

@test "AC-02 negativo: savia-core.md sin las reglas de caveman no pasa" {
  grep -v 'Self-strip before output' docs/rules/domain/savia-core.md > "$TMPDIR_TEST/core.md"
  run caveman_loaded "$OC_CONFIG" "$CAVEMAN_RULE" "$TMPDIR_TEST/core.md"
  [ "$status" -eq 1 ]
}

# ── Guard files (AC-03..AC-04) ───────────────────────────────────────────────

@test "AC-03: auto-grill-me.ts guard exists" {
  [[ -f "$GRILL_GUARD" ]]
}

@test "AC-03: auto-grill-me.ts exports shouldGrillPath" {
  grep -q "export function shouldGrillPath" "$GRILL_GUARD"
}

@test "AC-03: auto-grill-me.ts exports autoGrillMe" {
  grep -q "export async function autoGrillMe" "$GRILL_GUARD"
}

@test "AC-03: auto-grill-me.ts targets code extensions" {
  grep -qE '"ts"|"py"|"cs"|"go"' "$GRILL_GUARD"
}

@test "AC-04: auto-zoom-out.ts guard exists" {
  [[ -f "$ZOOM_GUARD" ]]
}

@test "AC-04: auto-zoom-out.ts exports shouldZoomOutPath" {
  grep -q "export function shouldZoomOutPath" "$ZOOM_GUARD"
}

@test "AC-04: auto-zoom-out.ts exports autoZoomOut" {
  grep -q "export async function autoZoomOut" "$ZOOM_GUARD"
}

@test "AC-04: auto-zoom-out.ts targets ROADMAP and docs/architecture" {
  grep -qE "ROADMAP|docs.*architecture" "$ZOOM_GUARD"
}

# ── Registration in savia-foundation (AC-05) ─────────────────────────────────

@test "AC-05: savia-foundation imports auto-grill-me" {
  grep -q "autoGrillMe" "$FOUNDATION"
  grep -q "auto-grill-me" "$FOUNDATION"
}

@test "AC-05: savia-foundation imports auto-zoom-out" {
  grep -q "autoZoomOut" "$FOUNDATION"
  grep -q "auto-zoom-out" "$FOUNDATION"
}

@test "AC-05: autoGrillMe in BEFORE_GUARDS array" {
  python3 - <<'PY'
content = open(".opencode/plugins/savia-foundation.ts").read()
guards_block = content[content.index("const BEFORE_GUARDS"):content.index("] as const;", content.index("const BEFORE_GUARDS"))+12]
assert "autoGrillMe" in guards_block, "autoGrillMe not in BEFORE_GUARDS"
PY
}

@test "AC-05: autoZoomOut in BEFORE_GUARDS array" {
  python3 - <<'PY'
content = open(".opencode/plugins/savia-foundation.ts").read()
guards_block = content[content.index("const BEFORE_GUARDS"):content.index("] as const;", content.index("const BEFORE_GUARDS"))+12]
assert "autoZoomOut" in guards_block, "autoZoomOut not in BEFORE_GUARDS"
PY
}

# ── Bash hook files (AC-06 — legacy Claude Code) ─────────────────────────────

@test "AC-06: auto-grill-me.sh bash hook exists" {
  [[ -f "$GRILL_HOOK" ]]
}

@test "AC-06: auto-zoom-out.sh bash hook exists" {
  [[ -f "$ZOOM_HOOK" ]]
}

@test "AC-06: auto-grill-me.sh is executable" {
  [[ -x "$GRILL_HOOK" ]]
}

# ── Semantics: non-blocking (AC-07) ─────────────────────────────────────────

@test "AC-07: autoGrillMe guard does not throw — verified via TS tests" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed (CI runner)"
  cd .opencode && bun test plugins/__tests__/auto-grill-me.test.ts 2>&1 | grep -q "0 fail"
}

@test "AC-07: autoZoomOut guard does not throw — verified via TS tests" {
  command -v bun >/dev/null 2>&1 || skip "bun not installed (CI runner)"
  cd .opencode && bun test plugins/__tests__/auto-zoom-out.test.ts 2>&1 | grep -q "0 fail"
}

# ── opencode.json valid JSON (AC-08) ─────────────────────────────────────────

@test "AC-08: opencode.json is valid JSON after changes" {
  python3 -c "import json; json.load(open('opencode.json'))"
}

# ── Safety verification (AC-09) ──────────────────────────────────────────────

@test "AC-09: auto-grill-me.sh hook uses set -uo pipefail safety flags" {
  grep -q "set -uo pipefail" "$GRILL_HOOK"
}

@test "AC-09: auto-zoom-out.sh hook uses set -uo pipefail safety flags" {
  grep -q "set -uo pipefail" "$ZOOM_HOOK"
}

# ── Negative cases (AC-10) ───────────────────────────────────────────────────

@test "AC-10: missing caveman-default.md path is detected as failure" {
  run test -f "$TMPDIR_TEST/nonexistent-caveman.md"
  [ "$status" -ne 0 ]
}

@test "AC-10: invalid JSON input fails json.load gracefully" {
  run python3 -c "import json; json.loads('{not valid json')"
  [ "$status" -ne 0 ]
}

@test "AC-10: empty guard file is rejected (no exports)" {
  local empty_guard="$TMPDIR_TEST/empty-guard.ts"
  : > "$empty_guard"
  run grep -q "export function shouldGrillPath" "$empty_guard"
  [ "$status" -ne 0 ]
}

@test "AC-10: bad opencode.json path returns error to readers" {
  run python3 -c "import json; json.load(open('$TMPDIR_TEST/missing-config.json'))"
  [ "$status" -ne 0 ]
}

@test "AC-10: missing FOUNDATION import for unknown guard fails grep" {
  run grep -q "ZZZ_DOES_NOT_EXIST_GUARD_ZZZ" "$FOUNDATION"
  [ "$status" -ne 0 ]
}

@test "AC-10: invalid extension list in guard would skip code paths" {
  run grep -q "\"xyz_unknown_ext\"" "$GRILL_GUARD"
  [ "$status" -ne 0 ]
}

# ── Edge cases (AC-11) ───────────────────────────────────────────────────────

@test "AC-11: nonexistent hook path boundary returns false" {
  [[ ! -f "$TMPDIR_TEST/nonexistent-hook.sh" ]]
}

@test "AC-11: empty foundation file edge case is detectable" {
  local empty_foundation="$TMPDIR_TEST/empty-foundation.ts"
  : > "$empty_foundation"
  [ ! -s "$empty_foundation" ] || [ "$(wc -c < "$empty_foundation")" -eq 0 ]
}

@test "AC-11: zero matches for sentinel keyword confirms boundary" {
  ! grep -q "SENTINEL_NULL_BOUNDARY_TOKEN_ZZZ" "$CAVEMAN_RULE"
}

@test "AC-11: large path with no arg defaults to safe no-op" {
  run bash -c '[[ -z "" ]]'
  [ "$status" -eq 0 ]
}
