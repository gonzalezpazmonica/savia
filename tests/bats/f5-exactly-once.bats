#!/usr/bin/env bats
# SE-387 C/F5 — exactly-once: retry/crash sobre el mecanismo de reservation.
R="$HOME/.savia/reservations"
K="bats-test-1"

setup() { rm -f "$R/pr.merge__$K.json"; }

@test "F5: reserve crea reservation en estado reserved" {
  run bash scripts/effect-reservation.sh reserve pr.merge "$K"
  [ "$status" -eq 0 ]
  st=$(jq -r .state "$R/pr.merge__$K.json"); [ "$st" = "reserved" ]
}

@test "F5: retry tras crash (reserved sin close) PERMITE completar una vez" {
  bash scripts/effect-reservation.sh reserve pr.merge "$K" >/dev/null
  run bash scripts/effect-reservation.sh reserve pr.merge "$K"
  [ "$status" -eq 0 ]  # reserved (crash previo) permite reintento de completion
}

@test "F5: close + retry => ALREADY_EXECUTED (exit 3, no duplica)" {
  bash scripts/effect-reservation.sh reserve pr.merge "$K" >/dev/null
  bash scripts/effect-reservation.sh close pr.merge "$K" >/dev/null
  run bash scripts/effect-reservation.sh reserve pr.merge "$K"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ALREADY_EXECUTED"* ]]
}
