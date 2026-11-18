#!/usr/bin/env bats
# BATS tests for scripts/test-auditor-sweep.sh (SE-039 Slice 1).
#
# Ref: SE-039, SPEC-055 test-auditor
# Safety: read-only, set -uo pipefail.

SCRIPT="scripts/test-auditor-sweep.sh"

# Un barrido completo audita ~800 ficheros (más de un minuto): se hace una sola vez por fichero de
# test y los casos leen su salida. Antes cada caso relanzaba el barrido y la suite pasaba de 900 s en CI.
# Los casos que necesitan controlar el tamaño o el alcance usan --filter con pocos ficheros.
setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  local rc=0
  # Sale con 1 si el veredicto es FAIL: es un resultado válido, no un fallo del arranque.
  bash scripts/test-auditor-sweep.sh --bottom 10 --json > "$BATS_FILE_TMPDIR/full.json" 2>"$BATS_FILE_TMPDIR/full.err" || rc=$?
  echo "$rc" > "$BATS_FILE_TMPDIR/full.rc"
}

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
  SMALL="test-se40*.bats"
}

teardown() { cd /; }

@test "exists + executable" { [[ -x "$SCRIPT" ]]; }

@test "uses set -uo pipefail" {
  run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "passes bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }

@test "references SE-039" {
  run grep -c 'SE-039' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "references test-auditor.sh" {
  run grep -c 'test-auditor' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "--help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"bottom"* ]]
  [[ "$output" == *"threshold"* ]]
}

@test "rejects unknown arg" {
  run bash "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
}

@test "rejects non-integer --bottom" {
  run bash "$SCRIPT" --bottom abc
  [ "$status" -eq 2 ]
}

@test "rejects --bottom 0" {
  run bash "$SCRIPT" --bottom 0
  [ "$status" -eq 2 ]
}

@test "rejects --threshold > 100" {
  run bash "$SCRIPT" --threshold 150
  [ "$status" -eq 2 ]
}

@test "rejects non-integer --threshold" {
  run bash "$SCRIPT" --threshold xyz
  [ "$status" -eq 2 ]
}

# ── Execution ─────────────────────────────────────────────────────────

@test "runs against real tests/ dir" {
  rc=$(cat "$BATS_FILE_TMPDIR/full.rc")
  [[ "$rc" -eq 0 || "$rc" -eq 1 ]]
  [ -s "$BATS_FILE_TMPDIR/full.json" ]
}

@test "el barrido no emite errores aritméticos (salida del auditor con un solo documento)" {
  # Solo el error que corrige el barrido: otros avisos de stderr (locale, jq) no son este bug.
  run grep -EiH 'syntax error|error sintáctico|arithmetic|aritm' "$BATS_FILE_TMPDIR/full.err"
  [ "$status" -eq 1 ]
}

@test "output reports VERDICT, Files scanned and Compliance" {
  run bash "$SCRIPT" --filter "$SMALL" --bottom 3
  [[ "$output" == *"VERDICT"* ]]
  [[ "$output" == *"Files scanned:"* ]]
  [[ "$output" == *"Compliance:"* ]]
}

@test "output reports Bottom N ranking" {
  run bash "$SCRIPT" --filter "$SMALL" --bottom 5
  [[ "$output" == *"Bottom 5"* ]]
}

@test "--filter narrows files" {
  run bash "$SCRIPT" --filter "test-mutation-*.bats"
  [[ "$output" == *"Files scanned:"* ]]
  full=$(python3 -c "import json;print(json.load(open('$BATS_FILE_TMPDIR/full.json'))['files'])")
  [[ "$output" != *"Files scanned: $full"* ]]
}

@test "--filter with no matches returns 1" {
  run bash "$SCRIPT" --filter "nonexistent-test-xyz-*.bats"
  [ "$status" -eq 1 ]
}

@test "--json produces valid JSON" {
  run python3 -c "
import json, sys
d = json.load(open('$BATS_FILE_TMPDIR/full.json'))
for k in ['verdict','files','compliant','compliance_pct','bottom']:
    assert k in d, f'missing {k}'
assert isinstance(d['bottom'], list)
print('ok')
"
  [[ "$output" == *"ok"* ]]
}

@test "--json bottom list respects --bottom size" {
  run bash -c "bash scripts/test-auditor-sweep.sh --filter '$SMALL' --bottom 2 --json | python3 -c \"
import json, sys
d = json.load(sys.stdin)
assert d['files'] > 2, d['files']
assert len(d['bottom']) == 2, len(d['bottom'])
print('ok')
\""
  [[ "$output" == *"ok"* ]]
}

@test "bottom list sorted ascending by score" {
  run python3 -c "
import json
d = json.load(open('$BATS_FILE_TMPDIR/full.json'))
scores = [b['score'] for b in d['bottom']]
assert len(scores) == 10, scores
assert scores == sorted(scores), f'not sorted: {scores}'
print('ok')
"
  [[ "$output" == *"ok"* ]]
}

@test "verdict is PASS or FAIL" {
  run python3 -c "
import json
print(json.load(open('$BATS_FILE_TMPDIR/full.json'))['verdict'])
"
  [[ "$output" == "PASS" || "$output" == "FAIL" ]]
}

@test "compliance_pct between 0 and 100" {
  run python3 -c "
import json
d = json.load(open('$BATS_FILE_TMPDIR/full.json'))
assert 0 <= d['compliance_pct'] <= 100
print('ok')
"
  [[ "$output" == *"ok"* ]]
}

# ── Isolation ────────────────────────────────────────────────────────

@test "isolation: does not modify any test file" {
  local h_before
  h_before=$(find tests -name "*.bats" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')
  bash "$SCRIPT" --filter "$SMALL" --bottom 2 >/dev/null 2>&1 || true
  local h_after
  h_after=$(find tests -name "*.bats" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')
  [[ "$h_before" == "$h_after" ]]
}

@test "isolation: exit codes 0/1/2" {
  run bash "$SCRIPT" --filter "$SMALL" --bottom 3
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  run bash "$SCRIPT" --bogus
  [[ "$status" -eq 2 ]]
}
