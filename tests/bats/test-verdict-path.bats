#!/usr/bin/env bats
# SE-367 — Derivation Path (AC-0..AC-5)
# Ref: docs/specs/SE-367-derivation-path.spec.md
# CRIT-001: store y traces en /tmp; sin red.

VP="bash scripts/verdict-path.sh"
FIX="tests/fixtures/verdict-path"  # trace observado propio de esta rama

setup() {
    TMPD="$(mktemp -d)"
    STORE="$TMPD/verdicts"
    cat > "$TMPD/verdict.json" <<'EOF'
{
  "verdict_id": "court-test-001",
  "judge": "correctness-judge",
  "outcome": "FAIL"
}
EOF
    cat > "$TMPD/trace.jsonl" <<'EOF'
{"event":"tool_exec","tool":"build","args_fp":"2dc9baa237cbcd24"}
{"event":"tool_blocked","tool":"git push"}
EOF
}

teardown() {
    rm -rf "$TMPD"
}

@test "SE-367 AC-0: attach valida y adjunta el path" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule "CRITERIO#no-conflicto" \
        --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"rule":"trace:tool_observed","ref":"trace#t-118","ground":true,"trace_event":"tool_exec","tool":"build"},{"rule":"ref:source_exists","ref":"AGENTS.md"}]' \
        --evidence-json '[{"ref":"AGENTS.md","quote":"mirror"},{"trace_event":"tool_blocked","tool":"git push","observed":true,"ground":true}]'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"attached": "court-test-001"'
    grep -q '"path"' "$STORE/court-test-001.json"
}

@test "SE-367 AC-0: attach sin rule falla (exit 2)" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE"
    [ "$status" -eq 2 ]
}

@test "SE-367 AC-2: ground:true con trace_event NO observado → FAIL (exit 1)" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule r \
        --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"rule":"trace:tool_observed","ground":true,"trace_event":"tool_exec","tool":"deploy_remote_staging"}]'
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'NO observado'
}

@test "SE-367 AC-3: ref inexistente → WARN (attach prosigue)" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule r \
        --premises-json '[{"rule":"ref:source_exists","ref":"docs/no/existe-ya.md"}]'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'WARN'
    echo "$output" | grep -q 'ref inexistente'
}

@test "SE-367 --validate: OK con trace observado" {
    $VP attach "$TMPD/verdict.json" --store "$STORE" --rule r \
        --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"rule":"x","ground":true,"trace_event":"tool_exec","tool":"build"}]' >/dev/null
    run $VP --validate court-test-001 --store "$STORE" --trace "$TMPD/trace.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"validate": "OK"'
}

@test "SE-367 --validate: FAIL si el trace ya no sostiene el ground" {
    $VP attach "$TMPD/verdict.json" --store "$STORE" --rule r \
        --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"rule":"x","ground":true,"trace_event":"tool_exec","tool":"build"}]' >/dev/null
    echo '{"event":"tool_exec","tool":"otra"}' > "$TMPD/trace-roto.jsonl"
    run $VP --validate court-test-001 --store "$STORE" --trace "$TMPD/trace-roto.jsonl"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q '"validate": "FAIL"'
}

@test "SE-367 AC-1: expand devuelve la cadena completa con sub-path anidado" {
    cat > "$TMPD/sub.json" <<'EOF'
{
  "verdict_id": "court-test-000",
  "judge": "coherence-judge",
  "outcome": "PASS",
  "path": {
    "rule": "CRITERIO#coherencia-interna",
    "premises": [{"rule": "ref:source_exists", "ref": "AGENTS.md"}],
    "evidence": [{"ref": "AGENTS.md", "quote": "mirror"}]
  }
}
EOF
    $VP attach "$TMPD/sub.json" --store "$STORE" --rule "CRITERIO#coherencia-interna" \
        --premises-json '[{"rule":"ref:source_exists","ref":"AGENTS.md"}]' >/dev/null
    $VP attach "$TMPD/verdict.json" --store "$STORE" --rule "CRITERIO#raiz" \
        --premises-json '[{"rule":"verdict:court-test-000","ref":"verdict:court-test-000"}]' >/dev/null
    run $VP expand court-test-001 --store "$STORE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"rule": "CRITERIO#raiz"'
    echo "$output" | grep -q '"sub_path"'
    echo "$output" | grep -q '"rule": "CRITERIO#coherencia-interna"'
}

