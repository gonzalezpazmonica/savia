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
  local task_id="$2" model="$4"
  echo "$task_id" >> "$STARTED_LOG"
  echo "$task_id:$model" >> "$STARTED_LOG.models"
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
  # TOKEN_EXHAUST_TASK: esa tarea agota tokens en el primer modelo (exit 2 → escalada)
  if [[ -n "${TOKEN_EXHAUST_TASK:-}" && "$task_id" == "$TOKEN_EXHAUST_TASK" && "$model" == "fast" ]]; then
    return 2
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
    # el lote parado por autoridad no sale con 0 (quien llama lo distingue de «completado»)
    [ "$status" -eq 4 ]
}

@test "AC1b: grant ya caducado antes de empezar -> ninguna tarea arranca" {
    issue_grant
    python3 - "$GRANT_FILE" <<'PY'
import json, sys, time
rec = json.load(open(sys.argv[1])); rec["expires_epoch"] = int(time.time()) - 5
json.dump(rec, open(sys.argv[1], "w"))
PY
    run_batch
    [ "$status" -eq 4 ]
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

@test "AC3e: scope de la skill que el comprobador rechaza (sale con 2) -> authority_invalid, no arranca" {
    issue_grant
    OVERNIGHT_GRANT_SCOPE="autonomy:overnight-otro" run_batch
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_invalid" ]
    grep -q "grant-scope override scope=autonomy:overnight-otro" "$AUDIT"
}

@test "AC3e2: el grant vigente de otra skill no autoriza la noche (scope fuera de autonomy:overnight*)" {
    bash "$T/scripts/operator-grant.sh" grant --scope autonomy:code-improvement-loop --context "test" --ttl-hours 1 >/dev/null
    # el grant existe y es válido para su skill
    bash "$T/scripts/operator-grant.sh" check --scope autonomy:code-improvement-loop
    OVERNIGHT_GRANT_SCOPE="autonomy:code-improvement-loop" run_batch
    [ "$status" -eq 4 ]
    [ -z "$(started)" ]
    [ "$(task_reason 1)" = "authority_invalid" ]
    grep -q "grant-scope override scope=<rechazado>" "$AUDIT"
}

@test "AC3e3: un scope con salto de línea no falsea el audit log" {
    issue_grant
    OVERNIGHT_GRANT_SCOPE=$'autonomy:overnight-sprint\nTASK_DONE task_id=9' run_batch
    [ -z "$(started)" ]
    run grep -c "TASK_DONE task_id=9" "$AUDIT"
    [ "$output" = "0" ]
    grep -q "AUTHORITY_SUSPENDED reason=authority_invalid suspended=5 scope=<rechazado>" "$AUDIT"
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
    # sin «!» en mitad del test: bats no evalúa esa negación (P1 de la revisión)
    run grep -c "PROHIBIDA" "$T/grant-calls.log"
    [ "$output" = "0" ]
    grep -q "^check --scope autonomy:overnight-sprint" "$T/grant-calls.log"
    # y estáticamente: ni el bucle ni la librería mencionan la acción grant/revoke
    ! grep -nE 'operator-grant\.sh"?[^#]*\b(grant|revoke|consume)\b' "$REPO/scripts/overnight-sprint-loop.sh" "$REPO/scripts/lib/overnight-authority.sh" | grep -v '^\S*:[0-9]*:\s*#'
}

# ── AC5: OVERNIGHT_REQUIRE_GRANT ─────────────────────────────────────────────

@test "AC5: OVERNIGHT_REQUIRE_GRANT=false explícito -> corre sin grant, deja 'grant-check disabled' y cabecera" {
    OVERNIGHT_REQUIRE_GRANT=false run_batch
    [ "$status" -eq 0 ]
    [ "$(started)" = "1,2,3,4,5" ]
    grep -q "grant-check disabled" "$AUDIT"
    # cabecera: el aviso sale antes de la primera tarea, no al final
    local i warn=-1 first=-1
    for i in "${!lines[@]}"; do
        [[ "$warn" -lt 0 && "${lines[$i]}" == *"control de autoridad desactivado"* ]] && warn=$i
        [[ "$first" -lt 0 && "${lines[$i]}" == *"Task 1:"* ]] && first=$i
    done
    [ "$warn" -ge 0 ] && [ "$first" -ge 0 ]
    [ "$warn" -lt "$first" ]
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
    # Dentro de run_loop, sin contar comentarios: la primera llamada precede a la elección.
    run awk '/^run_loop\(\)/{in_f=1} in_f && /^}/{in_f=0}
             in_f && $0 !~ /^[[:space:]]*#/ {
               if (!call && /if ! check_authority/) call=NR
               if (!pick && /task_id="\$\(printf/) pick=NR
             }
             END { print call+0, pick+0 }' "$REPO/scripts/overnight-sprint-loop.sh"
    [ "$status" -eq 0 ]
    read -r call pick <<<"$output"
    [ "$call" -gt 0 ] && [ "$pick" -gt 0 ]
    [ "$call" -lt "$pick" ]
}

@test "AC7: la escalada de modelo no relanza el agente si la autoridad caducó en el primer intento" {
    issue_grant
    EXPIRE_AFTER=2 EXPIRE_MODE=expire TOKEN_EXHAUST_TASK=2 run_batch
    [ "$status" -eq 4 ]
    # la tarea 2 se lanzó una sola vez (fast); ni mid ni heavy
    [ "$(paste -sd, "$STARTED_LOG.models")" = "1:fast,2:fast" ]
    for i in 2 3 4 5; do
        [ "$(task_status $i)" = "suspended" ]
        [ "$(task_reason $i)" = "authority_expired" ]
    done
    grep -q "AUTHORITY_SUSPENDED reason=authority_expired suspended=4 .*task_in_progress=2" "$AUDIT"
}

@test "AC7b: con autoridad vigente la escalada sigue funcionando (fast → mid)" {
    issue_grant
    TOKEN_EXHAUST_TASK=2 run_batch
    [ "$status" -eq 0 ]
    [ "$(paste -sd, "$STARTED_LOG.models")" = "1:fast,2:fast,2:mid,3:fast,4:fast,5:fast" ]
    [ "$(task_status 2)" = "done" ]
}

@test "AC8: si suspend falla, el audit dice AUTHORITY_SUSPEND_FAILED y no «suspendidas»" {
    mv "$T/scripts/overnight-sprint-state.sh" "$T/scripts/state-real.sh"
    cat > "$T/scripts/overnight-sprint-state.sh" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "suspend" ]] && { echo "fallo simulado" >&2; exit 1; }
