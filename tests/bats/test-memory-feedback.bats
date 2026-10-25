#!/usr/bin/env bats
# tests/bats/test-memory-feedback.bats
# SPEC-164 — Memory Feedback Loop (BATS tests, >= 6)
#
# Tests for:
#   .opencode/hooks/memory-feedback-task.sh
#   scripts/memory-feedback-extractor.py
#   scripts/memory-feedback-compactor.py
#   scripts/memory-feedback-post-merge.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
HOOK="$REPO_ROOT/.opencode/hooks/memory-feedback-task.sh"
EXTRACTOR="$REPO_ROOT/scripts/memory-feedback-extractor.py"
COMPACTOR="$REPO_ROOT/scripts/memory-feedback-compactor.py"
POST_MERGE="$REPO_ROOT/scripts/memory-feedback-post-merge.sh"

setup() {
    TMPDIR_MF="$(mktemp -d)"
    export HOME="$TMPDIR_MF"
    mkdir -p "$TMPDIR_MF/output"
    # Prevent actual memory writes in tests
    export SAVIA_TEST_MODE=true
    export CLAUDE_PROJECT_DIR="$REPO_ROOT"
}

teardown() {
    rm -rf "$TMPDIR_MF"
}

# ─── Test 1: hook file exists and is executable ──────────────────────────────

@test "memory-feedback-task.sh exists and is executable" {
    [[ -f "$HOOK" ]]
    [[ -x "$HOOK" ]]
}

# ─── Test 2: SAVIA_MEMORY_FEEDBACK=off → hook exits 0 without writing ────────

@test "SAVIA_MEMORY_FEEDBACK=off → hook exit 0 sin escribir" {
    local tel="$TMPDIR_MF/output/memory-feedback-telemetry.jsonl"
    local before=0
    [[ -f "$tel" ]] && before="$(wc -l < "$tel")"

    local payload='{"tool_name":"Task","tool_input":{"subagent_type":"test-runner"},"tool_result":"ERROR: test failed"}'
    run bash -c "SAVIA_MEMORY_FEEDBACK=off CLAUDE_PROJECT_DIR='$REPO_ROOT' bash '$HOOK' <<< '$payload'"

    [[ "$status" -eq 0 ]]
    # No telemetry line should have been written
    local after=0
    [[ -f "$tel" ]] && after="$(wc -l < "$tel")"
    [[ "$before" -eq "$after" ]]
}

# ─── Test 3: hook declares set -uo pipefail ───────────────────────────────────

@test "memory-feedback-task.sh tiene set -uo pipefail" {
    grep -qE "set -[uo]+ pipefail|set -euo pipefail" "$HOOK"
}

# ─── Test 4: extractor works standalone ──────────────────────────────────────

@test "memory-feedback-extractor.py funciona standalone con output de error" {
    local payload='{"tool_name":"Task","tool_input":{"subagent_type":"dotnet-developer"},"tool_result":"ERROR: build failed"}'
    local out
    out="$(printf '%s' "$payload" | python3 "$EXTRACTOR")"
    [[ -n "$out" ]]
    # Must be valid JSON
    python3 -c "import json, sys; d=json.loads(sys.argv[1]); assert d['outcome']=='failure'" "$out"
}

@test "memory-feedback-extractor.py funciona standalone con output limpio" {
    local payload='{"tool_name":"Task","tool_input":{"subagent_type":"test-runner"},"tool_result":"All 50 tests passed. Coverage 95%."}'
    local out
    out="$(printf '%s' "$payload" | python3 "$EXTRACTOR")"
    [[ -n "$out" ]]
    python3 -c "import json, sys; d=json.loads(sys.argv[1]); assert d['outcome']=='success'" "$out"
}

# ─── Test 5: compactor --dry-run no modifica nada ────────────────────────────

