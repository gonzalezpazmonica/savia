#!/usr/bin/env bats
# SE-498 F0 — reconcile (R5) sobre un ledger JSONL interino (SE-493 aún no está implementado).
# La clasificación es total: lo que no casa con una fila concreta es INDETERMINATE.

load fixtures/savia-control/setup

setup() { setup_control; }

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

@test "R5: PREPARED sin la transición abandon disponible queda INDETERMINATE (fail-closed)" {
  ledger '{"effect_id":"p1","state":"PREPARED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE p1"* ]]
}

@test "R5: PREPARED con abandon que funciona y el ámbito parado queda REJECTED" {
  printf '#!/usr/bin/env python3\nimport sys; sys.exit(0 if sys.argv[1:3][0] == "abandon" else 1)\n' > "$R/scripts/effect-ledger.py"
  ledger '{"effect_id":"p1","state":"PREPARED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 0 ]; [[ "$output" == *"REJECTED p1"* ]]
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
  tail -1 "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"indeterminate":\["e1"\],"scope":"executor:a","stop_seq":1'
  ls "$SAVIA_CONTROL_DIR"/reports/reconcile-*.json >/dev/null
}

@test "R5: un ledger ilegible hace salir 2 a reconcile" {
  printf 'no json\n' > "$SAVIA_EFFECT_LEDGER"
  sc pause --reason x
  run sc reconcile; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}
