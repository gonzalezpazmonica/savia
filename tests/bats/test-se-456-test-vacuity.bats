#!/usr/bin/env bats
# SE-456 — detector de vacuidad en tests BATS y ratchet sobre línea base.
# Ref: docs/specs/SE-456-test-vacuity-evidence-criteria.spec.md
# Ref: docs/rules/domain/test-evidence-criteria.md

set -uo pipefail

ENGINE="scripts/test-auditor-engine.py"
GATE="scripts/ci-test-quality-gate.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
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

@test "V1: variantes que antes se escapaban se detectan" {
  # \043 = «#»: sin un comentario literal en esta línea, el detector no se confunde con su propio fixture.
  fixture v1c "$(printf 'grep -q x f || true  \043 nota\ngrep -q x f || true;\ngrep -E -q x f || true\nassert_output "x" || true\nrun echo a; [ "$status" -eq 0 ] || true\n[ -f f ] || exit 0\n[ -f f ] || return 0\n[ -f f ] || echo "no pasa"')"
  [ "$(vac_count v1c)" -eq 8 ]
}

@test "@test con comillas simples o con comillas escapadas en el nombre se escanea" {
  printf '#!/usr/bin/env bats\n@test '"'"'simple'"'"' {\n  grep -q x f || true\n}\n@test "con \\"comillas\\"" {\n  grep -q y f || true\n}\n' > "$FX/tests/q.bats"
  [ "$(vac_count q)" -eq 2 ]
}

@test "no marca: || echo dentro de una sustitución de comando" {
  fixture ok7 '  [ "$(grep -c x f || echo 0)" = "0" ]'
  [ "$(vac_count ok7)" -eq 0 ]
}

@test "V1: aserciones encadenadas con && y anuladas con || true se detectan; preparación condicional no" {
  fixture v1e '  [ "$status" -eq 0 ] && [ -f x ] || true'
  [ "$(vac_count v1e)" -eq 1 ]
  fixture v1f '  [ -f x ] && echo hola || true'
  [ "$(vac_count v1f)" -eq 0 ]
}

@test "V1: || /usr/bin/true e if aserción; then :; fi se detectan" {
  fixture v1g "$(printf 'grep -q x f || /usr/bin/true\nif grep -q x f; then :; fi')"
  [ "$(vac_count v1g)" -eq 2 ]
}

@test "V2: nombrar \$output en un echo no comprueba el resultado; capturarlo sí" {
  fixture v2e "$(printf 'run echo a\necho "$output"')"
  [ "$(vac_kind v2e)" = "V2" ]
  fixture v2g "$(printf 'run echo a\nprevio="$status"\nrun echo a\n[ "$status" -eq "$previo" ]')"
  [ "$(vac_count v2g)" -eq 0 ]
}

@test "@test con comentario tras la llave se escanea" {
  printf '#!/usr/bin/env bats\n@test "con nota" {  \043 nota\n  grep -q x f || true\n}\n' > "$FX/tests/n.bats"
  [ "$(vac_count n)" -eq 1 ]
}

@test "test-auditor.sh --embed no certifica ni sale con 0 un fichero con vacuidad aunque sume 80" {
  cp tests/fixtures/se376/certified-skill-test.bats.fixture "$FX/tests/limpio.bats"
  cp "$FX/tests/limpio.bats" "$FX/tests/bueno.bats"
  printf '@test "vacio" {\n  run false\n}\n' >> "$FX/tests/bueno.bats"
  run bash scripts/test-auditor.sh "$FX/tests/bueno.bats" --embed
  [ "$status" -eq 1 ]
  [[ "$output" == *"hash NOT embedded"* ]]
  run grep -c '^# audit:' "$FX/tests/bueno.bats"
  [ "$output" = "0" ]
  run bash scripts/test-auditor.sh "$FX/tests/limpio.bats" --embed
  [ "$status" -eq 0 ]
  [[ "$output" == *"Embedded certification hash"* ]]
  run grep -c '^# audit:' "$FX/tests/limpio.bats"
  [ "$output" = "1" ]
}

@test "--vacuity-scan sin directorio tests/ sale con 2 y el gate falla cerrado" {
  mkdir -p "$BATS_TEST_TMPDIR/vacio"
  run python3 "$ENGINE" --vacuity-scan "$BATS_TEST_TMPDIR/vacio"
  [ "$status" -eq 2 ]
  echo 0 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$BATS_TEST_TMPDIR/vacio" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"el detector no pudo medir"* ]]
}

@test "ratchet: arreglar un hallazgo y añadir otro con el mismo recuento falla" {
  fixture nuevo '  grep -q x f || true'
  printf 'tests/viejo.bats\tcaso\tV1\n' > "$BATS_TEST_TMPDIR/base.findings"
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"tests/nuevo.bats"* ]]
}