@test "SE-367 AC-4: veredicto sin path sigue consumible (show OK, validate OK)" {
    $VP attach "$TMPD/verdict.json" --store "$STORE" --rule r >/dev/null 2>&1
    cat > "$TMPD/sin-path.json" <<'EOF'
{"verdict_id": "court-test-002", "judge": "x", "outcome": "PASS"}
EOF
    python3 - "$STORE" "$TMPD/sin-path.json" <<'PY'
import json, shutil, sys
store, src = sys.argv[1], sys.argv[2]
v = json.load(open(src))
open(f"{store}/court-test-002.json", "w").write(json.dumps(v, indent=2) + "\n")
PY
    run $VP show court-test-002 --store "$STORE"
    [ "$status" -eq 0 ]
    run $VP --validate court-test-002 --store "$STORE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'sin path'
}

@test "SE-367 AC-4b: expand de veredicto sin path no rompe (nota, no crash)" {
    cat > "$TMPD/sin-path.json" <<'EOF'
{"verdict_id": "court-test-003", "judge": "x", "outcome": "PASS"}
EOF
    mkdir -p "$STORE"
    python3 - "$STORE" "$TMPD/sin-path.json" <<'PY'
import json, sys
store, src = sys.argv[1], sys.argv[2]
v = json.load(open(src))
open(f"{store}/court-test-003.json", "w").write(json.dumps(v, indent=2) + "\n")
PY
    run $VP expand court-test-003 --store "$STORE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'sin path'
}

@test "SE-367 AC-5: veredicto estilo court emite y valida path via wrapper" {
    cat > "$TMPD/court.json" <<'EOF'
{
  "verdict_id": "court-20260903-014",
  "judge": "coherence-judge",
  "outcome": "PASS",
  "flow": "SE-367-integration"
}
EOF
    $VP attach "$TMPD/court.json" --store "$STORE" --rule "CRITERIO#coherencia-interna" \
        --trace "tests/fixtures/verdict-path/trace.jsonl" \
        --premises-json '[{"rule":"trace:tool_observed","ground":true,"trace_event":"tool_exec","tool":"build"},{"rule":"ref:source_exists","ref":"AGENTS.md"}]' \
        --evidence-json '[{"ref":"docs/specs/SE-367-derivation-path.spec.md","quote":"cada claim referencia un ref existente o un evento del trace"}]' >/dev/null
    run $VP --validate court-20260903-014 --store "$STORE" --trace "tests/fixtures/verdict-path/trace.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"validate": "OK"'
}

# ── Comportamiento: valores, ramas y códigos de salida (SE-456) ───────────────

@test "SE-367 attach: el fichero guardado contiene rule, premisas y evidencias tal cual" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule "R#1" \
        --premises-json '[{"rule":"p","ref":"https://x.example/doc"}]' \
        --evidence-json '[{"quote":"q"}]'
    [ "$status" -eq 0 ]
    [ "$(jq -r .attached <<<"$output")" = "court-test-001" ]
    [ "$(jq -r .file <<<"$output")" = "$STORE/court-test-001.json" ]
    [ "$(jq -r .path.rule "$STORE/court-test-001.json")" = "R#1" ]
    [ "$(jq -r '.path.premises|length' "$STORE/court-test-001.json")" -eq 1 ]
    [ "$(jq -r '.path.evidence[0].quote' "$STORE/court-test-001.json")" = "q" ]
    # el resto del veredicto se conserva
    [ "$(jq -r .outcome "$STORE/court-test-001.json")" = "FAIL" ]
}

@test "SE-367 attach: premisas desde fichero con --premises-file" {
    echo '[{"rule":"from-file","ref":"verdict:otro"}]' > "$TMPD/prem.json"
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --premises-file "$TMPD/prem.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.path.premises[0].rule' "$STORE/court-test-001.json")" = "from-file" ]
}

@test "SE-367 attach: sin premisas ni evidencias guarda arrays vacíos" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R
    [ "$status" -eq 0 ]
    [ "$(jq -c .path.premises "$STORE/court-test-001.json")" = "[]" ]
    [ "$(jq -c .path.evidence "$STORE/court-test-001.json")" = "[]" ]
}

