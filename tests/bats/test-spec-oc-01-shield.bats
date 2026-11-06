#!/usr/bin/env bats
# test-spec-oc-01-shield.bats — SPEC-OC-01 Savia Shield OpenCode Adaptation
#
# Tests: savia-shield-check.sh and supporting components.
# Run: bats tests/bats/test-spec-oc-01-shield.bats
# S03p (SE-376): comportamiento sobre un workspace sintético (SAVIA_WORKSPACE_DIR):
# críticos vs no críticos, cableado real en la lista de guards, JSON con cero
# componentes y fail-closed sin workspace.
# Ref: docs/propuestas/SPEC-OC-01-savia-shield-opencode-adaptation.md
set -uo pipefail

WORKSPACE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="$WORKSPACE/scripts/savia-shield-check.sh"
DOC="$WORKSPACE/docs/rules/domain/savia-shield-opencode.md"

# ── Test 1: Script exists and is executable ───────────────────────────────────
@test "savia-shield-check.sh exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

# ── Test 2: --json flag produces valid JSON ───────────────────────────────────
@test "savia-shield-check.sh --json produces valid JSON" {
  run bash "$SCRIPT" --json
  # exit 0 (active) or 1 (partial) are both acceptable — just not 2
  [ "$status" -ne 2 ]
  # Output must be parseable JSON
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null
}

# ── Test 3: shield_status field is present in JSON output ────────────────────
@test "JSON output contains shield_status field" {
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'shield_status' in d, 'shield_status missing'
assert d['shield_status'] in ('active', 'partial', 'inactive'), f'bad value: {d[\"shield_status\"]}'
"
}

# ── Test 4: components and missing arrays are present ────────────────────────
@test "JSON output contains components and missing arrays" {
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'components' in d, 'components missing'
assert 'missing' in d, 'missing missing'
assert isinstance(d['components'], list), 'components must be list'
assert isinstance(d['missing'], list), 'missing must be list'
"
}

# ── Test 5: context-sanitize-input.sh is referenced in check ────────────────
@test "context-sanitize-input.sh component appears in output when present" {
  # The hook exists (checked in test setup), so it must appear in components
  [ -f "$WORKSPACE/.opencode/hooks/context-sanitize-input.sh" ]
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'context-sanitize-input' in d['components'], \
  'context-sanitize-input not in components: ' + str(d['components'])
"
}

# ── Test 6: data-sovereignty-gate guard is checked ───────────────────────────
@test "data-sovereignty-gate guard detected as component" {
  [ -f "$WORKSPACE/.opencode/plugins/guards/data-sovereignty-gate.ts" ]
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'data-sovereignty-gate' in d['components'], \
  'data-sovereignty-gate not in components: ' + str(d['components'])
"
}

# ── Test 7: savia-foundation-wired is checked (dataSovereigntyGate wired) ────
@test "savia-foundation-wired component detected" {
  run bash "$SCRIPT" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'savia-foundation-wired' in d['components'], \
  'savia-foundation-wired not in components: ' + str(d['components'])
"
}

