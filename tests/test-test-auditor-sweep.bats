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

# Auditor falso en un proyecto copia: el barrido solo debe aceptar un único documento con total 0..100.
sweep_with_auditor() {  # sweep_with_auditor <cuerpo del auditor falso>
  local p="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$p/scripts" "$p/tests"
  cp "$SCRIPT" "$p/scripts/test-auditor-sweep.sh"
  printf '#!/bin/bash\n%s\n' "$1" > "$p/scripts/test-auditor.sh"
  chmod +x "$p/scripts/test-auditor.sh"
  printf '#!/usr/bin/env bats\n' > "$p/tests/test-x.bats"
  run bash "$p/scripts/test-auditor-sweep.sh" --json
}

@test "auditor con dos documentos contradictorios: score 0 y FAIL, no PASS" {
  sweep_with_auditor "printf '%s\n' '{\"total\":100}' '{\"total\":0}'; exit 1"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "FAIL" and .compliant == 0' >/dev/null
}

@test "auditor con total fuera de rango (150): score 0" {
  sweep_with_auditor "echo '{\"total\":150}'; exit 0"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.verdict == "FAIL" and .compliant == 0' >/dev/null
}

@test "auditor con un único documento válido sobre el umbral: cuenta como conforme" {
  sweep_with_auditor "echo '{\"total\":90}'; exit 1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "PASS" and .compliant == 1' >/dev/null
}

# PATH mínimo con solo las órdenes que el barrido usa: permite simular la ausencia de jq o python3.
# restricted_path <orden-excluida>...
restricted_path() {
  local bin="$BATS_TEST_TMPDIR/bin" c x skip
  mkdir -p "$bin"
  for c in bash dirname find sort grep cat python3 jq; do
    skip=0
    for x in "$@"; do [[ "$c" == "$x" ]] && skip=1; done
    (( skip )) && continue
    command -v "$c" >/dev/null 2>&1 && ln -sf "$(command -v "$c")" "$bin/$c"
  done
  echo "$bin"
}

# Corre el barrido con un auditor falso sin jq en el PATH y comprueba FAIL con 0 conformes.
assert_sweep_rejects_without_jq() {  # <cuerpo del auditor falso>
  local p="$BATS_TEST_TMPDIR/proj" bin
  sweep_with_auditor "$1"   # prepara el proyecto copia (con jq: lo que importa es la siguiente)
  bin=$(restricted_path jq)
  [ ! -e "$bin/jq" ]
  run env PATH="$bin" bash "$p/scripts/test-auditor-sweep.sh" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict":"FAIL"'* && "$output" == *'"compliant":0'* ]]
}

@test "sin jq: un total válido seguido de basura no certifica" {
  assert_sweep_rejects_without_jq "printf '%s' '{\"total\":100}basura'"
}

@test "sin jq: dos documentos en una línea no certifican" {
  assert_sweep_rejects_without_jq "echo '{\"total\":100} {}'"
}

@test "sin jq: un total decimal no certifica" {
  assert_sweep_rejects_without_jq "echo '{\"total\":100.5}'"
}

@test "sin jq: un entero enorme que desborda a 0..100 no certifica" {
  # 18446744073709551716 = 2^64 + 100: en aritmética de bash de 64 bits vale 100.
  assert_sweep_rejects_without_jq "echo '{\"total\":18446744073709551716}'"
}

@test "clave total repetida (0 y luego 100) no certifica" {
  assert_sweep_rejects_without_jq "echo '{\"total\":0,\"total\":100}'"
}

@test "sin jq: un documento válido sobre el umbral sigue contando como conforme" {
  local p="$BATS_TEST_TMPDIR/proj" bin
  sweep_with_auditor "echo '{\"total\":90}'"
  bin=$(restricted_path jq)
  run env PATH="$bin" bash "$p/scripts/test-auditor-sweep.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"PASS"'* && "$output" == *'"compliant":1'* ]]
}

@test "sin python3 no hay respaldo: un auditor válido puntúa 0 y el barrido sale FAIL" {
  local p="$BATS_TEST_TMPDIR/proj" bin
  sweep_with_auditor "echo '{\"total\":90}'"
  bin=$(restricted_path python3)
  [ ! -e "$bin/python3" ]
  run env PATH="$bin" bash "$p/scripts/test-auditor-sweep.sh" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict":"FAIL"'* && "$output" == *'"compliant":0'* ]]
}
