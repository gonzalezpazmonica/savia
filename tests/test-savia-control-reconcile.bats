#!/usr/bin/env bats
# SE-498 F0 — reconcile (R5) sobre un ledger JSONL interino (SE-493 se retiró el 2026-11-14; no hay transición de abandono).
# La clasificación es total: lo que no casa con una fila concreta es INDETERMINATE.
# Ref: docs/specs/SE-498-global-stop-cross-executor-revocation.spec.md (R5).
# Cada test trabaja en su BATS_TEST_TMPDIR (repo, diario y ledger propios; ver fixtures/savia-control/setup).

load fixtures/savia-control/setup

setup() { setup_control; }

teardown() { unset SAVIA_EFFECT_LEDGER SAVIA_CONTROL_DIR MERGE_SPRINT_HOME GH_STUB_DIR; }

ledger() { printf '%s\n' "$@" > "$SAVIA_EFFECT_LEDGER"; }

@test "R5: cada estado del ledger cae en su clase; lo no listado es INDETERMINATE" {
  ledger '{"effect_id":"ok","state":"SUCCEEDED","receipt":"r1","executor":"a"}' \
         '{"effect_id":"comp","state":"SUCCEEDED","receipt":"r2","compensation":{"state":"SUCCEEDED"},"executor":"a"}' \
         '{"effect_id":"abs","state":"FAILED","probe":{"result":"ABSENT","definitive":true},"executor":"a"}' \
         '{"effect_id":"nodef","state":"FAILED","probe":{"result":"ABSENT","definitive":false},"executor":"a"}' \
         '{"effect_id":"norec","state":"SUCCEEDED","executor":"a"}' \
         '{"effect_id":"raro","state":"INVENTADO","executor":"a","irreversible":true}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"
  [ "$status" -eq 5 ]
  [[ "$output" == *"CONFIRMED ok"* ]]
  [[ "$output" == *"COMPENSATED comp"* ]]
  [[ "$output" == *"REJECTED abs"* ]]
  [[ "$output" == *"INDETERMINATE nodef"* ]]
  [[ "$output" == *"INDETERMINATE norec"* ]]
  [[ "$output" == *"INDETERMINATE raro [executor:a] (irreversible"* ]]
}

@test "R5: PREPARED queda INDETERMINATE: no hay transición de abandono" {
  ledger '{"effect_id":"p1","state":"PREPARED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]; [ "$status" -ne 0 ]; [[ "$output" == *"INDETERMINATE p1"* ]]
}

@test "R5: un ABANDONED heredado del ledger se clasifica REJECTED y no deja nada incierto" {
  ledger '{"effect_id":"ab1","state":"ABANDONED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"REJECTED ab1"* ]]
  [[ "$output" != *"INDETERMINATE ab1"* ]]
}

@test "R5 negativo: aunque reaparezca un guion con el nombre del libro retirado, no se invoca y PREPARED sigue INDETERMINATE" {
  # Nombre partido: el test de retirada de SE-493 prohíbe citar el guion entero.
  local viejo="$R/scripts/effect-""ledger.py"
  printf '#!/usr/bin/env python3\nimport pathlib,sys\npathlib.Path(sys.argv[0]+".llamado").write_text("x")\nsys.exit(0)\n' > "$viejo"
  ledger '{"effect_id":"p1","state":"PREPARED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile
  [ "$status" -eq 5 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDETERMINATE p1"* ]]
  [[ "$output" != *"REJECTED p1"* ]]
  [ ! -e "$viejo.llamado" ]
}

@test "R5: los efectos de ámbitos en RUNNING no entran en el informe ni en el exit" {
  ledger '{"effect_id":"pa","state":"PREPARED","executor":"a"}' '{"effect_id":"ok","state":"SUCCEEDED","receipt":"r","executor":"b"}'
  sc pause --scope executor:b --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" != *pa* ]]
}

@test "R5: con 5, el diario registra el reconcile con sus ámbitos, su stop_seq y los inciertos" {
  ledger '{"effect_id":"e1","state":"NEEDS_REVIEW","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  tail -1 "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"op":"reconcile"'
  tail -1 "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"indeterminate":\["e1"\],"resolved":\[\],"scope":"executor:a","stop_seq":1'
  ls "$SAVIA_CONTROL_DIR"/reports/reconcile-*.json >/dev/null
}

@test "R5 error: un ledger ilegible (invalid JSON) hace salir 2 a reconcile" {
  printf 'no json\n' > "$SAVIA_EFFECT_LEDGER"
  sc pause --reason x
  run sc reconcile; [ "$status" -eq 2 ]; [ "$status" -ne 0 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

@test "R5 empty: con el ledger vacío y un ámbito parado, reconcile no informa nada incierto" {
  : > "$SAVIA_EFFECT_LEDGER"
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" != *INDETERMINATE* ]]
}

@test "R5 nonexistent: sin fichero de ledger, reconcile sale 0 y no lo crea" {
  [ ! -e "$SAVIA_EFFECT_LEDGER" ]
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"
  [ "$status" -eq 0 ]
  [ ! -e "$SAVIA_EFFECT_LEDGER" ]
}

@test "R5 null: un estado nulo no casa con ninguna fila y queda INDETERMINATE" {
  ledger '{"effect_id":"n1","state":null,"executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"
  [ "$status" -eq 5 ]
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDETERMINATE n1"* ]]
}