# ── Test 8: shield_status is active when all components present ───────────────
@test "shield_status is active when all components are present" {
  run bash "$SCRIPT" --json
  # With doc present, should be active
  [ -f "$DOC" ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['shield_status'] == 'active', \
  'Expected active, got: ' + d['shield_status'] + ' | missing: ' + str(d['missing'])
"
}

# ── Test 9: savia-shield-opencode.md doc exists with required sections ────────
@test "savia-shield-opencode.md exists with required sections" {
  [ -f "$DOC" ]
  grep -q "shield_status" "$DOC"
  grep -q "Verificar que está activo" "$DOC"
  grep -q "Qué datos protege" "$DOC"
}

# ── Test 10: doc contains OpenCode vs Claude Code comparison table ────────────
@test "savia-shield-opencode.md contains activation and comparison info" {
  [ -f "$DOC" ]
  grep -q "Activar Savia Shield" "$DOC"
  grep -q "Claude Code" "$DOC"
  grep -q "OpenCode" "$DOC"
}

# ── S03p: workspace sintético ─────────────────────────────────────────────────

mk_ws() { # workspace completo y activo
  WS="$(mktemp -d "$BATS_TEST_TMPDIR/ws.XXXXXX")"
  mkdir -p "$WS/.opencode/plugins/guards" "$WS/.opencode/plugins/lib" \
    "$WS/.opencode/hooks" "$WS/docs/rules/domain"
  touch "$WS/.opencode/plugins/guards/data-sovereignty-gate.ts" \
    "$WS/.opencode/plugins/guards/data-sovereignty-audit.ts" \
    "$WS/.opencode/plugins/lib/sovereignty-patterns.ts" \
    "$WS/.opencode/plugins/guards/block-credential-leak.ts" \
    "$WS/.opencode/hooks/context-sanitize-input.sh" \
    "$WS/docs/rules/domain/savia-shield-opencode.md"
  cat > "$WS/.opencode/plugins/savia-foundation.ts" <<'TS'
import { blockCredentialLeak } from "./guards/block-credential-leak.ts";
import { dataSovereigntyGate } from "./guards/data-sovereignty-gate.ts";
const BEFORE_GUARDS = [
  blockCredentialLeak,
  dataSovereigntyGate, // SH01
] as const;
TS
}

shield() { run env SAVIA_WORKSPACE_DIR="$WS" bash "$SCRIPT" "$@"; }

jq_py() { echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

@test "synthetic: complete workspace is active with exit 0 and no missing" {
  mk_ws
  shield --json
  [ "$status" -eq 0 ]
  jq_py "assert d['shield_status']=='active' and d['missing']==[] and len(d['components'])==8, d"
}

@test "synthetic: missing only the doc is partial with exit 1" {
  mk_ws
  mv "$WS/docs/rules/domain/savia-shield-opencode.md" "$WS/doc.bak"
  shield --json
  [ "$status" -eq 1 ]
  jq_py "assert d['shield_status']=='partial' and d['missing']==['savia-shield-opencode-doc'], d"
}

@test "synthetic: each missing critical file makes shield inactive (exit 2)" {
  for f in .opencode/plugins/guards/data-sovereignty-gate.ts \
           .opencode/plugins/guards/data-sovereignty-audit.ts \
           .opencode/plugins/lib/sovereignty-patterns.ts \
           .opencode/plugins/guards/block-credential-leak.ts \
           .opencode/hooks/context-sanitize-input.sh; do
    mk_ws
    mv "$WS/$f" "$WS/removed.bak"
    shield --json
    [ "$status" -eq 2 ] || { echo "not inactive without $f: $output"; false; }
    jq_py "assert d['shield_status']=='inactive', d"
  done
}

@test "synthetic: guard imported but removed from the guard list is blocked as not wired" {
  mk_ws
  sed -i '/^  dataSovereigntyGate, \/\/ SH01$/d' "$WS/.opencode/plugins/savia-foundation.ts"
  grep -q 'import { dataSovereigntyGate }' "$WS/.opencode/plugins/savia-foundation.ts"
  shield --json
  [ "$status" -eq 2 ]
  jq_py "assert 'savia-foundation-wired' in d['missing'] and d['shield_status']=='inactive', d"
}

@test "synthetic: commented-out credential guard is not wired and makes shield inactive" {
  mk_ws
  sed -i 's|^  blockCredentialLeak,$|  // blockCredentialLeak,|' "$WS/.opencode/plugins/savia-foundation.ts"
  shield --json
  [ "$status" -eq 2 ]
  jq_py "assert 'block-credential-leak-wired' in d['missing'] and d['shield_status']=='inactive', d"
}

@test "synthetic: missing foundation file reports both wirings missing" {
  mk_ws
  mv "$WS/.opencode/plugins/savia-foundation.ts" "$WS/f.bak"
  shield --json
  [ "$status" -eq 2 ]
  jq_py "assert {'savia-foundation-wired','block-credential-leak-wired'} <= set(d['missing']), d"
}

@test "synthetic: empty workspace gives empty components array (zero), not an empty string" {
  WS="$(mktemp -d "$BATS_TEST_TMPDIR/empty.XXXXXX")"
  shield --json
  [ "$status" -eq 2 ]
  jq_py "assert d['components']==[] and len(d['missing'])==8 and d['shield_status']=='inactive', d"
}

@test "synthetic: text mode lists found and missing components with counts" {
  mk_ws
  mv "$WS/docs/rules/domain/savia-shield-opencode.md" "$WS/doc.bak"
  shield
  [ "$status" -eq 1 ]
  [[ "$output" == *"Savia Shield Status: partial"* ]]
  [[ "$output" == *"Components found (7):"* ]]
  [[ "$output" == *"Missing (1):"*"  - savia-shield-opencode-doc"* ]]
}

@test "synthetic: text mode with zero components prints no empty entry" {
  WS="$(mktemp -d "$BATS_TEST_TMPDIR/empty.XXXXXX")"
  shield
  [ "$status" -eq 2 ]
  [[ "$output" == *"Components found (0):"* ]]
  [[ "$output" != *"  + "$'\n'* ]]
  [[ "$output" != *"  + " ]]
}

@test "nonexistent workspace dir fails closed with exit 2 and error" {
  run env SAVIA_WORKSPACE_DIR="$BATS_TEST_TMPDIR/nope" bash "$SCRIPT" --json
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: workspace directory not found"* ]]
  [[ "$output" != *shield_status* ]]
}
