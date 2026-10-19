#!/usr/bin/env bats
# Ref: OpenCode 2 adaptation, savia-gates dual V1/V2 (plan oc2-analysis P1-P7)
#
# Static checks for the dual plugin and the installers. The behaviour itself (guards load and block in a REAL
# engine) is scripts/opencode-gates-real.py; this file runs it only when SAVIA_GATES_REAL=1 because it starts
# real OpenCode servers (about a minute per engine, and OpenCode 1 needs the npm registry the first time).

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLUGIN_DIR="$ROOT_DIR/scripts/opencode-plugin/savia-gates"
}

# ── P1: the plugin loads in both engines ─────────────────────────────────────

@test "gates: lib/gates.ts is frontend-agnostic (no OpenCode SDK or Bun shell)" {
  [ -f "$PLUGIN_DIR/lib/gates.ts" ]
  ! grep -E '@opencode|Bun\.\$|ctx\.' "$PLUGIN_DIR/lib/gates.ts" | grep -v '^\s*//' | grep -v '^[^:]*://'
}

@test "gates: V2 adapter fails closed when the guards cannot start or the runtime lacks the hook domains" {
  grep -q 'GUARDS_UNAVAILABLE' "$PLUGIN_DIR/lib/v2-adapter.ts"
  grep -q 'the guards cannot be installed' "$PLUGIN_DIR/lib/v2-adapter.ts"
}

@test "gates: OpenCode 1.19 calls setup() with a reduced context and V2 setup ignores it" {
  grep -q 'isReducedHostContext' "$PLUGIN_DIR/lib/v2-adapter.ts"
}

@test "gates: V1 chat.message reads the typed text from the parts (the message record has none)" {
  grep -q 'export function promptText' "$PLUGIN_DIR/lib/v1-adapter.ts"
  grep -q 'p?.type === "text"' "$PLUGIN_DIR/lib/v1-adapter.ts"
}

@test "gates: permission policy no longer needs a Bun shell helper" {
  ! grep -q '\$`' "$PLUGIN_DIR/lib/permission.ts"
  grep -q 'node:child_process' "$PLUGIN_DIR/lib/permission.ts"
}

@test "gates: package.json carries the SDKs as optional peers, not installable dependencies" {
  python3 - "$PLUGIN_DIR/package.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert 'dependencies' not in d, 'runtime dependencies would be installed by the host'
assert d['peerDependenciesMeta']['@opencode-ai/plugin']['optional'] is True
assert d['peerDependenciesMeta']['@opencode/plugin']['optional'] is True
PY
}

@test "gates: .opencode/package.json declares the V2 SDK as optional peer" {
  python3 - "$ROOT_DIR/.opencode/package.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert '@opencode-ai/plugin' in d['dependencies']
assert d['peerDependenciesMeta']['@opencode/plugin']['optional'] is True
PY
}

# ── P2/P3: installers use the packages that exist ────────────────────────────

@test "install: install.sh uses @opencode/cli (v2, default) or opencode-ai (v1), never @opencode-ai/cli" {
  grep -q '@opencode/cli' "$ROOT_DIR/install.sh"
  grep -q 'opencode-ai' "$ROOT_DIR/install.sh"
  ! grep -q 'npm install -g @opencode-ai/cli' "$ROOT_DIR/install.sh"
  ! grep -q 'npm install -g @opencode-ai/cli' "$ROOT_DIR/install.ps1"
  grep -q 'SAVIA_OPENCODE_FLAVOR' "$ROOT_DIR/install.sh"
}

@test "install: opencode-install.sh --dry-run per flavor names the right npm package and config key" {
  run env SAVIA_HOME="$BATS_TEST_TMPDIR/h2" bash "$ROOT_DIR/scripts/opencode-install.sh" --dry-run --flavor v2
  [ "$status" -eq 0 ]
  [[ "$output" == *"@opencode/cli@2."* ]]
  run env SAVIA_HOME="$BATS_TEST_TMPDIR/h1" bash "$ROOT_DIR/scripts/opencode-install.sh" --dry-run --flavor v1
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm opencode-ai"* ]]
  run bash "$ROOT_DIR/scripts/opencode-install.sh" --flavor v3
  [ "$status" -eq 2 ]
}

