#!/usr/bin/env bats
# SCL-006 — Autonomía graduada por p_consistent
# Ref: docs/specs/SCL-006-autonomia-graduada.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  export REPO_ROOT
}

setup() {
  AUT="$REPO_ROOT/scripts/learning-autonomy.sh"
}

@test "AC-1: p_consistent bajo (<0.5) restringe a L0 — L1 denegado" {
  run bash "$AUT" --p-consistent 0.4 --requested L1
  [ "$status" -ne 0 ]
  [[ "$output" == *"L0"* ]]
}

@test "AC-2: p 0.5-0.7 permite L1" {
  run bash "$AUT" --p-consistent 0.6 --requested L1
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRANTED"* ]]
}

@test "AC-3: p 0.7-0.85 permite L2, no L3" {
  run bash "$AUT" --p-consistent 0.8 --requested L2
  [ "$status" -eq 0 ]
  run bash "$AUT" --p-consistent 0.8 --requested L3
  [ "$status" -ne 0 ]
}

@test "AC-4: p >= 0.85 degrada a L2 sin historial+aprobacion (gates loop-phasing)" {
  run bash "$AUT" --p-consistent 0.9 --requested L3
  [ "$status" -ne 0 ]
  [[ "$output" == *"L2"* ]]
}

@test "AC-5: p >= 0.85 + historial + humano permite L3" {
  run bash "$AUT" --p-consistent 0.9 --requested L3 --history-ok --human-ok
  [ "$status" -eq 0 ]
  [[ "$output" == *"L3"* ]]
  [[ "$output" == *"GRANTED"* ]]
}

@test "AC-5a: p >= 0.85 sin aprobación humana no permite L3" {
  run bash "$AUT" --p-consistent 0.9 --requested L3 --history-ok
  [ "$status" -ne 0 ]
  [[ "$output" == *"L2"* ]]
}

@test "AC-5b: p >= 0.85 sin historial no permite L3" {
  run bash "$AUT" --p-consistent 0.9 --requested L3 --human-ok
  [ "$status" -ne 0 ]
  [[ "$output" == *"L2"* ]]
}

@test "AC-6: pedir menos de lo permitido siempre se concede" {
  run bash "$AUT" --p-consistent 0.9 --requested L1 --history-ok --human-ok
  [ "$status" -eq 0 ]
}

@test "AC-7: --json emite JSON valido" {
  run bash "$AUT" --p-consistent 0.65 --requested L1 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['granted'] == True, d; assert d['allowed'] == 'L1', d"
}

@test "AC-8: valor fuera de rango es error (exit 3)" {
  run bash "$AUT" --p-consistent 1.5
  [ "$status" -eq 3 ]
}

# ── Comportamiento: fronteras exactas, salida y errores ──────────────────────

lvl_of() { bash "$AUT" --p-consistent "$@" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["allowed"])'; }

@test "fronteras: 0.49->L0, 0.50->L1, 0.69->L1, 0.70->L2, 0.84->L2, 0.85->L3 (con gates)" {
  [ "$(lvl_of 0.49)" = "L0" ]
  [ "$(lvl_of 0.50)" = "L1" ]
  [ "$(lvl_of 0.69)" = "L1" ]
  [ "$(lvl_of 0.70)" = "L2" ]
  [ "$(lvl_of 0.84)" = "L2" ]
  [ "$(lvl_of 0.85 --history-ok --human-ok)" = "L3" ]
  [ "$(lvl_of 0.849 --history-ok --human-ok)" = "L2" ]
}

@test "extremos 0 y 1 son válidos: 0 -> L0, 1 -> L3 con gates y L2 sin ellos" {
  [ "$(lvl_of 0)" = "L0" ]
  [ "$(lvl_of 1 --history-ok --human-ok)" = "L3" ]
  [ "$(lvl_of 1)" = "L2" ]
}

