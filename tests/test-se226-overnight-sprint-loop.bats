#!/usr/bin/env bats
# SE-226 — overnight-sprint-loop.sh smoke tests

setup() {
    cd "$BATS_TEST_DIRNAME/.."
    LOOP="$PWD/scripts/overnight-sprint-loop.sh"
    STATE="$PWD/scripts/overnight-sprint-state.sh"
}

@test "overnight-sprint-loop.sh exists and is executable" {
    [[ -x "$LOOP" ]]
}

@test "overnight-sprint-state.sh exists and is executable" {
    [[ -x "$STATE" ]]
}

@test "loop has set -uo pipefail" {
    grep -q "set -uo pipefail" "$LOOP"
}

@test "state has set -uo pipefail" {
    grep -q "set -uo pipefail" "$STATE"
}

@test "loop --help or no args exits non-zero with usage hint" {
    run bash "$LOOP"
    [[ "$status" -ne 0 ]] || [[ "$output" =~ [Uu]sage ]]
}

@test "state --self-test exits 0" {
    run bash "$STATE" --self-test
    [[ "$status" -eq 0 ]]
}

@test "loop handles missing sprint-id gracefully" {
    run bash "$LOOP" --tasks /tmp/nonexistent.json
    [[ "$status" -ne 0 ]]
}

@test "loop handles dry-run with synthetic tasks" {
    tmpdir="$BATS_TEST_TMPDIR"
    echo '[{"id":1,"description":"test","status":"pending"}]' > "$tmpdir/tasks.json"
    # SE-472: el bucle exige grant vigente. Se emite uno real en un directorio temporal
    # (AC5d prohíbe desactivar el requisito); su caducidad se prueba en test-se472.
    printf -- '---\nactive_slug: "tester"\n---\n' > "$tmpdir/active-user.md"
    SAVIA_GRANTS_DIR="$tmpdir/grants" SAVIA_ACTIVE_USER_FILE="$tmpdir/active-user.md" \
        bash scripts/operator-grant.sh grant \
        --scope autonomy:overnight-sprint --context "test" --ttl-hours 1 >/dev/null
    run env SAVIA_WORKSPACE_DIR="$tmpdir/ws" SAVIA_GRANTS_DIR="$tmpdir/grants" \
        SAVIA_ACTIVE_USER_FILE="$tmpdir/active-user.md" \
        bash "$LOOP" --sprint-id "test-smoke" --tasks "$tmpdir/tasks.json" --max-tasks 1 --dry-run
    # dry-run should succeed
    [[ "$status" -eq 0 ]]
    [[ -f "$tmpdir/ws/output/agent-runs/test-smoke/state.json" ]]
}

@test "loop dry-run sin grant vigente para con exit 4 y deja la tarea suspendida (fail-closed)" {
    tmpdir="$BATS_TEST_TMPDIR"
    echo '[{"id":1,"description":"test","status":"pending"}]' > "$tmpdir/tasks.json"
    run env SAVIA_WORKSPACE_DIR="$tmpdir/ws" SAVIA_GRANTS_DIR="$tmpdir/nogrants" \
        bash "$LOOP" --sprint-id "test-deny" --tasks "$tmpdir/tasks.json" --max-tasks 1 --dry-run
    [[ "$status" -eq 4 ]]
    [[ "$output" == *"authority"* || "$output" == *"suspendida"* ]]
}

# ── SE-350 Coherence Court wiring ───────────────────────────────────────────

@test "loop references coherence-court.sh wiring functions" {
    grep -q "_coherence_register" "$LOOP"
    grep -q "_coherence_gate" "$LOOP"
}

@test "loop calls _coherence_register after TASK_DONE" {
    grep -q '_coherence_register "\$sprint_id" "\$task_id" "\$description"' "$LOOP"
}

@test "loop calls _coherence_gate at LOOP_END" {
    grep -q "_coherence_gate \"\$sprint_id\"" "$LOOP"
}

@test "coherence wiring is off-by-default non-blocking (OVERNIGHT_COHERENCE_GATE=off)" {
    tmpdir=$(mktemp -d)
    export OVERNIGHT_COHERENCE_GATE=off
    # El bucle deriva AGENT_RUNS_DIR de aquí: el audit log queda en $tmpdir/output/agent-runs.
    export SAVIA_WORKSPACE_DIR="$tmpdir"
    echo '[{"id":1,"description":"test","status":"pending"}]' > "$tmpdir/tasks.json"
    run bash "$LOOP" --sprint-id "coh-smoke" --tasks "$tmpdir/tasks.json" --max-tasks 1 --dry-run
    # la tarea arrancó de verdad (si no, el test no prueba el cableado de coherencia)
    grep -q "TASK_START task_id=1" "$tmpdir/output/agent-runs/coh-smoke-audit.log"
    unset OVERNIGHT_COHERENCE_GATE
    rm -rf "$tmpdir"
    [[ "$status" -eq 0 ]]
}

@test "coherence premises registry works (integration with coherence-court.sh)" {
    tmpdir=$(mktemp -d)
    export COHERENCE_PREMISES_DIR="$tmpdir/data"
    mkdir -p "$tmpdir/data"
    bash scripts/coherence-court.sh premises coh-flow init >/dev/null
    pid=$(bash scripts/coherence-court.sh premises coh-flow add decision "t1" --stage task-1)
    [[ -n "$pid" ]]
    out=$(bash scripts/coherence-court.sh premises coh-flow list --json)
    echo "$out" | python3 -c "import sys,json; rows=json.load(sys.stdin); assert len(rows)==1, rows"
    bash scripts/coherence-court.sh premises coh-flow list | grep -q "t1"
    rm -rf "$tmpdir"
}

