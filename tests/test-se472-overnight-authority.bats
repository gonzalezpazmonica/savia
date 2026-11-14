#!/usr/bin/env bats
# SE-472 S1 — la vigencia de la autoridad se comprueba antes de CADA tarea nocturna.
# Ejecuta el bucle real (scripts/overnight-sprint-loop.sh) con grants reales de
# scripts/operator-grant.sh en un directorio temporal. El "reloj simulado" es
# reescribir expires_epoch del grant durante una tarea (misma fuente que usa check).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    T="$(mktemp -d)"
    mkdir -p "$T/scripts/lib" "$T/home" "$T/ws/output/agent-runs"
    for f in overnight-sprint-loop.sh overnight-sprint-state.sh operator-grant.sh recursion-guard-export.sh; do
        cp "$REPO/scripts/$f" "$T/scripts/$f"
    done
    [[ -f "$REPO/scripts/lib/overnight-authority.sh" ]] && cp "$REPO/scripts/lib/overnight-authority.sh" "$T/scripts/lib/"
    printf -- '---\nactive_slug: "tester"\n---\n' > "$T/active-user.md"
    export SAVIA_GRANTS_DIR="$T/home/grants"
    export SAVIA_ACTIVE_USER_FILE="$T/active-user.md"
    export SAVIA_WORKSPACE_DIR="$T/ws"
    export AGENT_RUNS_DIR="$T/ws/output/agent-runs"
    export OVERNIGHT_COHERENCE_GATE=off
    unset OVERNIGHT_REQUIRE_GRANT OVERNIGHT_GRANT_SCOPE
    GRANT_FILE="$SAVIA_GRANTS_DIR/autonomy:overnight-sprint.json"
    SPRINT="s472"
    AUDIT="$AGENT_RUNS_DIR/$SPRINT-audit.log"
    STATE_JSON="$AGENT_RUNS_DIR/$SPRINT/state.json"
    # n tareas pendientes
    python3 - "$T/tasks.json" 5 <<'PY'
import json, sys
n = int(sys.argv[2])
json.dump([{"id": i, "description": f"tarea {i}", "status": "pending"} for i in range(1, n + 1)], open(sys.argv[1], "w"))
PY
    # Ejecutor de tareas simulado: registra cada arranque; en la tarea $EXPIRE_AFTER
    # simula el paso del tiempo (caducidad) o la revocación (borrado) del grant.
    cat > "$T/scripts/run-harness.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/overnight-sprint-loop.sh"
run_agent_task() {
  local task_id="$2"
  echo "$task_id" >> "$STARTED_LOG"
  if [[ -n "${EXPIRE_AFTER:-}" && "$task_id" == "$EXPIRE_AFTER" ]]; then
    case "${EXPIRE_MODE:-expire}" in
      expire) python3 - "$GRANT_FILE" <<'PY'
import json, sys, time
rec = json.load(open(sys.argv[1])); rec["expires_epoch"] = int(time.time()) - 5
json.dump(rec, open(sys.argv[1], "w"))
PY
      ;;
      revoke)  rm -f "$GRANT_FILE" ;;
      corrupt) printf '{no json' > "$GRANT_FILE" ;;
    esac
  fi
  return 0
}
export -f run_agent_task
parse_args "$@"
run_loop
EOF
    export STARTED_LOG="$T/started.log" GRANT_FILE
    : > "$STARTED_LOG"
}

teardown() { rm -rf "$T"; }

issue_grant() {
    bash "$T/scripts/operator-grant.sh" grant --scope autonomy:overnight-sprint --context "test" --ttl-hours 1 >/dev/null
}

run_batch() {
    run bash "$T/scripts/run-harness.sh" --sprint-id "$SPRINT" --tasks "$T/tasks.json" --max-tasks 10
}

started() { paste -sd, "$STARTED_LOG"; }

task_status() { jq -r ".tasks[] | select(.id == $1) | .status" "$STATE_JSON"; }
task_reason() { jq -r ".tasks[] | select(.id == $1) | .suspend_reason // \"\"" "$STATE_JSON"; }

# ── Línea base: grant vigente = comportamiento anterior (AC2) ───────────────

