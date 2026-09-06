#!/usr/bin/env bats
# SE-387 B (revisión 2026-09-05): close exige MERGED real, dentro de f5-state.sh.
S="scripts/f5-state.sh"
BIN="tests/bats/.bin-f5"; mkdir -p "$BIN"
stub_gh() { printf '#!/usr/bin/env bash\nif [ "$1" = "pr" ]; then echo %s; exit 0; fi\nexit 0\n' "$1" > "$BIN/gh"; chmod +x "$BIN/gh"; }

@test "close con PR OPEN => BLOCK (exit 2), estado NO se cierra" {
  printf '{"op":"pr.merge","key":"kA","state":"submitted"}' > "$HOME/.savia/reservations/pr.merge__kA.json"
  stub_gh OPEN
  run env PATH="$BIN:$PATH" bash "$S" close pr.merge kA
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
  [ "$(bash "$S" status pr.merge kA)" = "submitted" ]
}

@test "auto-merge aceptado pero state != MERGED => sigue submitted, NUNCA closed" {
  printf '{"op":"pr.merge","key":"kB","state":"submitted"}' > "$HOME/.savia/reservations/pr.merge__kB.json"
  stub_gh OPEN
  run env PATH="$BIN:$PATH" bash "$S" close pr.merge kB
  [ "$status" -eq 2 ]
  [ "$(bash "$S" status pr.merge kB)" = "submitted" ]
}

@test "close con PR MERGED => closed + receipt" {
  printf '{"op":"pr.merge","key":"kC","state":"submitted"}' > "$HOME/.savia/reservations/pr.merge__kC.json"
  stub_gh MERGED
  run env PATH="$BIN:$PATH" bash "$S" close pr.merge kC
  [ "$status" -eq 0 ]
  [ "$(bash "$S" status pr.merge kC)" = "closed" ]
}

@test "retry desde submitted con PR MERGED => close + ALREADY_EXECUTED" {
  printf '{"op":"pr.merge","key":"kD","state":"submitted"}' > "$HOME/.savia/reservations/pr.merge__kD.json"
  stub_gh MERGED
  run env PATH="$BIN:$PATH" bash "$S" reserve pr.merge kD
  [ "$status" -eq 3 ]
  [[ "$output" == *"ALREADY_EXECUTED"* ]]
  [ "$(bash "$S" status pr.merge kD)" = "closed" ]
}
