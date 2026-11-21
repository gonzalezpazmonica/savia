#!/usr/bin/env bats
# tests/bats/test-se253-hooks-coverage.bats
# SE-253 Slice 2 — Hooks Coverage Matrix
# AC-2.1: script exists, matrix exists, --check passes
# AC-2.2: no bloqueantes sin cobertura ni mitigacion
# AC-2.4: HOOKS-STRATEGY.md corregido (no ~80%, enlace a matrix)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/hooks-coverage-matrix.sh"
MATRIX="$REPO_ROOT/docs/hooks-coverage-matrix.md"
STRATEGY="$REPO_ROOT/.opencode/HOOKS-STRATEGY.md"

# ── AC-2.1: script exists and is executable ───────────────────────────────────
@test "AC-2.1: hooks-coverage-matrix.sh exists" {
  [[ -f "$SCRIPT" ]]
}

@test "AC-2.1: hooks-coverage-matrix.sh is executable" {
  [[ -x "$SCRIPT" ]]
}

# ── AC-2.1: matrix file exists ────────────────────────────────────────────────
@test "AC-2.1: docs/hooks-coverage-matrix.md exists" {
  [[ -f "$MATRIX" ]]
}

@test "AC-2.1: docs/hooks-coverage-matrix.md is non-empty" {
  [[ -s "$MATRIX" ]]
}

# ── AC-2.1: --check mode passes against committed file ───────────────────────
@test "AC-2.1: hooks-coverage-matrix.sh --check exits 0 with current matrix" {
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

# ── AC-2.1: matrix has expected structure ────────────────────────────────────
@test "AC-2.1: matrix has Summary section" {
  grep -q "## Summary" "$MATRIX"
}

@test "AC-2.1: matrix has Full matrix section" {
  grep -q "## Full matrix" "$MATRIX"
}

@test "AC-2.1: matrix has header columns (event, hook, portado_ts, cobertura, criticidad, mitigacion)" {
  grep -q "portado_ts" "$MATRIX"
  grep -q "cobertura" "$MATRIX"
  grep -q "criticidad" "$MATRIX"
  grep -q "mitigacion" "$MATRIX"
}

@test "AC-2.1: matrix summary row has numeric counts" {
  run python3 -c "
import re, sys
content = open('$MATRIX').read()
m = re.search(r'\| (\d+) \| (\d+)', content)
if not m:
    print('No numeric summary row found')
    sys.exit(1)
total = int(m.group(1))
if total < 50:
    print(f'Total {total} seems too low')
    sys.exit(1)
print(f'Total={total} OK')
"
  [ "$status" -eq 0 ]
}

# ── AC-2.2: no bloqueantes sin cobertura ni mitigacion ───────────────────────
@test "AC-2.2: Bloqueantes section says 'Ninguno' (all have coverage or documented degradation)" {
  grep -q "Ninguno — AC-2.2 satisfecho" "$MATRIX"
}

@test "AC-2.2: no hook row has empty mitigacion for bloqueante criticidad" {
  run python3 -c "
import re, sys
content = open('$MATRIX').read()
# Find Full matrix section
matrix_section = content.split('## Full matrix')[-1]
rows = re.findall(r'\|\s*(\w+)\s*\|\s*([\w\-\.]+)\s*\|\s*(si|no)\s*\|\s*(TS_GUARD|GIT_HOOK|CI_JOB|NONE)\s*\|\s*(bloqueante|warning|telemetria)\s*\|\s*(.*?)\s*\|', matrix_section)
violations = []
for event, hook, portado, cobertura, crit, mitigation in rows:
    if crit == 'bloqueante' and not mitigation.strip():
        violations.append(f'{event}|{hook}')
if violations:
    print('Bloqueantes with empty mitigation:', violations)
    sys.exit(1)
print(f'OK: {len(rows)} rows checked, 0 violations')
"
  [ "$status" -eq 0 ]
}

# ── AC-2.2: TS_GUARD count matches savia-foundation.ts imports ───────────────
@test "AC-2.2: TS_GUARD count in matrix is positive" {
  run python3 -c "
import re, sys
content = open('$MATRIX').read()
m = re.search(r'\| (\d+) \| (\d+) \([\d.]+%\) \|', content)
if not m:
    print('Could not parse summary row')
    sys.exit(1)
ts = int(m.group(2))
if ts < 10:
    print(f'TS guard count {ts} unexpectedly low')
    sys.exit(1)
print(f'TS guards: {ts}')
"
  [ "$status" -eq 0 ]
}

# ── AC-2.4: HOOKS-STRATEGY.md does not contain ~80% ─────────────────────────
@test "AC-2.4: HOOKS-STRATEGY.md does not contain '~80%'" {
  run grep -c '~80%' "$STRATEGY"
  [ "$output" = "0" ]
}

@test "AC-2.4: HOOKS-STRATEGY.md does not contain numeric hook count without matrix reference" {
  # The old claim was '69 hooks · 72 registros' — should be replaced by matrix reference
  run grep -c '72 registros' "$STRATEGY"
  [ "$output" = "0" ]
}

# ── AC-2.4: HOOKS-STRATEGY.md links to hooks-coverage-matrix.md ──────────────
@test "AC-2.4: HOOKS-STRATEGY.md contains link to hooks-coverage-matrix.md" {
  grep -q "hooks-coverage-matrix.md" "$STRATEGY"
}

@test "AC-2.4: HOOKS-STRATEGY.md has 'Cobertura OpenCode real' section" {
  grep -q "Cobertura OpenCode real" "$STRATEGY"
}

@test "AC-2.4: HOOKS-STRATEGY.md table shows real percentage (not ~80%)" {
  run python3 -c "
import re, sys
content = open('$STRATEGY').read()
# Should have a percentage that is not ~80%
# Real value from matrix is around 16.5%
m = re.search(r'16\.\d+%', content)
if not m:
    # Accept any non-80% percentage in the new section
    m = re.search(r'(\d+\.\d+%)', content)
    if not m:
        print('No percentage found in HOOKS-STRATEGY.md')
        sys.exit(1)
print(f'Found percentage: {m.group(0)}')
"
  [ "$status" -eq 0 ]
}

# ── SE-510 AC-7: guards listados en lib/before-guards.ts cuentan como TS_GUARD ─
_mk_tree() {
  local t="$1" plugin_import="$2"
  mkdir -p "$t/scripts" "$t/docs" "$t/.claude/hooks" "$t/.opencode/plugins/lib"
  cp "$SCRIPT" "$t/scripts/"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$t/.claude/hooks/fake-guard.sh"
  cat > "$t/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash .claude/hooks/fake-guard.sh"}]}]}}