@test "SE-367 attach: premisas que no son array → exit 2 y nada se guarda" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --premises-json '{"a":1}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"deben ser arrays"* ]]
    [ ! -e "$STORE/court-test-001.json" ]
}

@test "SE-367 attach: veredicto sin verdict_id → exit 2" {
    echo '{"outcome":"PASS"}' > "$TMPD/noid.json"
    run $VP attach "$TMPD/noid.json" --store "$STORE" --rule R
    [ "$status" -eq 2 ]
    [[ "$output" == *"necesita verdict_id"* ]]
}

@test "SE-367 attach: JSON inválido en --premises-json → exit 2" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --premises-json '[{'
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "SE-367 grounding: la tool debe coincidir con la observada, no solo el evento" {
    # tool_exec existe en el trace pero con tool 'build', no 'deploy'
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"ground":true,"trace_event":"tool_exec","tool":"deploy"}]'
    [ "$status" -eq 1 ]
    [[ "$output" == *"premise[0]: trace_event 'tool_exec' tool 'deploy' NO observado"* ]]
    [ ! -e "$STORE/court-test-001.json" ]
}

@test "SE-367 grounding: sin tool declarada basta con que el evento exista" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"ground":true,"trace_event":"tool_blocked"}]'
    [ "$status" -eq 0 ]
}

@test "SE-367 grounding: ground:true sin trace_event es error y señala el índice" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"rule":"ok"},{"ground":true}]'
    [ "$status" -eq 1 ]
    [[ "$output" == *"premise[1]: ground:true sin trace_event"* ]]
}

@test "SE-367 grounding: una evidencia con trace_event se comprueba contra el trace (evidence[i])" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/trace.jsonl" \
        --evidence-json '[{"trace_event":"nunca_visto","ground":true}]'
    [ "$status" -eq 1 ]
    [[ "$output" == *"evidence[0]: trace_event 'nunca_visto'"* ]]
}

@test "SE-367 grounding: sin ground:true un trace_event no observado no bloquea" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/trace.jsonl" \
        --premises-json '[{"trace_event":"nunca_visto"}]'
    [ "$status" -eq 0 ]
}

@test "SE-367 grounding: líneas rotas y vacías del trace se ignoran, las válidas cuentan" {
    printf '\nnot json\n{"event":"build_ok","tool":"t"}\n' > "$TMPD/t2.jsonl"
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/t2.jsonl" \
        --premises-json '[{"ground":true,"trace_event":"build_ok","tool":"t"}]'
    [ "$status" -eq 0 ]
}

@test "SE-367 grounding: trace inexistente equivale a trace vacío (ground falla)" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R --trace "$TMPD/no-existe.jsonl" \
        --premises-json '[{"ground":true,"trace_event":"tool_exec"}]'
    [ "$status" -eq 1 ]
}

@test "SE-367 refs: http, trace# y verdict: no avisan; una ref relativa inexistente sí" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R \
        --premises-json '[{"ref":"https://a.example"},{"ref":"http://a.example"},{"ref":"trace#t-1"},{"ref":"verdict:x"},{"ref":"AGENTS.md"},{"ref":"no/existe/en/repo.md"}]'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: premise[5]: ref inexistente: no/existe/en/repo.md"* ]]
    [ "$(grep -c '^WARN' <<<"$output")" -eq 1 ]
}

