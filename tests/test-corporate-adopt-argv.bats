#!/usr/bin/env bats
# tests/test-corporate-adopt-argv.bats — barrido Python (pendientes, 2026-11-27)
# corporate-adopt.sh y corporate-monotonicity-gate.sh: la tarjeta del cuerpo
# corporativo es entrada externa. Su ruta y su contenido van a Python por argv,
# nunca dentro del código de python3 -c; y un gate que falla para la adopción.
# Ref: docs/evidence/barridos/20261127-barrido-python.md (fila 21)

ADOPT="scripts/corporate-adopt.sh"
GATE="scripts/corporate-monotonicity-gate.sh"

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$(mktemp -d)"
  export LEDGER_DIR="$T/ledger" LEDGER="$T/ledger/adoption-ledger.jsonl"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$T/gate-ok.sh"
  printf '#!/usr/bin/env bash\necho "RESULT: FAIL"\nexit 1\n' > "$T/gate-fail.sh"
  cd "$T"
}

teardown() {
  cd /
  [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"
}

_card() {  # _card <ruta> <entry_id> [ambito]
  python3 -c 'import json,sys; json.dump({"body_id":"corp","version":"1","entries":[{"id":sys.argv[2],"ambito":sys.argv[3],"dureza":"blanda","principio":"p"}]}, open(sys.argv[1],"w"))' \
    "$1" "$2" "${3:-calidad}"
}

@test "adopt: si el gate de monotonía falla, la adopción se para con exit 1" {
  _card "$T/card.json" CRIT-900
  GATE_SCRIPT="$T/gate-fail.sh" run bash "$REPO/$ADOPT" "$T/card.json" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL"* ]]
  [ ! -s "$LEDGER" ]
}

@test "gate: ruta de tarjeta con comillas no ejecuta código" {
  local card="x');__import__('pathlib').Path('pwn-gate').touch();('.json"
  _card "$T/$card" CRIT-900
  run bash "$REPO/$GATE" "$T/$card"
  [ ! -e "$T/pwn-gate" ]
  [[ "$output" == *"Body: corp v1"* ]]
}

@test "adopt: ruta de tarjeta con comillas no ejecuta código" {
  local card="x');__import__('pathlib').Path('pwn-adopt').touch();('.json"
  _card "$T/$card" CRIT-900
  GATE_SCRIPT="$T/gate-ok.sh" run bash "$REPO/$ADOPT" "$T/$card" </dev/null
  [ ! -e "$T/pwn-adopt" ]
  [[ "$output" == *"Body: corp v1"* ]]
}

@test "adopt: id de entrada con barra y comilla queda literal en el ledger sin ejecutar código" {
  local eid="\\'+str(__import__('pathlib').Path('pwn-ledger').touch())+'"
  _card "$T/card.json" "$eid"
  GATE_SCRIPT="$T/gate-ok.sh" run bash "$REPO/$ADOPT" "$T/card.json" <<< $'y\nfirma\n'
  [ ! -e "$T/pwn-ledger" ]
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.loads(open(sys.argv[1]).readline()); assert d["entry_id"]==sys.argv[2] and d["signature"]=="firma" and d["action"]=="adopted", d' "$LEDGER" "$eid"
  [ "$status" -eq 0 ]
}

@test "adopt: detecta conflicto con el criterio personal del mismo ámbito" {
  printf 'CRIT-001 — Algo\n- ambito: calidad\n' > "$T/CRITERIO.md"
  _card "$T/card.json" CRIT-900 calidad
  CRITERIO="$T/CRITERIO.md" GATE_SCRIPT="$T/gate-ok.sh" run bash "$REPO/$ADOPT" "$T/card.json" <<< $'n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFLICT: Personal criterion in same ambito (calidad): CRIT-001"* ]]
}

@test "adopt: un ámbito con metacaracteres de regex no ejecuta código ni rompe" {
  printf 'CRIT-001 — Algo\n- ambito: calidad\n' > "$T/CRITERIO.md"
  _card "$T/card.json" CRIT-900 "(.*"
  CRITERIO="$T/CRITERIO.md" GATE_SCRIPT="$T/gate-ok.sh" run bash "$REPO/$ADOPT" "$T/card.json" <<< $'n\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"No conflicts with personal criterion."* ]]
}
