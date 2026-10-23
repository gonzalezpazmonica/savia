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

# --- S03c: fronteras de umbral, contadores por agente y entradas inválidas (SE-445 S2) ---

@test "SAVIA_AUTONOMOUS_RUN=1 activa el hook también en main" {
  on_branch main
  export SAVIA_TURN_BUDGET=on SAVIA_AUTONOMOUS_RUN=1
  run call r1
  [[ "$(ctx)" == *"turnos 1/40"* ]]
}

@test "umbral del 90 %: 35/40 no avisa, 36/40 sí (frontera)" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed u1 34 0
  run call u1
  [[ "$(ctx)" == *"turnos 35/40"* ]]
  [[ "$(ctx)" != *"converge"* ]]
  run call u1
  [[ "$(ctx)" == *"turnos 36/40"* ]]
  [[ "$(ctx)" == *"converge"* ]]
}

@test "umbral de tiempo: con 15 min, quedan 4 → sin aviso; quedan 3 → aviso (frontera)" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  seed t1 1 11
  run call t1
  [[ "$(ctx)" == *"minutos restantes 4"* ]]
  [[ "$(ctx)" != *"converge"* ]]
  seed t2 1 12
  run call t2
  [[ "$(ctx)" == *"minutos restantes 3"* ]]
  [[ "$(ctx)" == *"converge"* ]]
}

@test "estado: el contador persiste en output/turn-budget/<sesión>.json con start y turns" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  call s1 >/dev/null; call s1 >/dev/null; call s1 >/dev/null
  python3 - "$FIX/output/turn-budget/s1.json" <<'PY'
import json, sys, time
st = json.load(open(sys.argv[1]))
assert st["turns"] == 3, st
assert abs(time.time() - st["start"]) < 60, st
PY
}

@test "subagentes con agent_id distinto llevan contadores separados" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  pre() { printf '{"hook_event_name":"PreToolUse","session_id":"m1","agent_id":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$FIX" bash "$HOOK"; }
  pre alfa >/dev/null; pre alfa >/dev/null
  run pre beta
  [[ "$(ctx)" == *"turnos 1/40"* ]]
  run pre alfa
  [[ "$(ctx)" == *"turnos 3/40"* ]]
  [ -f "$FIX/output/turn-budget/m1.alfa.json" ]
  [ -f "$FIX/output/turn-budget/m1.beta.json" ]
}

@test "ids de sesión con ../ se sanean y el estado no escapa de output/turn-budget" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  run call '../../escape'
  [ "$status" -eq 0 ]
  [ ! -e "$FIX/escape.json" ]
  ls -a "$FIX/output/turn-budget" | grep -q '^\.\._\.\._escape\.json$'
}

@test "eventos distintos de PreToolUse/UserPromptSubmit no emiten ni cuentan" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  run call p1 PostToolUse
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$FIX/output/turn-budget/p1.json" ]
}

@test "JSON inválido o stdin vacío → salida vacía y exit 0 (nunca bloquea)" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  run bash -c "printf 'no json' | CLAUDE_PROJECT_DIR='$FIX' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c "printf '' | CLAUDE_PROJECT_DIR='$FIX' bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SAVIA_TURN_BUDGET_MAX no numérico cae al máximo por defecto 100" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on SAVIA_TURN_BUDGET_MAX=abc
  run call d1
  [[ "$(ctx)" == *"turnos 1/100"* ]]
}

@test "SAVIA_TURN_BUDGET_MAX=0 se eleva a 1 y avisa de inmediato" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on SAVIA_TURN_BUDGET_MAX=0
  run call d2
  [[ "$(ctx)" == *"turnos 1/1"* ]]
  [[ "$(ctx)" == *"converge"* ]]
}

@test "minutos: AGENT_TASK_TIMEOUT_MINUTES se usa si no hay SAVIA_TURN_BUDGET_MINUTES" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on AGENT_TASK_TIMEOUT_MINUTES=30
  unset SAVIA_TURN_BUDGET_MINUTES
  run call d3
  [[ "$(ctx)" == *"minutos restantes 30"* ]]
}

@test "estado corrupto se descarta y el contador vuelve a 1" {
  on_branch agent/x
  export SAVIA_TURN_BUDGET=on
  echo '{{{' > "$FIX/output/turn-budget/c1.json"
  run call c1
  [ "$status" -eq 0 ]
  [[ "$(ctx)" == *"turnos 1/40"* ]]
}