@test "compactor --dry-run no modifica MEMORY.md" {
    local mem_dir="$TMPDIR_MF/auto"
    mkdir -p "$mem_dir"
    local mem_file="$mem_dir/MEMORY.md"
    cat > "$mem_file" <<'EOF'
# MEMORY Index
<!-- ENTRIES_START -->
- outcome:failure agent:test-runner lesson:Tests failed [2026-06-01T12:00:00Z]
- outcome:failure agent:test-runner lesson:Tests failed [2026-06-02T12:00:00Z]
- outcome:failure agent:test-runner lesson:Tests failed [2026-06-03T12:00:00Z]
<!-- ENTRIES_END -->
EOF
    local before_md5
    before_md5="$(md5sum "$mem_file" | cut -d' ' -f1)"

    run python3 "$COMPACTOR" --dry-run --memory "$mem_file"
    [[ "$status" -eq 0 ]]

    local after_md5
    after_md5="$(md5sum "$mem_file" | cut -d' ' -f1)"
    [[ "$before_md5" = "$after_md5" ]]
}

# ─── Test 6: post-merge --manual funciona ────────────────────────────────────

@test "memory-feedback-post-merge.sh --manual funciona y exit 0" {
    run bash "$POST_MERGE" --manual --pr 864 --spec SPEC-164
    [[ "$status" -eq 0 ]]
}

# ─── Test 7: hook tool_name != Task → exits 0 (no-op) ───────────────────────

@test "hook non-Task tool_name → exits 0 sin procesar" {
    local payload='{"tool_name":"Edit","tool_input":{},"tool_result":"edited"}'
    run bash -c "SAVIA_MEMORY_FEEDBACK=on CLAUDE_PROJECT_DIR='$REPO_ROOT' bash '$HOOK' <<< '$payload'"
    [[ "$status" -eq 0 ]]
}

# ─── Test 8: extractor json output has required fields ───────────────────────

@test "extractor output JSON tiene campos requeridos" {
    local payload='{"tool_name":"Task","tool_input":{"subagent_type":"code-reviewer"},"tool_result":"All checks passed successfully with zero warnings."}'
    local out
    out="$(printf '%s' "$payload" | python3 "$EXTRACTOR")"
    python3 - "$out" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
required = ["outcome", "agent_name", "lesson", "entropy_score", "should_write"]
missing = [f for f in required if f not in d]
if missing:
    print(f"Missing fields: {missing}", file=sys.stderr)
    sys.exit(1)
print("OK")
PYEOF
}

# ─── Test 9: post-merge script has set -uo pipefail ──────────────────────────

@test "memory-feedback-post-merge.sh tiene set -uo pipefail" {
    grep -qE "set -[uo]+ pipefail|set -euo pipefail" "$POST_MERGE"
}

# ─── Test 10: compactor script has valid bash syntax ─────────────────────────

@test "memory-feedback-task.sh tiene sintaxis bash válida" {
    bash -n "$HOOK"
}

@test "memory-feedback-post-merge.sh tiene sintaxis bash válida" {
    bash -n "$POST_MERGE"
}

# ─── Comportamiento del extractor (SPEC-164 S1) ──────────────────────────────
# ex <expr python> -> ejecuta el extractor con el payload y devuelve su JSON.
ex() { python3 -c 'import json,sys; print(json.dumps(eval(sys.argv[1])))' "$1" | python3 "$EXTRACTOR"; }
# chk <expr> <campo> <esperado> -> compara el campo (como texto Python) con lo esperado.
chk() {
    local got
    got=$(ex "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$2")
    [ "$got" = "$3" ] || { echo "payload=$1 campo=$2 obtenido=[$got] esperado=[$3]"; return 1; }
}

@test "extractor: cada palabra de fallo marca outcome=failure" {
    local w
    for w in ERROR error FAIL FAILED FAILURE fail failed exception Exception Traceback traceback Critical critical FATAL fatal Abort abort Crash crash; do
        chk "{'tool_result':'paso uno $w paso dos'}" outcome failure
    done
}

