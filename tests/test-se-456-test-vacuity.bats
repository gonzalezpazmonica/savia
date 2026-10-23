#!/usr/bin/env bats
# SE-456 — detector de vacuidad en tests BATS y ratchet sobre línea base.
# Ref: docs/specs/SE-456-test-vacuity-evidence-criteria.spec.md
# Ref: docs/rules/domain/test-evidence-criteria.md

set -uo pipefail

ENGINE="scripts/test-auditor-engine.py"
GATE="scripts/ci-test-quality-gate.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$REPO_ROOT"
  FX="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$FX/tests"
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR/fx"
}

# Escribe un fichero de tests con el cuerpo dado dentro de un único @test.
fixture() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bats\n@test "caso" {\n%s\n}\n' "$body" > "$FX/tests/$name.bats"
}

# Número de hallazgos de vacuidad del fichero.
vac_count() {
  python3 "$ENGINE" "$FX/tests/$1.bats" "$FX" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['vacuity']))"
}

vac_kind() {
  python3 "$ENGINE" "$FX/tests/$1.bats" "$FX" | python3 -c "import json,sys; print(' '.join(v['kind'] for v in json.load(sys.stdin)['vacuity']))"
}

@test "V1: grep -q anulado con || true se detecta" {
  fixture v1a '  grep -q "hash" "$f" || true'
  [ "$(vac_count v1a)" -eq 1 ]
  [ "$(vac_kind v1a)" = "V1" ]
}

@test "V1: [[ ]] anulado con || true y con || : se detectan" {
  fixture v1b '  [[ "$output" =~ X ]] || true
  [ -f x ] || :'
  [ "$(vac_count v1b)" -eq 2 ]
}

@test "V1: cadena de alternativas que acaba en || true se detecta" {
  fixture v1c '  [[ "$output" =~ A ]] || [[ "$output" =~ B ]] || true'
  [ "$(vac_count v1c)" -eq 1 ]
}

@test "V2: run sin comprobar el resultado se detecta" {
  fixture v2a '  run bash -c "exit 3"'
  [ "$(vac_count v2a)" -eq 1 ]
  [ "$(vac_kind v2a)" = "V2" ]
}

@test "V2: run seguido solo de true se detecta" {
  fixture v2b '  run bash -c "exit 1"
  # comentario
  true'
  [ "$(vac_count v2b)" -eq 1 ]
}

@test "V2: el primer run sin comprobar se detecta aunque el segundo sí se compruebe" {
  fixture v2c '  run false
  run true
  [ "$status" -eq 0 ]'
  [ "$(vac_count v2c)" -eq 1 ]
}

@test "no marca: run con \$status comprobado" {
  fixture ok1 '  run bash -c "exit 0"
  [ "$status" -eq 0 ]'
  [ "$(vac_count ok1)" -eq 0 ]
}

@test "no marca: run con \$output comprobado" {
  fixture ok2 '  run echo hola
  [[ "$output" == *hola* ]]'
  [ "$(vac_count ok2)" -eq 0 ]
}

@test "no marca: run -0, run -1 y run ! comprueban el estado por sí mismos" {
  fixture ok3 '  run -0 true
  run -1 false
  run ! false'
  [ "$(vac_count ok3)" -eq 0 ]
}

@test "no marca: || true en una línea que no es aserción" {
  fixture ok4 '  rm -f "$tmp/x" || true
  mkdir -p d || true'
  [ "$(vac_count ok4)" -eq 0 ]
}

@test "no marca: preparación condicional [[ ]] && accion || true" {
  fixture ok5 '  [[ -f "$HOME/.x" ]] && T=$(cat "$HOME/.x") || true'
  [ "$(vac_count ok5)" -eq 0 ]
}

@test "no marca: run y || true fuera de un @test (setup y helpers)" {
  printf '#!/usr/bin/env bats\nsetup() {\n  run true\n  grep -q x f || true\n}\n@test "caso" {\n  [ 1 -eq 1 ]\n}\n' > "$FX/tests/ok6.bats"
  [ "$(vac_count ok6)" -eq 0 ]
}

@test "el hallazgo lleva test, línea y tipo" {
  fixture loc '  [ 1 -eq 1 ]
  grep -q x f || true'
  run python3 "$ENGINE" "$FX/tests/loc.bats" "$FX"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
v = json.load(sys.stdin)['vacuity'][0]
assert v['test'] == 'caso', v
assert v['line'] == 4, v
assert v['kind'] == 'V1', v
"
}

@test "un fichero que suma 80 o más con vacuidad no certifica; sin ella, sí" {
  cp tests/fixtures/se376/certified-skill-test.bats.fixture "$FX/tests/bueno.bats"
  run python3 "$ENGINE" "$FX/tests/bueno.bats" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['total']>=80 and d['certified'] is True and d['vacuity']==[], d"
  printf '@test "vacio" {\n  run false\n}\n' >> "$FX/tests/bueno.bats"
  run python3 "$ENGINE" "$FX/tests/bueno.bats" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['total']>=80 and d['certified'] is False and len(d['vacuity'])==1, d"
}

@test "--vacuity-scan cuenta los hallazgos de todo el árbol de tests" {
  fixture a '  run false'
  fixture b '  grep -q x f || true'
  fixture c '  [ 1 -eq 1 ]'
  run python3 "$ENGINE" --vacuity-scan "$FX"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['count']==2, d; assert len(d['findings'])==2"
}

@test "ratchet: por encima de la línea base falla" {
  fixture a '  run false'
  fixture b '  run false'
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 > línea base 1"* ]]
}

@test "ratchet: igual a la línea base pasa" {
  fixture a '  run false'
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
}

@test "ratchet: por debajo de la línea base pasa y avisa de bajarla" {
  fixture a '  [ 1 -eq 1 ]'
  echo 3 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"bajar la línea base"* ]]
}

@test "ratchet: sin fichero de línea base falla cerrado" {
  fixture a '  [ 1 -eq 1 ]'
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/no-existe.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
}

@test "la línea base real coincide con lo que mide el detector en el repo" {
  run python3 "$ENGINE" --vacuity-scan "$REPO_ROOT"
  [ "$status" -eq 0 ]
  n=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
  [ "$n" -eq "$(cat .ci-baseline/test-vacuity.count)" ]
}

@test "la regla test-evidence-criteria existe y test-quality-gate la enlaza" {
  [ -f docs/rules/domain/test-evidence-criteria.md ]
  grep -q "test-evidence-criteria.md" docs/rules/domain/test-quality-gate.md
}