@test "AC2: grant vigente todo el lote -> las 5 tareas arrancan y terminan done" {
    issue_grant
    run_batch
    [ "$status" -eq 0 ]
    [ "$(started)" = "1,2,3,4,5" ]
    for i in 1 2 3 4 5; do [ "$(task_status $i)" = "done" ]; done
    run bash "$T/scripts/overnight-sprint-state.sh" export
    [ "$(echo "$output" | grep -c -P '\tdone\t')" -eq 5 ]
    ! grep -q "AUTHORITY_SUSPENDED" "$AUDIT"
}

# ── Caducidad a mitad de la noche (AC1) ──────────────────────────────────────

@test "AC1: el grant caduca durante la tarea 2 -> la 3 no arranca y 3-5 quedan suspended/authority_expired" {
    issue_grant
    EXPIRE_AFTER=2 EXPIRE_MODE=expire run_batch
    [ "$(started)" = "1,2" ]
    [ "$(task_status 1)" = "done" ]
    [ "$(task_status 2)" = "done" ]
    for i in 3 4 5; do
        [ "$(task_status $i)" = "suspended" ]
        [ "$(task_reason $i)" = "authority_expired" ]
    done
    grep -q "AUTHORITY_SUSPENDED reason=authority_expired suspended=3" "$AUDIT"
    [[ "$output" == *"3 tareas suspendidas por vigencia"* ]]
}

@test "AC1b: grant ya caducado antes de empezar -> ninguna tarea arranca" {
    issue_grant
    python3 - "$GRANT_FILE" <<'PY'
import json, sys, time
rec = json.load(open(sys.argv[1])); rec["expires_epoch"] = int(time.time()) - 5
json.dump(rec, open(sys.argv[1], "w"))
PY
    run_batch
    [ -z "$(started)" ]
    for i in 1 2 3 4 5; do [ "$(task_status $i)" = "suspended" ]; done
}

# ── Revocado / ausente / ilegible (AC3) ─────────────────────────────────────

@test "AC3: grant revocado a mitad del lote -> authority_missing, la siguiente no arranca" {
    issue_grant
    EXPIRE_AFTER=2 EXPIRE_MODE=revoke run_batch
    [ "$(started)" = "1,2" ]
    for i in 3 4 5; do
        [ "$(task_status $i)" = "suspended" ]
        [ "$(task_reason $i)" = "authority_missing" ]
    done
    grep -q "AUTHORITY_SUSPENDED reason=authority_missing" "$AUDIT"
}

@test "AC3b: revocado con operator-grant.sh revoke antes de empezar -> authority_missing" {
    issue_grant
    bash "$T/scripts/operator-grant.sh" revoke --scope autonomy:overnight-sprint
    run_batch
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_missing" ]
}

@test "AC3c: sin ningún fichero de grant -> no arranca nada" {
    run_batch
    [ -z "$(started)" ]
    [ "$(task_status 1)" = "suspended" ]
    [ "$(task_reason 1)" = "authority_missing" ]
}

@test "AC3d: fichero de grant corrupto a mitad del lote -> la siguiente no arranca (fail-closed)" {
    issue_grant
    EXPIRE_AFTER=1 EXPIRE_MODE=corrupt run_batch
    [ "$(started)" = "1" ]
    [ "$(task_status 2)" = "suspended" ]
    [[ "$(task_reason 2)" == authority_* ]]
}

@test "AC3e: scope inválido (comprobador sale con 2) -> authority_invalid, no arranca" {
    issue_grant
    OVERNIGHT_GRANT_SCOPE="autonomy:no-existe" run_batch
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_invalid" ]
}

@test "AC3f: comprobador ausente -> authority_invalid, no arranca (no se pudo comprobar != autorizado)" {
    issue_grant
    rm "$T/scripts/operator-grant.sh"
    run_batch
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_invalid" ]
}

@test "AC3g: grant de otro operador (grantor distinto del activo) -> no arranca" {
    issue_grant
    printf -- '---\nactive_slug: "otra-persona"\n---\n' > "$T/active-user.md"
    run_batch
    [ -z "$(started)" ]
    [ "$(task_status 1)" = "suspended" ]
}

# ── AC4: el bucle nunca emite grants ─────────────────────────────────────────

