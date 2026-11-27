#!/usr/bin/env bats
# SE-498 AC-10 — el bucle nocturno no interpreta la descripción de la tarea como
# código y no corre sin límite de tiempo.
#
# Antes: overnight-sprint-loop.sh metía '$description' dentro de
# `bash -c "run_agent_task '…' '$description' …"`; una comilla en la descripción
# ejecutaba órdenes arbitrarias (y la tarea contaba como hecha). Sin `timeout`
# en PATH, la tarea corría sin límite.

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    LOOP="$PWD/scripts/overnight-sprint-loop.sh"
    T="$BATS_TEST_TMPDIR"
    export OVERNIGHT_COHERENCE_GATE=off
}

# Escribe un tasks.json con una descripción arbitraria (sin pasar por el shell).
_tasks_with() {
    python3 -I -c 'import json,sys; json.dump([{"id":1,"description":sys.argv[2],"status":"pending"}], open(sys.argv[1],"w"))' "$1" "$2"
}

_run_loop() {
    run env SAVIA_WORKSPACE_DIR="$T/ws-$1" PATH="${2:-$PATH}" \
        bash "$LOOP" --sprint-id "$1" --tasks "$T/tasks-$1.json" --max-tasks 1 --dry-run
}

@test "AC-10: comilla simple en la descripción no ejecuta órdenes" {
    _tasks_with "$T/tasks-q.json" "x'; touch $T/PWNED-q; echo '"
    _run_loop q
    [[ ! -e "$T/PWNED-q" ]]
}

@test "AC-10: \$(…) y acentos graves en la descripción no se expanden" {
    _tasks_with "$T/tasks-s.json" "\$(touch $T/PWNED-s) \`touch $T/PWNED-b\`"
    _run_loop s
    [[ ! -e "$T/PWNED-s" ]]
    [[ ! -e "$T/PWNED-b" ]]
}

@test "AC-10: una descripción maliciosa no cuenta como tarea hecha por la inyección" {
    _tasks_with "$T/tasks-d.json" "x'; touch $T/PWNED-d; echo '"
    _run_loop d
    # La descripción llega literal a run_agent_task (DRY-RUN la imprime tal cual).
    [[ "$output" == *"DRY-RUN: would execute task 1 'x'; touch $T/PWNED-d; echo ''"* ]]
    [[ ! -e "$T/PWNED-d" ]]
}

@test "AC-10 positivo: con descripción normal la tarea se ejecuta (run_agent_task exportada)" {
    _tasks_with "$T/tasks-n.json" "tarea normal"
    _run_loop n
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"orden no encontrada"* ]]
    [[ "$output" != *"command not found"* ]]
    [[ "$output" == *"DRY-RUN: would execute task 1 'tarea normal' with model fast"* ]]
    grep -q "TASK_DONE task_id=1" "$T/ws-n/output/agent-runs/n-audit.log"
}

@test "AC-10 positivo: una redefinición de run_agent_task del llamador llega al hijo con timeout" {
    _tasks_with "$T/tasks-o.json" "a'b \"c\" \$d"
    cat > "$T/caller.sh" <<EOF
source "$LOOP"
run_agent_task() { printf '%s\n' "\$3" > "$T/got-o"; return 0; }
SPRINT_ID=o; TASKS_FILE="$T/tasks-o.json"; MAX_TASKS=1
run_loop
EOF
    run env SAVIA_WORKSPACE_DIR="$T/ws-o" bash "$T/caller.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$T/got-o")" == "a'b \"c\" \$d" ]]
}

@test "AC-10: sin timeout en PATH el bucle no lanza la tarea y sale con error" {
    mkdir -p "$T/bin"
    # PATH con todo /usr/bin y /bin salvo timeout/gtimeout.
    for d in /usr/local/bin /usr/bin /bin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            b="${f##*/}"
            [[ "$b" == timeout || "$b" == gtimeout ]] && continue
            [[ -e "$T/bin/$b" ]] || ln -s "$f" "$T/bin/$b"
        done
    done
    run env PATH="$T/bin" bash -c 'command -v timeout || command -v gtimeout'
    [[ "$status" -eq 1 ]]
    _tasks_with "$T/tasks-t.json" "tarea normal"
    _run_loop t "$T/bin"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *timeout* ]]
    [[ "$output" != *"DRY-RUN: would execute"* ]]
    [[ "$(grep -cs "TASK_START" "$T/ws-t/output/agent-runs/t-audit.log")" == 0 || \
       ! -e "$T/ws-t/output/agent-runs/t-audit.log" ]]
}

_path_without() {
    mkdir -p "$T/bin-$1"
    for d in /usr/local/bin /usr/bin /bin; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            b="${f##*/}"
            [[ "$b" == "$1" ]] && continue
            [[ -e "$T/bin-$1/$b" ]] || ln -s "$f" "$T/bin-$1/$b"
        done
    done
    echo "$T/bin-$1"
}

@test "AC-10: sin jq, el respaldo en Python lee la tarea aunque el sprint lleve comilla" {
    p="$(_path_without jq)"
    _tasks_with "$T/tasks-j.json" "tarea sin jq"
    run env SAVIA_WORKSPACE_DIR="$T/ws-j" PATH="$p" \
        bash "$LOOP" --sprint-id "j'x" --tasks "$T/tasks-j.json" --max-tasks 1 --dry-run
    [[ "$output" == *"Task 1: 'tarea sin jq'"* ]]
    [[ "$output" != *SyntaxError* ]]
}

@test "AC-10: un salto de línea en la descripción no falsifica líneas del audit log" {
    _tasks_with "$T/tasks-l.json" $'x\n[2026-01-01T00:00:00Z] TASK_DONE task_id=99 model=heavy'
    _run_loop l
    log="$T/ws-l/output/agent-runs/l-audit.log"
    grep -q 'TASK_START task_id=1 ' "$log"
    # La línea falsa (marca de tiempo inventada al principio) no existe.
    [[ "$(grep -c '^\[2026-01-01T00:00:00Z\]' "$log")" -eq 0 ]]
}

@test "AC-10: el bucle ya no interpola variables dentro de bash -c \"…\"" {
    # Ninguna variable entre comillas simples dentro de código (bash -c / python3 -c);
    # se excluyen las líneas de log, que solo imprimen.
    hits="$(grep -nE "'[\$][{]?[a-z_]+[}]?'" "$LOOP" | grep -vE '(_log|_audit|_warn|_err|echo) ' || true)"
    echo "$hits"
    [[ -z "$hits" ]]
}