JSON
  printf '%s\n' "$plugin_import" > "$t/.opencode/plugins/savia-foundation.ts"
  printf 'import { fakeGuard } from "../guards/fake-guard.ts";\nexport const BEFORE_GUARDS = [fakeGuard];\n' \
    > "$t/.opencode/plugins/lib/before-guards.ts"
}

@test "SE-510: guard importado vía lib/before-guards.ts sale como TS_GUARD" {
  t="$BATS_TEST_TMPDIR/tree"
  _mk_tree "$t" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";'
  run bash "$t/scripts/hooks-coverage-matrix.sh"
  [ "$status" -eq 0 ]
  grep -q '| PreToolUse | fake-guard.sh | si | TS_GUARD | bloqueante | fakeGuard |' "$t/docs/hooks-coverage-matrix.md"
}

@test "SE-510 negativo (seguridad c9eaee1 P2-1): guard importado pero fuera de BEFORE_GUARDS no da cobertura" {
  t="$BATS_TEST_TMPDIR/tree"
  _mk_tree "$t" 'import { BEFORE_GUARDS } from "./lib/before-guards.ts";'
  printf 'import { fakeGuard } from "../guards/fake-guard.ts";\nexport const BEFORE_GUARDS = [\n  // fakeGuard,\n  otherGuard,\n];\n' \
    > "$t/.opencode/plugins/lib/before-guards.ts"
  run bash "$t/scripts/hooks-coverage-matrix.sh"
  [ "$status" -eq 0 ]
  grep -q '| PreToolUse | fake-guard.sh | no | NONE | bloqueante |' "$t/docs/hooks-coverage-matrix.md"
}

@test "SE-510 negativo: lib/before-guards.ts que el plugin no importa no da cobertura" {
  t="$BATS_TEST_TMPDIR/tree"
  _mk_tree "$t" '// sin import de la lista'
  run bash "$t/scripts/hooks-coverage-matrix.sh"
  [ "$status" -eq 0 ]
  grep -q '| PreToolUse | fake-guard.sh | no | NONE | bloqueante |' "$t/docs/hooks-coverage-matrix.md"
  run grep -c 'TS_GUARD | bloqueante | fakeGuard' "$t/docs/hooks-coverage-matrix.md"
  [ "$output" = "0" ]
}