@test "AC4: el bucle solo llama a 'check'; si llamara a 'grant' (o renovara) el stub falla" {
    cat > "$T/scripts/operator-grant.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/grant-calls.log"
[[ "\$1" == "check" ]] || { echo "LLAMADA PROHIBIDA: \$*" >> "$T/grant-calls.log"; exit 99; }
exit 3
EOF
    run_batch
    [ -f "$T/grant-calls.log" ]
    ! grep -q "PROHIBIDA" "$T/grant-calls.log"
    grep -q "^check --scope autonomy:overnight-sprint" "$T/grant-calls.log"
    # y estáticamente: ni el bucle ni la librería mencionan la acción grant/revoke
    ! grep -nE 'operator-grant\.sh"?[^#]*\b(grant|revoke|consume)\b' "$REPO/scripts/overnight-sprint-loop.sh" "$REPO/scripts/lib/overnight-authority.sh" | grep -v '^\S*:[0-9]*:\s*#'
}

# ── AC5: OVERNIGHT_REQUIRE_GRANT ─────────────────────────────────────────────

@test "AC5: OVERNIGHT_REQUIRE_GRANT=false explícito -> corre sin grant, deja 'grant-check disabled' y cabecera" {
    OVERNIGHT_REQUIRE_GRANT=false run_batch
    [ "$(started)" = "1,2,3,4,5" ]
    grep -q "grant-check disabled" "$AUDIT"
    [[ "$output" == *"control de autoridad desactivado"* ]]
}

@test "AC5b: sin la variable y sin grant -> ninguna tarea arranca (authority_missing)" {
    run_batch
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_missing" ]
    ! grep -q "grant-check disabled" "$AUDIT"
}

@test "AC5c: cualquier valor distinto de 'false' deja el control activo" {
    for v in 0 no FALSE off "" " false"; do
        rm -rf "$AGENT_RUNS_DIR/$SPRINT" "$AUDIT"; : > "$STARTED_LOG"
        OVERNIGHT_REQUIRE_GRANT="$v" run_batch
        [ -z "$(started)" ] || { echo "arrancó con OVERNIGHT_REQUIRE_GRANT='$v'"; return 1; }
    done
}

@test "AC5d: ningún fichero versionado asigna OVERNIGHT_REQUIRE_GRANT=false" {
    cd "$REPO"
    run bash -c "git ls-files -z | xargs -0 grep -nE 'OVERNIGHT_REQUIRE_GRANT=.?false' 2>/dev/null | grep -v '^tests/test-se472-overnight-authority.bats:' | grep -v '^docs/specs/SE-472' | grep -v '^docs/propuestas/'"
    echo "$output"
    [ -z "$output" ]
}

# ── AC6: el gancho está conectado en el bucle real ──────────────────────────

@test "AC6: el bucle llama a check_authority antes de elegir la tarea" {
    local call pick
    call="$(grep -n 'check_authority' "$REPO/scripts/overnight-sprint-loop.sh" | grep -v '^\S*#' | grep -m1 'if ! check_authority' | cut -d: -f1)"
    pick="$(grep -n 'task_id="$(printf' "$REPO/scripts/overnight-sprint-loop.sh" | head -1 | cut -d: -f1)"
    [ -n "$call" ] && [ -n "$pick" ]
    [ "$call" -lt "$pick" ]
}

@test "state: suspend solo toca las pendientes y exige --reason" {
    printf '[{"id":1,"description":"a","status":"done"},{"id":2,"description":"b","status":"pending"}]' > "$T/t2.json"
    OVERNIGHT_SPRINT_ID=x bash "$T/scripts/overnight-sprint-state.sh" init --sprint-id x --tasks-file "$T/t2.json" >/dev/null 2>&1
    run env OVERNIGHT_SPRINT_ID=x bash "$T/scripts/overnight-sprint-state.sh" suspend
    [ "$status" -ne 0 ]
    run env OVERNIGHT_SPRINT_ID=x bash "$T/scripts/overnight-sprint-state.sh" suspend --reason authority_expired
    [ "$status" -eq 0 ]
    [ "$(jq -r '.tasks[0].status' "$AGENT_RUNS_DIR/x/state.json")" = "done" ]
    [ "$(jq -r '.tasks[1].status' "$AGENT_RUNS_DIR/x/state.json")" = "suspended" ]
}
