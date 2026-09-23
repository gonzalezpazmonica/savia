#!/usr/bin/env bats
# SE-387 C/F5 — 7 casos exigidos por la operadora (máquina de estados + orden).
S="scripts/f5-state.sh"
P="scripts/push-pr.sh"

setup() {
  export SAVIA_RESERVATIONS="$BATS_TEST_TMPDIR/reservations"
  mkdir -p "$SAVIA_RESERVATIONS" "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${F5_TEST_REMOTE_STATE:-OPEN}"\n' \
    > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "orden: grant y risk-tier se validan ANTES de crear reservation (casos 1-2)" {
  g=$(grep -n "operator-grant.sh check" "$P" | head -1 | cut -d: -f1)
  r=$(grep -n "risk-tier" "$P" | head -1 | cut -d: -f1)
  f=$(grep -n "f5-state.sh\" reserve" "$P" | head -1 | cut -d: -f1)
  [ "$g" -lt "$f" ] && [ "$r" -lt "$f" ]
}

@test "F5 caso 3: crash antes del merge (reserved) permite reanudar" {
  run bash "$S" reserve pr.merge k3
  [ "$status" -eq 0 ]
  run bash "$S" reserve pr.merge k3
  [ "$status" -eq 0 ]
  [ "$(bash "$S" status pr.merge k3)" = "reserved" ]
}

@test "F5 caso 4: crash tras solicitar merge (submitted) permite reanudar" {
  bash "$S" reserve pr.merge k4 >/dev/null
  bash "$S" mark_submitted pr.merge k4 >/dev/null
  run bash "$S" reserve pr.merge k4
  [ "$status" -eq 0 ]
  [ "$(bash "$S" status pr.merge k4)" = "submitted" ]
}

@test "F5 caso 5+6: merge completado -> close; retry tras CLOSED => ALREADY_EXECUTED" {
  bash "$S" reserve pr.merge k6 >/dev/null
  export F5_TEST_REMOTE_STATE=MERGED
  bash "$S" close pr.merge k6 >/dev/null
  run bash "$S" reserve pr.merge k6
  [ "$status" -eq 3 ]
  [[ "$output" == *"ALREADY_EXECUTED"* ]]
  [ "$(bash "$S" status pr.merge k6)" = "closed" ]
}

@test "F5 caso 7: PR mergeado externamente => ALREADY_EXECUTED" {
  printf '{"op":"pr.merge","key":"k7","state":"reserved"}' > "$SAVIA_RESERVATIONS/pr.merge__k7.json"
  export F5_TEST_REMOTE_STATE=MERGED
  run bash "$S" reserve pr.merge k7
  [ "$status" -eq 3 ]
  [[ "$output" == *"externamente"* || "$output" == *"ALREADY_EXECUTED"* ]]
  [ "$(bash "$S" status pr.merge k7)" = "closed" ]
}
