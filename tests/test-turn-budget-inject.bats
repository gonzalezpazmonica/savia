#!/usr/bin/env bats
# tests/test-turn-budget-inject.bats — SE-445 S2 (AC3): presupuesto de turnos visible en agentes autonomos.
# Ref: docs/specs/SE-445-autonomous-execution-safeguards.spec.md

setup() {
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/.claude" "$FIX/output/turn-budget"
  ln -s "$REAL_ROOT/scripts" "$FIX/scripts"
  git -C "$FIX" init -q -b main
  git -C "$FIX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  HOOK="$REAL_ROOT/.claude/hooks/turn-budget-inject.sh"
  unset SAVIA_TURN_BUDGET SAVIA_AUTONOMOUS_RUN
  export SAVIA_TURN_BUDGET_MAX=40 SAVIA_TURN_BUDGET_MINUTES=15
}

on_branch() { git -C "$FIX" switch -q -C "$1"; }
call() { # session [event]
  printf '{"hook_event_name":"%s","session_id":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "${2:-PreToolUse}" "$1" \
    | CLAUDE_PROJECT_DIR="$FIX" bash "$HOOK"
}
seed() { # session turns minutes_ago
  python3 -c '
import json,sys,time
json.dump({"turns":int(sys.argv[2]),"start":time.time()-60*float(sys.argv[3])}, open(sys.argv[1],"w"))' \
    "$FIX/output/turn-budget/$1.json" "$2" "$3"
}
ctx() { printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }

@test "AC3: turnos 7/40 y minutos restantes 9; tras otro turno solo figura el bloque nuevo" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed b1 6 6
  run call b1
  [ "$status" -eq 0 ]
  c=$(ctx)
  [[ "$c" == *"turnos 7/40"* ]]
  [[ "$c" == *"minutos restantes 9"* ]]
  run call b1
  c=$(ctx)
  [[ "$c" == *"turnos 8/40"* ]]
  [[ "$c" != *"turnos 7/40"* ]]
}

@test "AC3: el bloque declara que sustituye a los anteriores y nivel N1" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  run call b2
  [[ "$(ctx)" == *"sustituye"* ]]
  [[ "$output" == *'"saviaLevel"'*'N1'* ]]
}

@test "AC3: con poco presupuesto pide converger" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed b3 38 14
  run call b3
  [[ "$(ctx)" == *"converge"* ]]
}

@test "AC3: tiempo agotado no muestra minutos negativos" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed b4 3 99
  run call b4
  [[ "$(ctx)" == *"minutos restantes 0"* ]]
}

@test "sin SAVIA_TURN_BUDGET=on no emite nada" {
  on_branch agent/x
  run call b5
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fuera de modo autonomo (rama humana) no emite nada" {
  on_branch feature/x
  export SAVIA_TURN_BUDGET=on
  run call b6
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "UserPromptSubmit emite el bloque sin incrementar el contador" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed b7 5 1
  run call b7 UserPromptSubmit
  [[ "$(ctx)" == *"turnos 5/40"* ]]
  [[ "$output" == *UserPromptSubmit* ]]
}