@test "extractor: palabras parecidas sin frontera de palabra no son fallo" {
    local w
    for w in errors terror crashes aborted unfailing "all good" OK; do
        chk "{'tool_result':'resultado $w del paso'}" outcome success
    done
}

@test "extractor: tool_result como dict usa content, y si está vacío output" {
    chk "{'tool_result':{'content':'ERROR en content','output':'todo bien'}}" outcome failure
    chk "{'tool_result':{'content':'','output':'ERROR en output'}}" outcome failure
    chk "{'tool_result':{'content':'todo bien','output':'ERROR ignorado'}}" outcome success
    chk "{'tool_result':{'content':None,'output':None}}" lesson "Task completed with success"
}

@test "extractor: sin tool_result cae a output y luego a result" {
    chk "{'output':'ERROR en output','result':'bien'}" outcome failure
    chk "{'result':'ERROR en result'}" outcome failure
    chk "{'output':'','result':'ERROR en result'}" outcome failure
    chk "{'output':'salida normal larga','result':'ERROR ignorado'}" outcome success
}

@test "extractor: tool_result string vacío también cae a output" {
    chk "{'tool_result':'','output':'ERROR desde output'}" outcome failure
}

@test "extractor: sin salida -> success, lección genérica, entropía 0 y no se escribe" {
    chk "{}" outcome success
    chk "{}" lesson "Task completed with success"
    chk "{}" entropy_score 0.0
    chk "{}" should_write False
}

@test "extractor: agent_name respeta la precedencia subagent_type > agent > agent_name" {
    chk "{'tool_input':{'subagent_type':'a-judge','agent':'b','agent_name':'c'}}" agent_name a-judge
    chk "{'tool_input':{'agent':'b','agent_name':'c'}}" agent_name b
    chk "{'tool_input':{'agent_name':'c'}}" agent_name c
}

@test "extractor: agent_name se infiere de description o prompt cuando faltan los campos" {
    chk "{'tool_input':{'description':'python-developer arregla el bug'}}" agent_name python-developer
    chk "{'tool_input':{'prompt':'code-judge revisa'}}" agent_name code-judge
    chk "{'tool_input':{'description':'security-agent audita','prompt':'otro-agent'}}" agent_name security-agent
}

@test "extractor: agent_name unknown sin pistas o con tool_input que no es dict" {
    chk "{}" agent_name unknown
    chk "{'tool_input':{}}" agent_name unknown
    chk "{'tool_input':'texto'}" agent_name unknown
    chk "{'tool_input':{'description':'MAYUSCULAS 123'}}" agent_name unknown
    chk "{'tool_input':['subagent_type']}" agent_name unknown
}

@test "extractor: lección de fallo es la línea del error, no la primera" {
    chk "{'tool_result':'arrancando proceso largo\nTraceback (most recent call last)\nValueError: x'}" lesson "Traceback (most recent call last)"
    chk "{'tool_result':'inicio del trabajo\n  ERROR: disco lleno  \nfin del trabajo'}" lesson "ERROR: disco lleno"
}

@test "extractor: fallo sin línea de error reconocible usa la primera línea útil" {
    chk "{'tool_result':'Preparando entorno ahora\nCritical: valor fuera de rango'}" outcome failure
    chk "{'tool_result':'Preparando entorno ahora\nCritical: valor fuera de rango'}" lesson "Preparando entorno ahora"
}

@test "extractor: lección de éxito salta líneas cortas y boilerplate" {
    chk "{'tool_result':'ok\nDone\n  corto  \nResumen del trabajo realizado\nmás texto aquí'}" lesson "Resumen del trabajo realizado"
    chk "{'tool_result':'success\nCompleted\nSe han migrado 12 tablas'}" lesson "Se han migrado 12 tablas"
}

@test "extractor: línea de exactamente 10 caracteres cuenta, de 9 no" {
    chk "{'tool_result':'123456789\n1234567890\notra linea larga'}" lesson 1234567890
}

