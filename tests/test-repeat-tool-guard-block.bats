#!/usr/bin/env bats
# tests/test-repeat-tool-guard-block.bats — SE-445 S1: guard de repetición bloqueante (AC1, AC2).
# Ref: docs/specs/SE-445-autonomous-execution-safeguards.spec.md

setup() {
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/.claude" "$FIX/output"
  ln -s "$REAL_ROOT/scripts" "$FIX/scripts"
  ln -s "$REAL_ROOT/.claude/hooks" "$FIX/.claude/hooks"
  git -C "$FIX" init -q -b main
  git -C "$FIX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  HOOK="$REAL_ROOT/.claude/hooks/repeat-tool-guard.sh"
  unset SAVIA_LOOP_GUARD SAVIA_LOOP_EXCLUDE SAVIA_LOOP_BLOCK SAVIA_AUTONOMOUS_RUN SAVIA_LOOP_WINDOW_SECONDS
}

on_branch() { git -C "$FIX" switch -q -C "$1"; }

# call <event> <session> <tool> <json-input> [agent_id]
call_ev() {
  local payload
  payload=$(python3 -c '
import json,sys
d={"hook_event_name":sys.argv[1],"session_id":sys.argv[2],"tool_name":sys.argv[3],"tool_input":json.loads(sys.argv[4])}
if len(sys.argv)>5: d["agent_id"]=sys.argv[5]
print(json.dumps(d))' "$@")
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$FIX" bash "$HOOK"
}
call() { call_ev PreToolUse "$@"; }

@test "AC1: en agent/x la 3a llamada identica sale con 2; la 2a con 0 y recordatorio" {
  on_branch agent/x
  run call s1 Bash '{"command":"ls /tmp"}'
  [ "$status" -eq 0 ]
  run call s1 Bash '{"command":"ls /tmp"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"loop-guard"* ]]
  run call s1 Bash '{"command":"ls /tmp"}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"Handback"* ]]
}

@test "AC1: sigue bloqueando la 4a llamada identica" {
  on_branch agent/x
  for i in 1 2; do call s2 Bash '{"command":"ls /tmp"}' >/dev/null 2>&1; done
  run call s2 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 2 ]
  run call s2 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 2 ]
}

@test "AC1: una llamada distinta reinicia la cadena" {
  on_branch agent/x
  call s3 Bash '{"command":"ls /tmp"}' >/dev/null 2>&1
  call s3 Bash '{"command":"ls /tmp"}' >/dev/null 2>&1
  call s3 Bash '{"command":"pwd"}' >/dev/null 2>&1
  run call s3 Bash '{"command":"ls /tmp"}'
  [ "$status" -eq 0 ]
}

@test "AC1: SAVIA_LOOP_EXCLUDE=Bash no bloquea" {
  on_branch agent/x
  export SAVIA_LOOP_EXCLUDE=Bash
  for i in 1 2 3 4 5; do run call s4 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 0 ]; done
}

@test "AC1: el orden de claves de los argumentos no evita el bloqueo" {
  on_branch agent/x
  call s5 Grep '{"pattern":"x","path":"a"}' >/dev/null 2>&1
  call s5 Grep '{"path":"a","pattern":"x"}' >/dev/null 2>&1
  run call s5 Grep '{"pattern":"x","path":"a"}'
  [ "$status" -eq 2 ]
}

@test "AC1: sesiones y subagentes distintos no comparten cadena" {
  on_branch agent/x
  call s6 Bash '{"command":"ls"}' a1 >/dev/null 2>&1
  call s6 Bash '{"command":"ls"}' a2 >/dev/null 2>&1
  run call s6 Bash '{"command":"ls"}' a1
  [ "$status" -eq 0 ]
  run call other Bash '{"command":"ls"}'
  [ "$status" -eq 0 ]
}

@test "AC2: en feature/x humana sin SAVIA_LOOP_GUARD nunca bloquea" {
  on_branch feature/x
  for i in 1 2 3 4 5 6; do run call h1 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 0 ]; done
}

@test "AC2: en main tampoco bloquea" {
  for i in 1 2 3 4; do run call h2 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 0 ]; done
}

@test "AC2: SAVIA_LOOP_GUARD=1 en rama humana no convierte el guard en bloqueante" {
  on_branch feature/x
  export SAVIA_LOOP_GUARD=1
  for i in 1 2 3 4; do run call h3 Bash '{"command":"ls /tmp"}'; [ "$status" -eq 0 ]; done
}

@test "SAVIA_AUTONOMOUS_RUN=1 activa el modo bloqueante fuera de agent/*" {
  on_branch feature/x
  export SAVIA_AUTONOMOUS_RUN=1
  call a1 Bash '{"command":"ls"}' >/dev/null 2>&1
  call a1 Bash '{"command":"ls"}' >/dev/null 2>&1
  run call a1 Bash '{"command":"ls"}'
  [ "$status" -eq 2 ]
}

@test "SAVIA_LOOP_BLOCK=off desactiva el bloqueo en agent/*" {
  on_branch agent/x
  export SAVIA_LOOP_BLOCK=off
  for i in 1 2 3 4; do run call o1 Bash '{"command":"ls"}'; [ "$status" -eq 0 ]; done
}

@test "PostToolUse en agent/* no cuenta ni bloquea (sin doble conteo)" {
  on_branch agent/x
  for i in 1 2 3 4; do
    run call_ev PostToolUse p1 Bash '{"command":"ls"}'
    [ "$status" -eq 0 ]
  done
  run call p1 Bash '{"command":"ls"}'
  [ "$status" -eq 0 ]
}

@test "stdout limpio: el hook no escribe en stdout (OpenCode trata stdout no JSON como bloqueo)" {
  on_branch agent/x
  call so Bash '{"command":"ls"}' >/dev/null 2>&1
  out=$(call so Bash '{"command":"ls"}' 2>/dev/null)
  [ -z "$out" ]
}

@test "una cadena vieja (fuera de ventana) no cuenta como consecutiva" {
  on_branch agent/x
  export SAVIA_LOOP_WINDOW_SECONDS=1
  call w1 Bash '{"command":"ls"}' >/dev/null 2>&1
  call w1 Bash '{"command":"ls"}' >/dev/null 2>&1
  sleep 2
  run call w1 Bash '{"command":"ls"}'
  [ "$status" -eq 0 ]
}