@test "install: --link-only writes the V2 key 'plugins' with the linked directory, V1 'plugin'" {
  SAVIA_HOME="$BATS_TEST_TMPDIR/l2" run bash "$ROOT_DIR/scripts/opencode-install.sh" --link-only --flavor v2
  [ "$status" -eq 0 ]
  python3 - "$BATS_TEST_TMPDIR/l2/opencode/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['plugins'][0]['package'].endswith('/plugins/savia-gates') and 'plugin' not in d
PY
  SAVIA_HOME="$BATS_TEST_TMPDIR/l1" run bash "$ROOT_DIR/scripts/opencode-install.sh" --link-only --flavor v1
  [ "$status" -eq 0 ]
  python3 - "$BATS_TEST_TMPDIR/l1/opencode/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['plugin'][0].endswith('/plugins/savia-gates') and 'plugins' not in d
PY
}

# ── P4: opencode run flags ───────────────────────────────────────────────────

@test "hook runner: no --no-interactive (neither engine has it); v2 runs with a private server" {
  ! grep -q -- '--no-interactive' "$ROOT_DIR/scripts/agent-hook-runner.sh"
  grep -q -- '--standalone' "$ROOT_DIR/scripts/agent-hook-runner.sh"
}

# ── P7: migration smoke ──────────────────────────────────────────────────────

@test "migration smoke: accepts OpenCode 1 >= 1.18.29 and 2, and never starts the v2 background service" {
  grep -q '1.18.29' "$ROOT_DIR/scripts/opencode-migration-smoke.sh"
  grep -q 'OC_MAJOR' "$ROOT_DIR/scripts/opencode-migration-smoke.sh"
  grep -q 'npm install -g @opencode/cli' "$ROOT_DIR/scripts/opencode-migration-smoke.sh"
  ! grep -q 'opencode debug agents' <(grep -v '^\s*#' "$ROOT_DIR/scripts/opencode-migration-smoke.sh" | grep -v 'would start')
}

# ── P6: real engine ──────────────────────────────────────────────────────────

@test "real engine: driver and fake model are present and parse" {
  python3 -c "import ast,sys;[ast.parse(open(f).read()) for f in sys.argv[1:]]" \
    "$ROOT_DIR/scripts/opencode-gates-real.py" "$ROOT_DIR/scripts/opencode-gates-fake-llm.py"
  run python3 "$ROOT_DIR/scripts/opencode-gates-real.py" --help
  [ "$status" -eq 0 ]
}

@test "real engine: savia-gates loads and blocks in the real OpenCode 2 (SAVIA_GATES_REAL=1)" {
  [ "${SAVIA_GATES_REAL:-0}" = "1" ] || skip "opt-in: SAVIA_GATES_REAL=1 starts real OpenCode servers"
  run python3 "$ROOT_DIR/scripts/opencode-gates-real.py" --engine v2
  if [ "$status" -eq 77 ]; then skip "no OpenCode 2 binary"; fi
  echo "$output" >&2
  [ "$status" -eq 0 ]
}

@test "real engine: savia-gates loads and blocks in the real OpenCode 1 (SAVIA_GATES_REAL=1)" {
  [ "${SAVIA_GATES_REAL:-0}" = "1" ] || skip "opt-in: SAVIA_GATES_REAL=1 starts real OpenCode servers"
  run python3 "$ROOT_DIR/scripts/opencode-gates-real.py" --engine v1
  if [ "$status" -eq 77 ]; then skip "no OpenCode 1 binary (>= 1.18.29)"; fi
  echo "$output" >&2
  [ "$status" -eq 0 ]
}