@test "ratchet: los mismos hallazgos de la línea base pasan por identidad" {
  fixture viejo '  grep -q x f || true'
  printf 'tests/viejo.bats\tcaso\tV1\n' > "$BATS_TEST_TMPDIR/base.findings"
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
}

@test "--update-vacuity-baseline escribe recuento e identidades que el ratchet acepta" {
  fixture viejo '  run false'
  echo 0 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --update-vacuity-baseline
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/base.count")" -eq 1 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/base.findings")" -eq 1 ]
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
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
  printf 'tests/a.bats\tcaso\tV2\ntests/b.bats\tcaso\tV2\n' > "$BATS_TEST_TMPDIR/base.findings"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 > línea base 1"* ]]
}

@test "ratchet: igual a la línea base pasa" {
  fixture a '  run false'
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  printf 'tests/a.bats\tcaso\tV2\n' > "$BATS_TEST_TMPDIR/base.findings"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
}

@test "ratchet: con recuento pero sin fichero de identidades falla cerrado" {
  fixture a '  run false'
  echo 1 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"sin fichero de identidades"* ]]
}

@test "ratchet: por debajo de la línea base pasa y avisa de bajarla" {
  fixture a '  [ 1 -eq 1 ]'
  echo 3 > "$BATS_TEST_TMPDIR/base.count"
  printf 'tests/x.bats\tcaso\tV2\ntests/y.bats\tcaso\tV2\ntests/z.bats\tcaso\tV2\n' > "$BATS_TEST_TMPDIR/base.findings"
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --vacuity-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"bajar la línea base"* ]]
}

@test "ratchet: sin fichero de línea base falla cerrado" {
  fixture a '  [ 1 -eq 1 ]'
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/no-existe.count" bash "$GATE" --vacuity-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"sin línea base"* ]]
}

@test "update-baseline: detector caído no toca la línea base existente" {
  mkdir -p "$BATS_TEST_TMPDIR/vacio"
  echo 7 > "$BATS_TEST_TMPDIR/base.count"
  run env SAVIA_VACUITY_ROOT="$BATS_TEST_TMPDIR/vacio" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --update-vacuity-baseline
  [ "$status" -eq 2 ]
  [ "$(cat "$BATS_TEST_TMPDIR/base.count")" = "7" ]
  [ ! -e "$BATS_TEST_TMPDIR/base.findings" ]
}

@test "update-baseline: escribe recuento e identidades coherentes" {
  fixture a '  run false'
  run env SAVIA_VACUITY_ROOT="$FX" SAVIA_VACUITY_BASELINE="$BATS_TEST_TMPDIR/base.count" bash "$GATE" --update-vacuity-baseline
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/base.count")" = "1" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/base.findings")" -eq 1 ]
}

@test "la línea base real coincide con lo que mide el detector en el repo" {
  run python3 "$ENGINE" --vacuity-scan "$REPO_ROOT"
  [ "$status" -eq 0 ]
  n=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
  # Menos que la línea base es una mejora y el ratchet la deja pasar (AC3): solo se exige que no la supere
  # y que recuento e identidades de la línea base sean coherentes entre sí.
  [ "$n" -le "$(cat .ci-baseline/test-vacuity.count)" ]
  [ "$(cat .ci-baseline/test-vacuity.count)" -eq "$(wc -l < .ci-baseline/test-vacuity.findings)" ]
}

@test "la regla test-evidence-criteria existe y test-quality-gate la enlaza" {
  [ -f docs/rules/domain/test-evidence-criteria.md ]
  grep -q "test-evidence-criteria.md" docs/rules/domain/test-quality-gate.md
}

# ── S03q (SE-376): parte de puntuación del gate con auditor simulado ─────────
# Copia el gate a un árbol propio con test-auditor.sh y test-coverage-checker.sh
# simulados; el motor de vacuidad y el umbral adaptativo son los reales.
gate_fx() {  # gate_fx <json que devuelve el auditor simulado>
  G="$BATS_TEST_TMPDIR/g"; mkdir -p "$G/scripts" "$G/tests"
  cp "$GATE" "$ENGINE" scripts/quality-gate-adaptive.py "$G/scripts/"
  printf '%s\n' "$1" > "$G/audit.out"
  printf '#!/usr/bin/env bash\ncat "%s"\n' "$G/audit.out" > "$G/scripts/test-auditor.sh"
  printf '#!/usr/bin/env bash\necho "{\\"coverage_percent\\": 91}"\n' > "$G/scripts/test-coverage-checker.sh"
  printf '#!/usr/bin/env bats\n@test "x" {\n  [ 1 -eq 1 ]\n}\n' > "$G/tests/ok.bats"
  echo 0 > "$G/base.count"; : > "$G/base.findings"
}
gate_run() {
  run env SAVIA_VACUITY_ROOT="$G" SAVIA_VACUITY_BASELINE="$G/base.count" "$@" bash "$G/scripts/ci-test-quality-gate.sh"
}

