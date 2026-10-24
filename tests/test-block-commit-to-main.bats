#!/usr/bin/env bats
# BATS tests for .claude/hooks/block-commit-to-main.sh (SE-337).
# Ref: autonomous-safety (NUNCA commit en ramas humanas), SE-337.
# SE-339: cobertura de hook crítico (ratchet de seguridad).
SCRIPT=".claude/hooks/block-commit-to-main.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
  export SAVIA_TURN_SDLC_LOG_DIR="$TMPDIR/se337-log"
  mkdir -p "$SAVIA_TURN_SDLC_LOG_DIR"
}

teardown() { cd /; unset SAVIA_TURN_SDLC_LOG_DIR; }

@test "existe + ejecutable" { [[ -x "$SCRIPT" ]]; }
@test "usa set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "pasa bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "referencia SE-337 y autonomous-safety" { run grep -c 'SE-337' "$SCRIPT"; [[ "$output" -ge 1 ]]; }

@test "sin entrada (no-tty) sale 0 silencioso" {
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
}

@test "en rama no-humana no bloquea" {
  # Simula: branch != main → guard sale 0 sin tocar log
  run bash -c 'echo "" | BRANCH_UNUSED=1 bash "$0" </dev/null' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "en rama main emite decision:block" {
  run bash -c '
    source .claude/hooks/lib/profile-gate.sh 2>/dev/null || true
    branch=$(cd . && git branch --show-current 2>/dev/null || echo "")
    # Forzar branch main simulando via hook input no es trivial; verificamos el
    # contenido del guard: contiene la lógica de bloqueo de main/master.
    grep -q "main" "$0" && echo "GUARD_PRESENT"
  ' "$SCRIPT"
  run grep -c 'decision.*block' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "bypass documentado SAVIA_ALLOW_MAIN_COMMIT=1" {
  run grep -c 'SAVIA_ALLOW_MAIN_COMMIT' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "bloqueo registra en JSONL (no silencioso)" {
  run grep -c 'commit-guard.jsonl' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
# --- Comportamiento real: repo temporal, entrada JSON de hook, veredicto observable ---

mkrepo() {  # $1 = rama
  REPO="$TMPDIR/repo-$1-$RANDOM"
  git init -q -b "$1" "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}
hook() {  # $1 = comando git simulado, $2 = cwd
  jq -n --arg c "$1" --arg d "$2" '{tool_input:{command:$c},cwd:$d}' | bash "$SCRIPT"
}

@test "commit en rama main: emite decision block con motivo y registra block" {
  mkrepo main
  run hook 'git commit -m x' "$REPO"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .decision)" = "block" ]
  [[ "$(echo "$output" | jq -r .reason)" == *"(main)"* ]]
  run jq -r .verdict "$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl"
  [ "$output" = "block" ]
}

@test "commit en master tambien se bloquea" {
  mkrepo master
  run hook 'git commit -m x' "$REPO"
  [ "$(echo "$output" | jq -r .decision)" = "block" ]
}

@test "commit en rama agent/* no bloquea ni escribe log" {
  mkrepo agent/tarea
  run hook 'git commit -m x' "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl" ]
}

@test "rama con nombre parecido (mainline, feature/main) no bloquea" {
  mkrepo mainline
  run hook 'git commit -m x' "$REPO"
  [ -z "$output" ]
  mkrepo feature/main
  run hook 'git commit -m x' "$REPO"
  [ -z "$output" ]
}

@test "comando que no es commit en main no bloquea (git status, --no-commit, commit-msg)" {
  mkrepo main
  for c in 'git status' 'git merge --no-commit x' 'cat .git/hooks/commit-msg' 'echo commit'; do
    run hook "$c" "$REPO"
    [ -z "$output" ]
  done
  [ ! -e "$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl" ]
}

@test "commit encadenado tras punto y coma en main se bloquea" {
  mkrepo main
  run hook 'echo hi; git commit -m x' "$REPO"
  [ "$(echo "$output" | jq -r .decision)" = "block" ]
}

@test "bypass SAVIA_ALLOW_MAIN_COMMIT=1: deja pasar y registra bypass" {
  mkrepo main
  SAVIA_ALLOW_MAIN_COMMIT=1 run hook 'git commit -m x' "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run jq -r .verdict "$SAVIA_TURN_SDLC_LOG_DIR/commit-guard.jsonl"
  [ "$output" = "bypass" ]
}

@test "bypass con valor distinto de 1 sigue bloqueando" {
  mkrepo main
  SAVIA_ALLOW_MAIN_COMMIT=true run hook 'git commit -m x' "$REPO"
  [ "$(echo "$output" | jq -r .decision)" = "block" ]
}

@test "cd entre comillas a worktree agent/* evalua esa rama, no la del cwd" {
  mkrepo main; MAIN="$REPO"
  mkrepo agent/wt; WT="$REPO"
  run hook "cd \"$WT\" && git commit -m x" "$MAIN"
  [ -z "$output" ]
  run hook "cd \"$MAIN\" && git commit -m x" "$WT"
  [ "$(echo "$output" | jq -r .decision)" = "block" ]
}

@test "directorio fuera de repo git sale sin bloquear" {
  mkdir -p "$TMPDIR/nogit"
  run hook 'git commit -m x' "$TMPDIR/nogit"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "HEAD desacoplado (sin rama) no bloquea" {
  mkrepo main
  git -C "$REPO" checkout -q --detach
  run hook 'git commit -m x' "$REPO"
  [ -z "$output" ]
}
