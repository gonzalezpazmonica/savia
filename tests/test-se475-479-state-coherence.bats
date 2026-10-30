#!/usr/bin/env bats
# PR #1415: coherencia entre specs SE-475..SE-479, planning-state y sesión.

STATE="docs/propuestas/planning-state.json"

@test "cada spec SE-475..479 en disco tiene iniciativa y pertenece a una sesión" {
  for f in docs/specs/SE-47[5-9]-*.spec.md; do
    id=$(basename "$f" | cut -d- -f1-2)
    run jq -e --arg i "$id" '.initiatives|map(.id)|index($i)' "$STATE"
    [ "$status" -eq 0 ]
    run jq -e --arg i "$id" '.route.session_plan|map(.initiatives[])|index($i)' "$STATE"
    [ "$status" -eq 0 ]
  done
}

@test "cada iniciativa SE-475..479 del estado tiene su spec en disco" {
  for id in $(jq -r '.initiatives[]|select(.id|test("^SE-47[5-9]$"))|.id' "$STATE"); do
    run bash -c "ls docs/specs/${id}-*.spec.md"
    [ "$status" -eq 0 ]
  done
}

@test "la prioridad de la spec coincide con la de su sesión y con la del estado" {
  for f in docs/specs/SE-47[5-9]-*.spec.md; do
    id=$(basename "$f" | cut -d- -f1-2)
    spec=$(sed -n 's/^priority: //p' "$f" | head -1)
    sess=$(jq -r --arg i "$id" '.route.session_plan[]|select(.initiatives|index($i))|.priority' "$STATE")
    init=$(jq -r --arg i "$id" '.initiatives[]|select(.id==$i)|.priority' "$STATE")
    [ "$spec" = "$sess" ]
    [ "$init" = "$sess" ]
  done
}

@test "SE-478 no está en el estado, el LOG ni como spec (bloqueada por política)" {
  [ ! -e docs/specs/SE-478-decision-triage-symmetry-protocol.spec.md ]
  run jq -e '.initiatives|map(.id)|index("SE-478")' "$STATE"
  [ "$status" -ne 0 ]
  run grep -q "SE-478" docs/propuestas/LOG.md
  [ "$status" -ne 0 ]
}

@test "las specs no repiten entradas de timeline" {
  for f in docs/specs/SE-47[5-9]-*.spec.md; do
    d=$(grep "PROPOSED" "$f" | sort | uniq -d | wc -l)
    [ "$d" -eq 0 ]
  done
}

@test "SE-479 define la precedencia entre clasificaciones" {
  run grep -q "FAIL_ESCAPE\` > \`FAIL_FALSE_DONE" docs/specs/SE-479-no-in-scope-solution-battery.spec.md
  [ "$status" -eq 0 ]
}

@test "SE-477 AC5 inventaría llamadores y define periodo de aviso" {
  run grep -q "Inventario de llamadores" docs/specs/SE-477-comparison-statistics-minimum.spec.md
  [ "$status" -eq 0 ]
  run grep -q "Periodo de aviso" docs/specs/SE-477-comparison-statistics-minimum.spec.md
  [ "$status" -eq 0 ]
}