exec bash "$T/scripts/state-real.sh" "\$@"
EOF
    run_batch
    [ "$status" -eq 4 ]
    [ -z "$(started)" ]
    grep -q "AUTHORITY_SUSPEND_FAILED reason=authority_missing pending=5" "$AUDIT"
    run grep -c "AUTHORITY_SUSPENDED " "$AUDIT"
    [ "$output" = "0" ]
    [ "$(task_status 1)" = "pending" ]
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

@test "state: suspend sin jq usa python3 y marca las pendientes de verdad" {
    printf '[{"id":1,"description":"a","status":"done"},{"id":2,"description":"b","status":"pending"},{"id":3,"description":"c","status":"in_progress"}]' > "$T/t3.json"
    OVERNIGHT_SPRINT_ID=y bash "$T/scripts/overnight-sprint-state.sh" init --sprint-id y --tasks-file "$T/t3.json" >/dev/null 2>&1
    # PATH sin jq: enlaces a todo lo ejecutable menos jq
    mkdir -p "$T/nojq"
    local d f
    IFS=: read -ra dirs <<<"$PATH"
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        for f in "$d"/*; do
            [[ -x "$f" && "$(basename "$f")" != jq && ! -e "$T/nojq/$(basename "$f")" ]] && ln -s "$f" "$T/nojq/"
        done
    done
    run env PATH="$T/nojq" OVERNIGHT_SPRINT_ID=y bash "$T/scripts/overnight-sprint-state.sh" suspend --reason authority_expired --task-id 3
    [ "$status" -eq 0 ]
    [ "$(jq -r '.tasks[0].status' "$AGENT_RUNS_DIR/y/state.json")" = "done" ]
    [ "$(jq -r '.tasks[1].status' "$AGENT_RUNS_DIR/y/state.json")" = "suspended" ]
    [ "$(jq -r '.tasks[2].status' "$AGENT_RUNS_DIR/y/state.json")" = "suspended" ]
    [ "$(jq -r '.tasks[2].suspend_reason' "$AGENT_RUNS_DIR/y/state.json")" = "authority_expired" ]
}

@test "state: suspend rechaza --task-id no numérico" {
    printf '[{"id":1,"description":"a","status":"pending"}]' > "$T/t4.json"
    OVERNIGHT_SPRINT_ID=z bash "$T/scripts/overnight-sprint-state.sh" init --sprint-id z --tasks-file "$T/t4.json" >/dev/null 2>&1
    run env OVERNIGHT_SPRINT_ID=z bash "$T/scripts/overnight-sprint-state.sh" suspend --reason authority_expired --task-id '1"; x'
    [ "$status" -ne 0 ]
    [ "$(jq -r '.tasks[0].status' "$AGENT_RUNS_DIR/z/state.json")" = "pending" ]
}