@test "extractor: si todas las líneas son triviales devuelve la primera" {
    chk "{'tool_result':'ok\ndone\nfin'}" lesson ok
}

@test "extractor: la lección se trunca a 150 caracteres" {
    local long; long=$(python3 -c 'print("x"*400)')
    local got
    got=$(ex "{'tool_result':'ERROR $long'}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["lesson"]))')
    [ "$got" -eq 150 ]
    got=$(ex "{'tool_result':'$long'}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["lesson"]))')
    [ "$got" -eq 150 ]
}

@test "extractor: salida solo de espacios -> lección genérica" {
    chk "{'tool_result':'   \n  \n'}" lesson "Task completed with success"
}

@test "extractor: menos de 10 tokens -> entropía 0 aunque sean distintos" {
    chk "{'tool_result':'a1 a2 a3 a4 a5 a6 a7 a8 a9'}" entropy_score 0.0
}

@test "extractor: 10 tokens únicos -> entropía exacta 0.72 (frontera inferior)" {
    chk "{'tool_result':'alpha1 beta22 gamma33 delta44 eps55 zeta66 eta777 theta88 iota99 kappa00'}" entropy_score 0.72
}

@test "extractor: entropía = ratio de únicos x tamaño/100, con valores exactos" {
    # 20 tokens únicos de 5 caracteres: 119 caracteres -> factor 1.0 -> 1.0
    chk "{'tool_result':' '.join('tok%02d' % i for i in range(20))}" entropy_score 1.0
    # mitad repetidos y 63 caracteres: 0.5 x 0.63 = 0.315
    chk "{'tool_result':'alpha beta gamma delta eps zeta alpha beta gamma delta eps zeta'}" entropy_score 0.315
}

@test "extractor: entropía ignora mayúsculas al contar únicos" {
    # 10 tokens que solo difieren en mayúsculas -> 1 único: 0.1 x 0.59 = 0.059
    chk "{'tool_result':'AbCdE abcde ABCDE abcDE aBcde ABcde abCDE AbcdE abcdE ABCde'}" entropy_score 0.059
}

@test "extractor: éxito con entropía > 0.3 se escribe; con 0.3 o menos no" {
    chk "{'tool_result':'alpha beta gamma delta eps zeta alpha beta gamma delta eps zeta'}" should_write True
    chk "{'tool_result':'ok'}" should_write False
    chk "{'tool_result':'aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb'}" should_write False
}

@test "extractor: un fallo se escribe siempre aunque la entropía sea 0" {
    chk "{'tool_result':'ERROR'}" should_write True
    chk "{'tool_result':'ERROR'}" entropy_score 0.0
}

@test "extractor: el redondeo de la entropía es a 4 decimales" {
    local got
    got=$(ex "{'tool_result':'a1 b2 c3 d4 e5 f6 g7 h8 i9 j0 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1'}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["entropy_score"])')
    [ "$got" = "0.2632" ]
}

@test "extractor: stdin vacío o en blanco -> outcome unknown, exit 0" {
    run python3 "$EXTRACTOR" <<< ""
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["outcome"], d["agent_name"], d["should_write"])' "$output")" = "unknown unknown False" ]
    run python3 "$EXTRACTOR" <<< "   "
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome": "unknown"'* ]]
}

@test "extractor: JSON inválido -> valores por defecto seguros, exit 0" {
    run python3 "$EXTRACTOR" <<< "{no es json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"outcome": "unknown"'* ]]
    [[ "$output" == *'"should_write": false'* ]]
}

@test "extractor: JSON válido pero no objeto (lista, null, número) -> valores por defecto, exit 0" {
    local raw
    for raw in '[]' '[1,2]' 'null' '42' '"texto"'; do
        run python3 "$EXTRACTOR" <<< "$raw"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"outcome": "unknown"'* ]]
    done
}
