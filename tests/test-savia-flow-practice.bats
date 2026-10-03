#!/usr/bin/env bats
# test-savia-flow-practice.bats — calibracion SE-376 de la skill savia-flow-practice
# Ref: .claude/skills/savia-flow-practice/SKILL.md
# Ref: docs/rules/domain/pm-workflow.md
# Ejercita los scripts reales de Savia Flow (imputacion de horas, sprints y
# tareas) contra un repo de empresa sintetico: bare + clon con espacios en la
# ruta. Ningun dato real de la operadora.

SCRIPT="scripts/savia-flow-timesheet.sh"
SPRINT_SH="scripts/savia-flow-sprint.sh"
TASKS_SH="scripts/savia-flow-tasks.sh"
FLOW_SH="scripts/savia-flow.sh"
BRANCH_SH="scripts/savia-branch.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  export HOME="$TMPDIR_TEST/home"
  mkdir -p "$HOME/.pm-workspace"
  git config --global user.email "flow@example.test"
  git config --global user.name "Flow Test"
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
  REPO="$TMPDIR_TEST/company repo"
  BARE="$TMPDIR_TEST/company.git"
  git init -q --bare "$BARE"
  git clone -q "$TMPDIR_TEST/company.git" "$REPO" 2>/dev/null
  mkdir -p "$REPO/projects/webapp"
  echo "# webapp" > "$REPO/projects/webapp/README.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm init
  git -C "$REPO" push -q origin HEAD 2>/dev/null
  printf 'LOCAL_PATH=%s\nUSER_HANDLE=alice\nTEAM_NAME=backend\n' "$REPO" \
    > "$HOME/.pm-workspace/company-repo"
  MONTH="$(date +%Y-%m)"
  TODAY="$(date +%Y-%m-%d)"
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

ts()     { bash "$ROOT/$SCRIPT" "$@"; }
sprint() { bash "$ROOT/$SPRINT_SH" "$@"; }
tasks()  { bash "$ROOT/$TASKS_SH" "$@"; }
flow()   { bash "$ROOT/$FLOW_SH" "$@"; }
show()   { git -C "$BARE" show "$1:$2"; }  # la verdad es el remoto, no el clon