@test "SE-367 refs: una ref absoluta existente no avisa" {
    run $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R \
        --premises-json "[{\"ref\":\"$TMPD/trace.jsonl\"}]"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "SE-367 show: devuelve el veredicto guardado" {
    $VP attach "$TMPD/verdict.json" --store "$STORE" --rule R >/dev/null
    run $VP show court-test-001 --store "$STORE"
    [ "$status" -eq 0 ]
    [ "$(jq -r .path.rule <<<"$output")" = "R" ]
    [ "$(jq -r .judge <<<"$output")" = "correctness-judge" ]
}

@test "SE-367 show: veredicto inexistente → exit 2 con la ruta" {
    run $VP show fantasma --store "$STORE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"veredicto no encontrado: $STORE/fantasma.json"* ]]
}

@test "SE-367 expand: premisa verdict: anidada, inexistente y ciclo" {
    mkdir -p "$STORE"
    echo '{"verdict_id":"a","outcome":"FAIL","path":{"rule":"RA","premises":[{"ref":"verdict:b"},{"ref":"verdict:perdido"}],"evidence":[{"quote":"e"}]}}' > "$STORE/a.json"
    echo '{"verdict_id":"b","outcome":"PASS","path":{"rule":"RB","premises":[{"ref":"verdict:a"}],"evidence":[]}}' > "$STORE/b.json"
    run $VP expand a --store "$STORE"
    [ "$status" -eq 0 ]
    [ "$(jq -r .rule <<<"$output")" = "RA" ]
    [ "$(jq -r .outcome <<<"$output")" = "FAIL" ]
    [ "$(jq -r '.premises[0].sub_path.rule' <<<"$output")" = "RB" ]
    [ "$(jq -r '.premises[0].sub_path.outcome' <<<"$output")" = "PASS" ]
    # a → b → a: el segundo 'a' se marca como ciclo y no recursa
    [ "$(jq -r '.premises[0].sub_path.premises[0].sub_path.cycle' <<<"$output")" = "true" ]
    [ "$(jq -r '.premises[1].sub_path.error' <<<"$output")" = "no encontrado" ]
    [ "$(jq -r '.evidence[0].quote' <<<"$output")" = "e" ]
}

@test "SE-367 validate: veredicto guardado con ground roto → exit 1 y errors" {
    mkdir -p "$STORE"
    echo '{"verdict_id":"v1","path":{"rule":"R","premises":[{"ground":true,"trace_event":"tool_exec","tool":"build"}],"evidence":[]}}' > "$STORE/v1.json"
    run $VP validate v1 --store "$STORE" --trace "$TMPD/trace.jsonl"
    [ "$status" -eq 0 ]
    [ "$(jq -r .validate <<<"$output")" = "OK" ]
    run $VP validate v1 --store "$STORE" --trace "$TMPD/vacio.jsonl"
    [ "$status" -eq 1 ]
    [ "$(jq -r .validate <<<"$output")" = "FAIL" ]
    [[ "$(jq -r '.errors[0]' <<<"$output")" == *"grounding fallido"* ]]
}

@test "SE-367 validate: incluye warnings de refs inexistentes sin fallar" {
    mkdir -p "$STORE"
    echo '{"verdict_id":"v2","path":{"rule":"R","premises":[{"ref":"nada/aqui.md"}],"evidence":[]}}' > "$STORE/v2.json"
    run $VP validate v2 --store "$STORE"
    [ "$status" -eq 0 ]
    [ "$(jq -r .validate <<<"$output")" = "OK" ]
    [[ "$(jq -r '.warnings[0]' <<<"$output")" == *"ref inexistente: nada/aqui.md"* ]]
    [ "$(jq 'has("errors")' <<<"$output")" = "false" ]
}

@test "SE-367 --validate acepta el id en cualquier posición y como flag global" {
    mkdir -p "$STORE"
    echo '{"verdict_id":"v3","path":{"rule":"R","premises":[],"evidence":[]}}' > "$STORE/v3.json"
    run $VP --validate v3 --store "$STORE"
    [ "$status" -eq 0 ]
    run $VP --store "$STORE" --validate v3
    [ "$status" -eq 0 ]
    [ "$(jq -r .verdict_id <<<"$output")" = "v3" ]
}

@test "SE-367 --validate sin id → exit 2" {
    run $VP --validate --store "$STORE"
    [ "$status" -eq 2 ]
}

@test "SE-367 sin subcomando → exit 2 con ayuda" {
    run $VP
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
    [[ "$output" == *"SE-367 Derivation Path"* ]]
}

@test "SE-367 --store relativo se resuelve contra la raíz del repo, no el cwd" {
    cd "$TMPD"
    run bash "$BATS_TEST_DIRNAME/../../scripts/verdict-path.sh" attach "$TMPD/verdict.json" --store "tests/.tmp-vp-store-$$" --rule R
    [ "$status" -eq 0 ]
    f="$(jq -r .file <<<"$output")"
    [[ "$f" == "$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tests/.tmp-vp-store-$$/court-test-001.json" ]]
    [ -f "$f" ]
    rm -r "$(dirname "$f")"
}
