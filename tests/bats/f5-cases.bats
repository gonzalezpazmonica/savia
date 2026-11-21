#!/usr/bin/env bats
# SPEC-387 C/F5 — máquina de estados, fail-closed y orden de autoridad.
SCRIPT="scripts/f5-state.sh"
PUSH_SCRIPT="scripts/push-pr.sh"
# Coverage: reserve/close exercise pr_state through the public command contract.

setup() {
  export SAVIA_ORIGINAL_PATH="$PATH"
  export SAVIA_RESERVATIONS="$BATS_TEST_TMPDIR/reservations"
  mkdir -p "$SAVIA_RESERVATIONS" "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${F5_TEST_REMOTE_STATE:-OPEN}"\n' \
    > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
  export PATH="$SAVIA_ORIGINAL_PATH"
}

@test "safety: target activa set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "orden: grant y risk-tier se validan ANTES de crear reservation (casos 1-2)" {
  g=$(grep -n "operator-grant.sh check" "$PUSH_SCRIPT" | head -1 | cut -d: -f1)
  r=$(grep -n "risk-tier" "$PUSH_SCRIPT" | head -1 | cut -d: -f1)
  f=$(grep -n "f5-state.sh\" reserve" "$PUSH_SCRIPT" | head -1 | cut -d: -f1)
  [ "$g" -lt "$f" ] && [ "$r" -lt "$f" ]
}

@test "F5 caso 3: crash antes del merge (reserved) permite reanudar" {
  run bash "$SCRIPT" reserve pr.merge 103
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" reserve pr.merge 103
  [ "$status" -eq 0 ]
  [ "$(bash "$SCRIPT" status pr.merge 103)" = "reserved" ]
}

@test "F5 caso 4: crash tras solicitar merge (submitted) permite reanudar" {
  bash "$SCRIPT" reserve pr.merge 104 >/dev/null
  bash "$SCRIPT" mark_submitted pr.merge 104 >/dev/null
  run bash "$SCRIPT" reserve pr.merge 104
  [ "$status" -eq 0 ]
  [ "$(bash "$SCRIPT" status pr.merge 104)" = "submitted" ]
}

@test "F5 caso 5+6: reject retry tras CLOSED con ALREADY_EXECUTED" {
  bash "$SCRIPT" reserve pr.merge 106 >/dev/null
  export F5_TEST_REMOTE_STATE=MERGED
  bash "$SCRIPT" close pr.merge 106 >/dev/null
  run bash "$SCRIPT" reserve pr.merge 106
  [ "$status" -eq 3 ]
  [[ "$output" == *"ALREADY_EXECUTED"* ]]
  [ "$(bash "$SCRIPT" status pr.merge 106)" = "closed" ]
}

@test "F5 caso 7: reject efecto externo ya ejecutado" {
  printf '{"op":"pr.merge","key":"107","state":"reserved"}' > "$SAVIA_RESERVATIONS/pr.merge__107.json"
  export F5_TEST_REMOTE_STATE=MERGED
  run bash "$SCRIPT" reserve pr.merge 107
  [ "$status" -eq 3 ]
  [[ "$output" == *"externamente"* || "$output" == *"ALREADY_EXECUTED"* ]]
  [ "$(bash "$SCRIPT" status pr.merge 107)" = "closed" ]
}

@test "F5 negativo: close bloquea estado remoto no mergeado" {
  bash "$SCRIPT" reserve pr.merge 108 >/dev/null
  run bash "$SCRIPT" close pr.merge 108
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
}

@test "F5 edge nonexistent reservation: mark_submitted falla cerrado" {
  run bash "$SCRIPT" mark_submitted pr.merge 109
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}