@test "fuera de rango por ambos lados: -0.01 y 1.01 -> exit 3 con mensaje" {
  run bash "$AUT" --p-consistent -0.01
  [ "$status" -eq 3 ]
  [[ "$output" == *"out of range"* ]]
  run bash "$AUT" --p-consistent 1.01
  [ "$status" -eq 3 ]
}

@test "L3 sin gates se degrada a L2 aunque se pida L2: concedido" {
  run bash "$AUT" --p-consistent 0.95 --requested L2
  [ "$status" -eq 0 ]
  [[ "$output" == *"nivel permitido: L2"* ]]
}

@test "sin --requested: concede, no imprime línea de nivel solicitado y el JSON dice none" {
  run bash "$AUT" --p-consistent 0.1
  [ "$status" -eq 0 ]
  [[ "$output" != *"solicitado"* ]]
  [[ "$output" == *"veredicto: GRANTED"* ]]
  run bash "$AUT" --p-consistent 0.1 --json
  [[ "$output" == *'"requested":"none"'* ]]
}

@test "salida de texto exacta de una concesión y de una denegación" {
  run bash "$AUT" --p-consistent 0.6 --requested L1
  [ "${lines[0]}" = "p_consistent: 0.6" ]
  [ "${lines[1]}" = "nivel permitido: L1" ]
  [ "${lines[2]}" = "nivel solicitado: L1" ]
  [ "${lines[3]}" = "veredicto: GRANTED" ]
  run bash "$AUT" --p-consistent 0.6 --requested L2
  [ "$status" -eq 1 ]
  [ "${lines[2]}" = "nivel solicitado: L2" ]
  [ "${lines[3]}" = "veredicto: DENIED" ]
  [[ "$output" != *"GRANTED"* ]]
}

@test "JSON exacto con gates y denegación" {
  run bash "$AUT" --p-consistent 0.9 --requested L3 --history-ok --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"p_consistent":0.9,"allowed":"L2","requested":"L3","granted":false,"history_ok":true,"human_ok":false}' ]
}

@test "nivel solicitado inválido se deniega siempre (no se interpreta como bajo)" {
  run bash "$AUT" --p-consistent 0.9 --requested L9 --history-ok --human-ok
  [ "$status" -eq 1 ]
  [[ "$output" == *"DENIED"* ]]
  run bash "$AUT" --p-consistent 0.9 --requested l1 --history-ok --human-ok
  [ "$status" -eq 1 ]
  run bash "$AUT" --p-consistent 0.9 --requested "" --history-ok --human-ok
  [ "$status" -eq 0 ]
}

@test "cada escalón: pedir uno por encima se deniega y el exacto se concede" {
  local p req ok
  for pair in "0.2 L0 L1" "0.6 L1 L2" "0.75 L2 L3"; do
    set -- $pair
    run bash "$AUT" --p-consistent "$1" --requested "$2"
    [ "$status" -eq 0 ]
    run bash "$AUT" --p-consistent "$1" --requested "$3"
    [ "$status" -eq 1 ]
  done
}

@test "pedir un nivel inferior al permitido en cada escalón se concede" {
  run bash "$AUT" --p-consistent 0.75 --requested L0
  [ "$status" -eq 0 ]
  run bash "$AUT" --p-consistent 0.75 --requested L1
  [ "$status" -eq 0 ]
  run bash "$AUT" --p-consistent 0.6 --requested L0
  [ "$status" -eq 0 ]
}

@test "sin argumentos o con -h: uso y exit 2" {
  run bash "$AUT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"learning-autonomy.sh --p-consistent"* ]]
  [[ "$output" == *"[--history-ok] [--human-ok] [--json]"* ]]
  [[ "$output" == *"3 input out of range"* ]]
  run bash "$AUT" -h
  [ "$status" -eq 2 ]
  run bash "$AUT" --p-consistent 0.5 --help
  [ "$status" -eq 2 ]
}

@test "argumentos desconocidos se ignoran" {
  run bash "$AUT" --p-consistent 0.6 --nada --requested L1
  [ "$status" -eq 0 ]
}