# seed <branch> <path> <contenido>: publica un fichero en una rama del remoto
# (plumbing directo sobre el bare: no depende de do_write ni de un clon)
seed() {
  local idx="$TMPDIR_TEST/idx-$RANDOM" parent blob tree commit
  parent=$(git -C "$BARE" rev-parse -q --verify "refs/heads/$1" || true)
  if [ -n "$parent" ]; then GIT_INDEX_FILE="$idx" git -C "$BARE" read-tree "$parent"; fi
  blob=$(printf '%s\n' "$3" | git -C "$BARE" hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git -C "$BARE" update-index --add --cacheinfo 100644 "$blob" "$2"
  tree=$(GIT_INDEX_FILE="$idx" git -C "$BARE" write-tree)
  commit=$(git -C "$BARE" commit-tree "$tree" ${parent:+-p "$parent"} -m seed)
  git -C "$BARE" update-ref "refs/heads/$1" "$commit"
}

# use_clone <dir>: apunta la configuracion de empresa a otro clon del remoto
use_clone() {
  printf 'LOCAL_PATH=%s\nUSER_HANDLE=alice\nTEAM_NAME=backend\n' "$1" > "$HOME/.pm-workspace/company-repo"
}

# ── Contrato de los scripts ─────────────────────────────────────────

@test "set -uo pipefail: sin HOME los tres scripts fallan cerrados sin escribir (null)" {
  for f in "$SCRIPT" "$SPRINT_SH" "$TASKS_SH"; do
    run env -u HOME bash "$ROOT/$f" help
    [ "$status" -ne 0 ]
    [[ "$output" == *"HOME"* ]]
  done
  run env -u HOME bash "$ROOT/$SCRIPT" log alice TASK-0001 1 x
  [ "$status" -ne 0 ]
  run git -C "$BARE" rev-parse --verify -q user/alice
  [ "$status" -ne 0 ]
}

@test "timesheet: subcomando desconocido falla con exit 2 y help con exit 0" {
  run ts nope
  [ "$status" -eq 2 ]
  run ts help
  [ "$status" -eq 0 ]
  [[ "$output" == *"log"* ]]
}

@test "timesheet: sin repo de empresa configurado da error claro y exit 1" {
  : > "$HOME/.pm-workspace/company-repo"
  run ts log alice TASK-0001 2 "x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"company-repo"* ]]
  [[ "$output" != *"parameter null"* ]]
}

# ── Imputacion de horas ─────────────────────────────────────────────

@test "timesheet log: registra la entrada en user/<handle> y quita la @ del handle" {
  run ts log @alice TASK-0001 2 "API login"
  [ "$status" -eq 0 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| TASK-0001 | 2h | API login"* ]]
  run git -C "$BARE" rev-parse --verify -q "user/@alice"
  [ "$status" -ne 0 ]
}

@test "timesheet log: acepta coma decimal es_ES y la normaliza a punto" {
  LC_ALL=es_ES.UTF-8 run ts log alice TASK-0002 "1,5" "revision"
  [ "$status" -eq 0 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [[ "$output" == *"| TASK-0002 | 1.5h |"* ]]
}

@test "timesheet log: rechaza horas no numericas sin escribir nada (invalid)" {
  run ts log alice TASK-0001 abc "x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"horas"* ]]
  run show user/alice "flow/timesheet/$MONTH.md"
  [ "$status" -ne 0 ]
}

@test "timesheet log: rechaza cero y horas negativas (boundary zero)" {
  run ts log alice TASK-0001 0 "x"
  [ "$status" -eq 2 ]
  run ts log alice TASK-0001 -3 "x"
  [ "$status" -eq 2 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [ "$status" -ne 0 ]
}

@test "timesheet log: limite de 24 horas por entrada (boundary)" {
  run ts log alice TASK-0001 24 "maraton"
  [ "$status" -eq 0 ]
  run ts log alice TASK-0001 24.5 "imposible"
  [ "$status" -eq 2 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [[ "$output" == *"| 24h |"* ]]
  [[ "$output" != *"24.5h"* ]]
}

@test "timesheet log: rechaza handle o task_id con caracteres peligrosos (reject)" {
  run ts log "../evil" TASK-0001 1 "x"
  [ "$status" -eq 2 ]
  run ts log "alice bob" TASK-0001 1 "x"
  [ "$status" -eq 2 ]
  run ts log alice "TASK|1" 1 "x"
  [ "$status" -eq 2 ]
}

@test "timesheet log: notas con | y salto de linea no rompen el formato" {
  run ts log alice TASK-0003 1 $'a|b\nc'
  [ "$status" -eq 0 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  local n; n=$(echo "$output" | grep -c "TASK-0003")
  [ "$n" -eq 1 ]
  [[ "$output" == *"| TASK-0003 | 1h | a/b c"* ]]
}

@test "timesheet log: 6 imputaciones concurrentes: todas exit 0 y 7 entradas distintas" {
  ts log alice T-0 1 seed >/dev/null 2>&1
  local pids=() i p
  for i in 1 2 3 4 5 6; do
    ts log alice "T-$i" 1 n >/dev/null 2>&1 &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done
  run show user/alice "flow/timesheet/$MONTH.md"
  local n; n=$(echo "$output" | grep "| T-" | cut -d'|' -f2 | sort -u | wc -l)
  [ "$n" -eq 7 ]
}

@test "timesheet day: fecha invalida falla y dia sin entradas lo dice" {
  ts log alice TASK-0001 2 "x" >/dev/null 2>&1
  run ts day alice 2026-13-45
  [ "$status" -eq 2 ]
  run ts day alice "$TODAY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK-0001"* ]]
}

# ── Varios clones del mismo repo de empresa (uso real: un clon por persona) ──

@test "dos clones: imputaciones alternas A, B, A no se pierden en origin" {
  local B="$TMPDIR_TEST/clon b"
  git clone -q "$BARE" "$B" 2>/dev/null
  use_clone "$REPO"; run ts log alice T-A1 1 a; [ "$status" -eq 0 ]
  use_clone "$B";    run ts log alice T-B1 1 b; [ "$status" -eq 0 ]
  use_clone "$REPO"; run ts log alice T-A2 1 a; [ "$status" -eq 0 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [[ "$output" == *"| T-A1 |"* ]]
  [[ "$output" == *"| T-B1 |"* ]]
  [[ "$output" == *"| T-A2 |"* ]]
}

@test "dos clones: 3 + 3 imputaciones en paralelo publican las 6 (reintento tras push rechazado)" {
  local B="$TMPDIR_TEST/clon b" pids=() p i c
  git clone -q "$BARE" "$B" 2>/dev/null
  printf 'LOCAL_PATH=%s\nTEAM_NAME=backend\n' "$REPO" > "$TMPDIR_TEST/cfg-a"
  printf 'LOCAL_PATH=%s\nTEAM_NAME=backend\n' "$B" > "$TMPDIR_TEST/cfg-b"
  for i in 1 2 3; do
    for c in a b; do
      mkdir -p "$TMPDIR_TEST/h-$c-$i/.pm-workspace"
      cp "$TMPDIR_TEST/cfg-$c" "$TMPDIR_TEST/h-$c-$i/.pm-workspace/company-repo"
      cp "$HOME/.gitconfig" "$TMPDIR_TEST/h-$c-$i/.gitconfig"
      HOME="$TMPDIR_TEST/h-$c-$i" bash "$ROOT/$SCRIPT" log alice "T-$c$i" 1 n >/dev/null 2>&1 &
      pids+=("$!")
    done
  done
  for p in "${pids[@]}"; do wait "$p"; done
  run show user/alice "flow/timesheet/$MONTH.md"
  local n; n=$(echo "$output" | grep -E "\| T-[ab][123] \|" | cut -d'|' -f2 | sort -u | wc -l)
  [ "$n" -eq 6 ]
}

@test "dos clones: tasks create desde A y B da TASK-0001 y TASK-0002 en origin" {
  local B="$TMPDIR_TEST/clon b"
  git clone -q "$BARE" "$B" 2>/dev/null
  use_clone "$REPO"; run tasks create task "desde A"; [ "$status" -eq 0 ]
  use_clone "$B";    run tasks create task "desde B"; [ "$status" -eq 0 ]
  [[ "$output" == *"TASK-0002"* ]]
  run show team/backend projects/default/backlog/pbi-0001.md
  [[ "$output" == *'title: "desde A"'* ]]
  run show team/backend projects/default/backlog/pbi-0002.md
  [[ "$output" == *'title: "desde B"'* ]]
}

@test "remoto caido: log, sprint y task fallan con exit 1 y sin exito falso (fail)" {
  ts log alice T-0 1 seed >/dev/null 2>&1
  mv "$BARE" "$BARE.off"
  run ts log alice T-X1 1 x
  [ "$status" -eq 1 ]
  [[ "$output" == *"NO registrado"* ]]
  [[ "$output" != *"✅"* ]]
  run sprint create "Offline" 2026-10-05 2026-10-16
  [ "$status" -eq 1 ]
  [[ "$output" != *"✅"* ]]
  run tasks create task "Offline"
  [ "$status" -eq 1 ]
  [[ "$output" != *"✅"* ]]
  mv "$BARE.off" "$BARE"
  run ts log alice T-X3 1 x
  [ "$status" -eq 0 ]
  run show user/alice "flow/timesheet/$MONTH.md"
  [[ "$output" == *"| T-0 |"* ]]
  [[ "$output" == *"| T-X3 |"* ]]
  [[ "$output" != *"T-X1"* ]]
}

@test "push rechazado por el servidor (pre-receive): exit 1 sin reintentos ni exito falso (reject)" {
  printf '#!/bin/sh\necho "politica: rama cerrada" >&2\nexit 1\n' > "$BARE/hooks/pre-receive"
  chmod +x "$BARE/hooks/pre-receive"
  run ts log alice T-1 1 x
  [ "$status" -eq 1 ]
  [[ "$output" == *"NO registrado"* ]]
  [[ "$output" == *"pre-receive"* ]]
  [[ "$output" != *"6 veces"* ]]
  [[ "$output" != *"✅"* ]]
  run git -C "$BARE" rev-parse --verify -q user/alice
  [ "$status" -ne 0 ]
}

@test "remoto caido: report avisa de datos posiblemente desfasados" {
  ts log alice T-0 2 seed >/dev/null 2>&1
  mv "$BARE" "$BARE.off"
  run ts report alice "$TODAY" "$TODAY"
  mv "$BARE.off" "$BARE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"desfasados"* ]]
  [[ "$output" == *"Total: 2.00 h"* ]]
}

# ── Informe de horas ────────────────────────────────────────────────

@test "timesheet report: suma por tarea y total cruzando meses, rango inclusivo" {
  seed user/alice flow/timesheet/2026-09.md $'# Timesheet\n2026-09-29 10:00 | TASK-0001 | 2h | a\n2026-09-30 10:00 | TASK-0002 | 1.5h | b\n2026-09-15 10:00 | TASK-0009 | 8h | fuera'
  seed user/alice flow/timesheet/2026-10.md $'# Timesheet\n2026-10-01 09:00 | TASK-0001 | 3h | c\n2026-10-02 09:00 | TASK-0009 | 5h | fuera'
  run ts report alice 2026-09-29 2026-10-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK-0001: 5.00 h"* ]]
  [[ "$output" == *"TASK-0002: 1.50 h"* ]]
  [[ "$output" == *"Total: 6.50 h"* ]]
  [[ "$output" != *"TASK-0009"* ]]
}

@test "timesheet report: con locale es_ES el total sigue siendo correcto" {
  seed user/alice flow/timesheet/2026-09.md $'2026-09-29 10:00 | TASK-0001 | 1.25h | a\n2026-09-30 10:00 | TASK-0001 | 0.5h | b'
  LC_ALL=es_ES.UTF-8 run ts report alice 2026-09-01 2026-09-30
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 1.75 h"* ]]
}

@test "timesheet report: entradas legado no numericas se ignoran y se cuentan" {
  seed user/alice flow/timesheet/2026-09.md $'2026-09-29 10:00 | TASK-0001 | abch | legado\n2026-09-30 10:00 | TASK-0001 | 2h | ok'
  run ts report alice 2026-09-01 2026-09-30
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2.00 h"* ]]
  [[ "$output" == *"ignoradas: 1"* ]]
}

@test "timesheet report: rango vacio da total cero (empty)" {
  run ts report alice 2026-01-01 2026-01-31
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 0.00 h"* ]]
}

@test "timesheet report: rechaza fechas invalidas y desde > hasta (error)" {
  run ts report alice 2026-02-30 2026-03-01
  [ "$status" -eq 2 ]
  run ts report alice 2026-10-05 2026-10-01
  [ "$status" -eq 2 ]
  run ts report alice
  [ "$status" -eq 2 ]
}

# ── Sprint ──────────────────────────────────────────────────────────

@test "sprint create: crea SPR-<anio>-01 y luego -02 con todos los campos" {
  run sprint create "MVP login" 2026-10-05 2026-10-16 80
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPR-2026-01"* ]]
  run sprint create "Pagos" 2026-10-19 2026-10-30
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPR-2026-02"* ]]
  run show team/backend projects/backlog/sprints/SPR-2026-01/sprint.md
  [[ "$output" == *"goal: MVP login"* ]]
  [[ "$output" == *"capacity_h: 80"* ]]
  [[ "$output" == *"status: active"* ]]
  run show team/backend projects/backlog/sprints/SPR-2026-02/sprint.md
  [[ "$output" == *"capacity_h: 120"* ]]
}

@test "sprint create: el anio del ID sale de la fecha de inicio, no del reloj" {
  run sprint create "Arranque" 2027-01-04 2027-01-15
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPR-2027-01"* ]]
}

@test "sprint create: rechaza fechas invalidas, fin < inicio, capacidad y goal vacio (invalid)" {
  run sprint create "G" 2026-02-30 2026-03-10
  [ "$status" -eq 2 ]
  run sprint create "G" 2026-10-16 2026-10-05
  [ "$status" -eq 2 ]
  run sprint create "G" 2026-10-05 2026-10-16 abc
  [ "$status" -eq 2 ]
  run sprint create "G" 2026-10-05 2026-10-16 0
  [ "$status" -eq 2 ]
  run sprint create "" 2026-10-05 2026-10-16
  [ "$status" -eq 2 ]
  run git -C "$BARE" rev-parse --verify -q team/backend
  [ "$status" -ne 0 ]
}

@test "sprint create: dos creaciones concurrentes obtienen IDs distintos" {
  sprint create "A" 2026-10-05 2026-10-16 >/dev/null 2>&1 &
  local p1=$!
  sprint create "B" 2026-10-05 2026-10-16 >/dev/null 2>&1 &
  local p2=$!
  wait "$p1" "$p2"
  run git -C "$BARE" ls-tree --name-only team/backend projects/backlog/sprints/
  local n; n=$(echo "$output" | grep -c "SPR-2026-0")
  [ "$n" -eq 2 ]
}

@test "sprint close: cierra, fija fecha y board muestra el estado" {
  sprint create "MVP" 2026-10-05 2026-10-16 >/dev/null 2>&1
  run sprint close SPR-2026-01
  [ "$status" -eq 0 ]
  run show team/backend projects/backlog/sprints/SPR-2026-01/sprint.md
  [[ "$output" == *"status: closed"* ]]
  [[ "$output" == *"closed: $TODAY"* ]]
  run sprint board SPR-2026-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"closed"* ]]
  [[ "$output" == *"MVP"* ]]
}

@test "sprint close: cerrar dos veces conserva la fecha de cierre original" {
  seed team/backend projects/backlog/sprints/SPR-2026-01/sprint.md $'---\nid: SPR-2026-01\ngoal: Viejo\nstatus: closed\nclosed: 2026-01-01\n---'
  run sprint close SPR-2026-01
  [ "$status" -eq 0 ]
  run show team/backend projects/backlog/sprints/SPR-2026-01/sprint.md
  [[ "$output" == *"closed: 2026-01-01"* ]]
}

@test "sprint close: sprint inexistente falla y un ID mal formado se rechaza (error)" {
  run sprint close SPR-2026-07
  [ "$status" -eq 1 ]
  run sprint close "../x"
  [ "$status" -eq 2 ]
}

@test "sprint velocity: lista sprints con estado; burndown no implementado" {
  sprint create "A" 2026-10-05 2026-10-16 >/dev/null 2>&1
  sprint create "B" 2026-10-19 2026-10-30 >/dev/null 2>&1
  sprint close SPR-2026-01 >/dev/null 2>&1
  run sprint velocity
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPR-2026-01"*"closed"* ]]
  [[ "$output" == *"SPR-2026-02"*"active"* ]]
  run sprint burndown SPR-2026-01
  [ "$status" -eq 2 ]
}

@test "sprint: al hacer source no ejecuta el CLI ni pisa get_repo del llamador" {
  run bash -c 'get_repo() { echo propio; }; source "$1"; get_repo' _ "$ROOT/$SPRINT_SH"
  [ "$status" -eq 0 ]
  [ "$output" = "propio" ]
}

@test "savia-flow sprint-close: cierra el sprint activo, no el mas antiguo" {
  flow sprint-start webapp s1 "uno" 2026-09-01 2026-09-12 >/dev/null 2>&1
  flow sprint-close webapp >/dev/null 2>&1
  flow sprint-start webapp s2 "dos" 2026-09-15 2026-09-26 >/dev/null 2>&1
  run flow sprint-close webapp
  [ "$status" -eq 0 ]
  [[ "$output" == *"s2"* ]]
  run show team/backend projects/webapp/sprints/s2/sprint.md
  [[ "$output" == *'status: "closed"'* ]]
}

@test "savia-flow sprint-close: sin sprint activo falla (null)" {
  run flow sprint-close webapp
  [ "$status" -eq 1 ]
}

@test "savia-flow metrics: cuenta total y done de verdad (no 0 por subshell)" {
  seed team/backend projects/webapp/backlog/pbi-001.md $'---\nid: "PBI-001"\nstatus: "done"\n---'
  seed team/backend projects/webapp/backlog/pbi-002.md $'---\nid: "PBI-002"\nstatus: "new"\n---'
  run flow metrics webapp
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2 | Done: 1"* ]]
}

# ── Tareas ──────────────────────────────────────────────────────────

@test "tasks create: la segunda tarea no pisa la primera (TASK-0001, TASK-0002)" {
  run tasks create task "Primera"
  [ "$status" -eq 0 ]
  run tasks create bug "Segunda"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK-0002"* ]]
  run show team/backend projects/default/backlog/pbi-0001.md
  [[ "$output" == *'title: "Primera"'* ]]
  run show team/backend projects/default/backlog/pbi-0002.md
  [[ "$output" == *'title: "Segunda"'* ]]
}

@test "tasks create: guarda sprint existente y rechaza sprint inexistente" {
  sprint create "MVP" 2026-10-05 2026-10-16 >/dev/null 2>&1
  run tasks create task "Con sprint" @bob SPR-2026-01 high
  [ "$status" -eq 0 ]
  run show team/backend projects/default/backlog/pbi-0001.md
  [[ "$output" == *'sprint: "SPR-2026-01"'* ]]
  [[ "$output" == *'assigned: "bob"'* ]]
  [[ "$output" == *'priority: "high"'* ]]
  run tasks create task "Huerfana" bob SPR-2026-09
  [ "$status" -eq 1 ]
}

@test "tasks create: rechaza tipo, prioridad y titulo de mas de 100 caracteres (invalid)" {
  run tasks create epic "X"
  [ "$status" -eq 2 ]
  run tasks create task "X" bob "" urgent
  [ "$status" -eq 2 ]
  run tasks create task "$(printf 'a%.0s' {1..101})"
  [ "$status" -eq 2 ]
  run tasks create task "$(printf 'a%.0s' {1..100})"
  [ "$status" -eq 0 ]
}

@test "tasks create: 3 altas en paralelo dan 3 tareas distintas (concurrencia)" {
  local pids=() p i
  for i in 1 2 3; do
    tasks create task "Paralela $i" >/dev/null 2>&1 &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done
  run git -C "$BARE" ls-tree --name-only team/backend projects/default/backlog/
  [ "$(echo "$output" | grep -c 'pbi-000[123].md')" -eq 3 ]
  local t; t=$(for i in 1 2 3; do git -C "$BARE" show "team/backend:projects/default/backlog/pbi-000$i.md" | grep '^title:'; done | sort -u | wc -l)
  [ "$t" -eq 3 ]
}

@test "tasks move, assign y list operan sobre la tarea real" {
  tasks create task "Login" >/dev/null 2>&1
  run tasks move TASK-0001 in-progress
  [ "$status" -eq 0 ]
  run tasks assign TASK-0001 @carol
  [ "$status" -eq 0 ]
  run show team/backend projects/default/backlog/pbi-0001.md
  [[ "$output" == *'status: "in-progress"'* ]]
  [[ "$output" == *'assigned: "carol"'* ]]
  run tasks list
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASK-0001"*"in-progress"*"carol"* ]]
}

@test "tasks move: estado invalido y tarea inexistente fallan (reject)" {
  tasks create task "Login" >/dev/null 2>&1
  run tasks move TASK-0001 blocked
  [ "$status" -eq 2 ]
  run tasks move TASK-0099 done
  [ "$status" -eq 1 ]
}