@test "puntuación: auditor con salida ilegible no da RESULT: PASS (aviso fail-closed)" {
  gate_fx 'Traceback: auditor caído'
  gate_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: WARN — calidad sin medir"* ]]
  [[ "$output" != *"RESULT: PASS"* ]]
}

@test "puntuación: JSON sin lista results tampoco certifica (negativo)" {
  gate_fx '{"total_files": 3}'
  gate_run
  [[ "$output" == *"RESULT: WARN — calidad sin medir"* ]]
  gate_fx '{"total_files": 3, "results": "x"}'
  gate_run
  [[ "$output" == *"RESULT: WARN — calidad sin medir"* ]]
}

@test "puntuación: umbral no numérico no deja pasar (negativo)" {
  gate_fx '{"total_files":1,"results":[{"file":"a.bats","total":10}]}'
  gate_run SAVIA_QUALITY_GATE_FIXED_MIN=abc
  [[ "$output" == *"Umbral no numérico: 'abc'"* ]]
  [[ "$output" != *"RESULT: PASS"* ]]
}

@test "puntuación: umbral decimal (79.5) se acepta y filtra (79 debajo, 80 no)" {
  gate_fx '{"total_files":2,"results":[{"file":"a.bats","total":79},{"file":"b.bats","total":80}]}'
  gate_run SAVIA_QUALITY_GATE_FIXED_MIN=79.5
  [[ "$output" != *"Umbral no numérico"* ]]
  [[ "$output" == *"Audited: 2 files, 1 below threshold (79.5)"* ]]
  [[ "$output" == *"a.bats: 79/100"* ]]
  [[ "$output" != *"b.bats: 80/100"* ]]
}

@test "puntuación: FIXED_MIN no se interpreta como código en modo adaptativo (negativo)" {
  gate_fx '{"total_files":6,"results":[{"file":"a","total":50},{"file":"b","total":60},{"file":"c","total":70},{"file":"d","total":80},{"file":"e","total":90},{"file":"f","total":95}]}'
  local mark="$BATS_TEST_TMPDIR/inyectado"
  gate_run SAVIA_QUALITY_GATE_ADAPTIVE=on \
    "SAVIA_QUALITY_GATE_FIXED_MIN=0+len(open('$mark','w').name)"
  [ ! -e "$mark" ]
  [[ "$output" != *"RESULT: PASS"* ]]
}

@test "puntuación: boundary 79 queda por debajo de 80 y 80 no" {
  gate_fx '{"total_files":2,"results":[{"file":"a.bats","total":79},{"file":"b.bats","total":80}]}'
  gate_run
  [[ "$output" == *"Audited: 2 files, 1 below threshold (80)"* ]]
  [[ "$output" == *"a.bats: 79/100"* ]]
  [[ "$output" != *"b.bats: 80/100"* ]]
  [[ "$output" == *"RESULT: WARN — tests below quality threshold (80)"* ]]
}

@test "puntuación: todos en 80 o más da RESULT: PASS y exit 0" {
  gate_fx '{"total_files":2,"results":[{"file":"a.bats","total":80},{"file":"b.bats","total":95}]}'
  gate_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Audited: 2 files, 0 below threshold (80)"* ]]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "puntuación: adaptive=on usa el umbral calculado (65), no el fijo" {
  gate_fx '{"total_files":6,"results":[{"file":"a","total":50},{"file":"b","total":60},{"file":"c","total":70},{"file":"d","total":80},{"file":"e","total":90},{"file":"f","total":95}]}'
  gate_run SAVIA_QUALITY_GATE_ADAPTIVE=on
  [[ "$output" == *"Adaptive threshold: 65"* ]]
  [[ "$output" == *"Audited: 6 files, 2 below threshold (65)"* ]]
}

@test "puntuación: adaptive=warn avisa pero filtra con el fijo 80" {
  gate_fx '{"total_files":6,"results":[{"file":"a","total":50},{"file":"b","total":60},{"file":"c","total":70},{"file":"d","total":80},{"file":"e","total":90},{"file":"f","total":95}]}'
  gate_run SAVIA_QUALITY_GATE_ADAPTIVE=warn
  [[ "$output" == *"Adaptive would use 65; gating on fixed 80"* ]]
  [[ "$output" == *"3 below threshold (80)"* ]]
}

@test "puntuación limpia pero vacuidad por encima de la base: exit 1" {
  gate_fx '{"total_files":1,"results":[{"file":"a.bats","total":90}]}'
  printf '#!/usr/bin/env bats\n@test "v" {\n  run false\n}\n' > "$G/tests/vac.bats"
  gate_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESULT: PASS"* ]]
  [[ "$output" == *"RESULT: FAIL — tests que no pueden fallar"* ]]
}
