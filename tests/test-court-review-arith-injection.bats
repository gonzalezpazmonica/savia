#!/usr/bin/env bats
# Ref: scripts/court-review.sh, scripts/court-turn-router.sh
# Inyección por evaluación aritmética de bash: $(( )), (( )) y [[ -gt ]]
# evalúan subíndices, así que un contador "HOME[$(cmd)]" ejecutaría cmd.
# Toda entrada aritmética (argumentos y variables de entorno) se valida como
# entero decimal antes de usarla, igual que en coherence-court.sh.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  ROOT_REAL="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COURT="$ROOT_REAL/scripts/court-review.sh"
  ROUTER="$ROOT_REAL/scripts/court-turn-router.sh"
  MARK="$TMPDIR/pwned"
  PAYLOAD="HOME[\$(touch $MARK)]"
  CRC="$TMPDIR/.review.crc"
  printf -- '---\nrounds:\n  []\n---\n' > "$CRC"
  FINDINGS="$TMPDIR/findings.json"
  echo '{"findings":[{"msg":"naming is unclear"}]}' > "$FINDINGS"
}

teardown() { cd /; }

@test "score: payload in C does not execute and exits 2" {
  run bash "$COURT" score "$PAYLOAD" 0 0 0
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
  [[ "$output" == *"C must be"* ]]
}

@test "score: payload in each of H, M, L is rejected without executing" {
  for pos in 2 3 4; do
    args=(0 0 0 0); args[$((pos - 1))]="$PAYLOAD"
    run bash "$COURT" score "${args[@]}"
    [ ! -e "$MARK" ]
    [ "$status" -eq 2 ]
  done
}

@test "score: non-numeric, negative and leading-zero counts are rejected" {
  for bad in abc -1 08 1.5 "" " 1"; do
    run bash "$COURT" score "$bad" 0 0 0
    [ "$status" -eq 2 ] || { echo "accepted: '$bad'"; return 1; }
  done
}

@test "score: oversized count cannot wrap 64-bit arithmetic into a pass" {
  run bash "$COURT" score 18446744073709551612 0 0 0
  [ "$status" -eq 2 ]
  [[ "$output" != *"verdict=pass"* ]]
}

@test "score: COURT_SCORE_PASS payload does not execute" {
  COURT_SCORE_PASS="$PAYLOAD" run bash "$COURT" score 0 0 0 0
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
  [[ "$output" == *"COURT_SCORE_PASS"* ]]
}

@test "score: COURT_SCORE_CONDITIONAL payload does not execute" {
  COURT_SCORE_CONDITIONAL="$PAYLOAD" run bash "$COURT" score 0 0 1 0
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
}

@test "score: valid counts keep the historical result" {
  run bash "$COURT" score 0 0 0 0
  [ "$status" -eq 0 ]
  [ "$output" = "score=100 verdict=pass (C=0 H=0 M=0 L=0)" ]
  run bash "$COURT" score 1 0 2 0
  [ "$status" -eq 0 ]
  [ "$output" = "score=69 verdict=fail (C=1 H=0 M=2 L=0)" ]
  run bash "$COURT" score
  [ "$status" -eq 0 ]
  [[ "$output" == score=100* ]]
}

@test "validate: COURT_MAX_FIX_ROUNDS payload does not execute" {
  COURT_MAX_FIX_ROUNDS="$PAYLOAD" run bash "$COURT" validate "$CRC"
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
  [[ "$output" == *"COURT_MAX_FIX_ROUNDS"* ]]
}

@test "validate: default and numeric COURT_MAX_FIX_ROUNDS still work" {
  run bash "$COURT" validate "$CRC"
  [ "$status" -eq 0 ]
  COURT_MAX_FIX_ROUNDS=3 run bash "$COURT" validate "$CRC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"max 3"* ]]
}

@test "check: COURT_MAX_LOC payload does not execute" {
  cd "$TMPDIR"
  COURT_MAX_LOC="$PAYLOAD" run bash "$COURT" check
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
  [[ "$output" == *"COURT_MAX_LOC"* ]]
}

@test "router: leading-zero --round is rejected instead of read as octal" {
  for bad in 08 010; do
    run bash "$ROUTER" --findings "$FINDINGS" --round "$bad"
    [ "$status" -eq 2 ] || { echo "accepted: '$bad'"; return 1; }
  done
  run bash "$ROUTER" --findings "$FINDINGS" --max-round 09
  [ "$status" -eq 2 ]
}

@test "router: payload in --round does not execute" {
  run bash "$ROUTER" --findings "$FINDINGS" --round "$PAYLOAD"
  [ ! -e "$MARK" ]
  [ "$status" -eq 2 ]
}

@test "router: valid rounds still route" {
  run bash "$ROUTER" --findings "$FINDINGS" --round 1 --max-round 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"cognitive-judge"* ]]
}
