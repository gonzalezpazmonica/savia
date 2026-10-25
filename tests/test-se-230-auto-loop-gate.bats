#!/usr/bin/env bats
# Tests for SE-230 Auto-Loop Gate
# Ref: docs/rules/domain/auto-loop-gate.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/auto-loop-gate.sh"
  unset SAVIA_LOOP_CONTEXT 2>/dev/null || true
}

teardown() {
  unset SAVIA_LOOP_CONTEXT 2>/dev/null || true
}

# ── Structural ───────────────────────────────────────────────────────────────

@test "script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "script has safety flags set" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

# ── PROPOSE_LOOP: tdd-vertical-slices via spec+test ──────────────────────────

@test "spec+test -> PROPOSE_LOOP tdd-vertical-slices" {
  run bash "$SCRIPT" --request "implementa la spec SE-200 con tests y dod"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP', d['decision']
assert d['loop_skill']=='tdd-vertical-slices', d['loop_skill']
"
}

@test "spec+acceptance -> PROPOSE_LOOP tdd-vertical-slices max 8 iterations" {
  run bash "$SCRIPT" --request "implementa spec con acceptance criteria definidos"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP'
assert d['loop_skill']=='tdd-vertical-slices'
assert d['max_iterations']==8, d['max_iterations']
"
}

# ── PROPOSE_LOOP: tdd-vertical-slices via bug+reproduce ──────────────────────

@test "bug+reproduce -> PROPOSE_LOOP tdd-vertical-slices max 5" {
  run bash "$SCRIPT" --request "hay un bug que debo reproduce con test"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP', d['decision']
assert d['loop_skill']=='tdd-vertical-slices'
assert d['max_iterations']==5, d['max_iterations']
"
}

@test "bug+falla -> PROPOSE_LOOP tdd-vertical-slices" {
  run bash "$SCRIPT" --request "corrige el bug que falla en el login"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP'
assert d['loop_skill']=='tdd-vertical-slices'
"
}

# ── PROPOSE_LOOP: code-improvement-loop via refactor+coverage ────────────────

@test "refactor+coverage -> PROPOSE_LOOP code-improvement-loop" {
  run bash "$SCRIPT" --request "refactor el modulo auth mejorando coverage"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP', d['decision']
assert d['loop_skill']=='code-improvement-loop', d['loop_skill']
assert d['max_iterations']==6
"
}

# ── PROPOSE_LOOP: court-orchestrator via code review ─────────────────────────

@test "code review -> PROPOSE_LOOP court-orchestrator" {
  run bash "$SCRIPT" --request "necesito un code review de este PR"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP', d['decision']
assert d['loop_skill']=='court-orchestrator', d['loop_skill']
assert d['max_iterations']==3
"
}

@test "pr review -> PROPOSE_LOOP court-orchestrator" {
  run bash "$SCRIPT" --request "haz un pr review del cambio"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP'
assert d['loop_skill']=='court-orchestrator'
"
}

# ── SINGLE_SHOT: conversational ──────────────────────────────────────────────

@test "conversational request -> SINGLE_SHOT" {
  run bash "$SCRIPT" --request "hola como estas, que tal el sprint"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='SINGLE_SHOT', d['decision']
"
}

@test "docs request -> SINGLE_SHOT" {
  run bash "$SCRIPT" --request "actualiza el README con los nuevos endpoints"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='SINGLE_SHOT', d['decision']
"
}

# ── CLARIFY_NEEDED: refactor without criterion ───────────────────────────────

@test "refactor alone -> CLARIFY_NEEDED" {
  run bash "$SCRIPT" --request "refactor el servicio de pagos"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='CLARIFY_NEEDED', d['decision']
"
}

# ── Recursion guard ───────────────────────────────────────────────────────────

@test "SAVIA_LOOP_CONTEXT set -> always SINGLE_SHOT" {
  export SAVIA_LOOP_CONTEXT="active"
  run bash "$SCRIPT" --request "implementa la spec SE-200 con tests y dod"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json; d=json.load(sys.stdin)
assert d['decision']=='SINGLE_SHOT', d['decision']
assert 'recursion' in d['rationale'].lower() or 'recursion' in d.get('rationale','').lower()
"
}

# ── JSON validity ─────────────────────────────────────────────────────────────

@test "output is valid JSON for spec+dod request" {
  run bash "$SCRIPT" --request "spec con criterio de aceptacion y dod"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)"
}

@test "output is valid JSON for SINGLE_SHOT" {
  run bash "$SCRIPT" --request "que tiempo hace"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)"
}

@test "decision field is one of three valid values" {
  run bash "$SCRIPT" --request "cualquier peticion arbitraria sin patron"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['decision'] in ('PROPOSE_LOOP','SINGLE_SHOT','CLARIFY_NEEDED'), d['decision']
"
}

@test "max_iterations is positive int when PROPOSE_LOOP" {
  run bash "$SCRIPT" --request "spec con test de aceptacion"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['decision']=='PROPOSE_LOOP':
  assert isinstance(d['max_iterations'],int) and d['max_iterations']>0, d['max_iterations']
"
}

@test "proposal_text contains loop_skill name when PROPOSE_LOOP" {
  run bash "$SCRIPT" --request "spec con tests y criterio de aceptacion"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d['decision']=='PROPOSE_LOOP':
  assert d['loop_skill'] in (d.get('proposal_text') or ''), 'skill not in proposal_text'
"
}

@test "rationale is non-empty string in PROPOSE_LOOP" {
  run bash "$SCRIPT" --request "hay un bug que reproduce la falla"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP'
assert isinstance(d['rationale'],str) and len(d['rationale'])>0
"
}

# ── New cases (pattern 5: research+depth) ────────────────────────────────────

@test "research+profundidad -> PROPOSE_LOOP tech-research-agent" {
  run bash "$SCRIPT" --request "investiga el rendimiento de la BD en profundidad"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['decision']=='PROPOSE_LOOP', 'expected PROPOSE_LOOP, got: ' + d['decision']
assert d['loop_skill']=='tech-research-agent', 'expected tech-research-agent, got: ' + str(d['loop_skill'])
"
}

# ── CLARIFY_NEEDED proposal_text content ─────────────────────────────────────

@test "CLARIFY_NEEDED proposal_text contains coverage or criterio suggestion" {
  run bash "$SCRIPT" --request "refactor el modulo de autorizacion"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['decision']=='CLARIFY_NEEDED', 'expected CLARIFY_NEEDED, got: ' + d['decision']
pt=(d.get('proposal_text') or '').lower()
assert 'coverage' in pt or 'criterio' in pt, 'proposal_text missing coverage/criterio hint: ' + repr(pt)
"
}

# ── SAVIA_LOOP_CONTEXT with real depth format -> SINGLE_SHOT ─────────────────

@test "SAVIA_LOOP_CONTEXT=overnight-sprint:3 (depth format) -> SINGLE_SHOT" {
  export SAVIA_LOOP_CONTEXT="overnight-sprint:3"
  run bash "$SCRIPT" --request "implementa la spec SE-200 con tests y dod"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['decision']=='SINGLE_SHOT', 'expected SINGLE_SHOT, got: ' + d['decision']
"
}

# ── Embedded double-quotes -> output is valid JSON ───────────────────────────

@test "request with embedded double quotes -> output is valid JSON" {
  run bash "$SCRIPT" --request 'implementar feature "auth" con spec y dod'
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

# ── --request absent -> exit 1 (not JSON) ────────────────────────────────────

@test "--request absent -> exit 1 with error on stderr" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  # output should NOT be parseable JSON (it is an error message)
  echo "${output}${stderr}" | grep -q "request" || true
}

# ── Comportamiento: tabla de decisión completa, precedencia, nulos y errores ──

gate() { run bash "$SCRIPT" --request "$1"; }
field() { echo "$output" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]], ensure_ascii=False))' "$1"; }

@test "cada rama devuelve su skill, criterio de convergencia y presupuesto exactos" {
  local row req skill conv n
  while IFS='|' read -r req skill conv n; do
    gate "$req"
    [ "$status" -eq 0 ]
    [ "$(field decision)" = '"PROPOSE_LOOP"' ] || { echo "decision para: $req -> $output"; return 1; }
    [ "$(field loop_skill)" = "\"$skill\"" ] || { echo "skill para: $req -> $output"; return 1; }
    [ "$(field convergence_criterion)" = "\"$conv\"" ]
    [ "$(field max_iterations)" = "$n" ]
  done <<'EOF'
spec nueva con criterio claro|tdd-vertical-slices|tests_green_and_dod|8
spec con test unitario|tdd-vertical-slices|tests_green_and_dod|8
bug que falla en producción|tdd-vertical-slices|bug_reproduced_and_fixed|5
bug que quiero reproduce|tdd-vertical-slices|bug_reproduced_and_fixed|5
refactor con cobertura mínima|code-improvement-loop|coverage_threshold_met|6
refactor y test de humo|code-improvement-loop|coverage_threshold_met|6
revisar PR 123|court-orchestrator|court_no_blocking_findings|3
review de código del módulo|court-orchestrator|court_no_blocking_findings|3
investiga a fondo el mercado|tech-research-agent|research_saturation|4
analiza en profundidad la API|tech-research-agent|research_saturation|4
research exhaustivo de opciones|tech-research-agent|research_saturation|4
EOF
}

@test "SINGLE_SHOT y CLARIFY_NEEDED llevan null en skill, criterio e iteraciones" {
  gate "hola, cuéntame un chiste"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  [ "$(field loop_skill)" = "null" ]
  [ "$(field convergence_criterion)" = "null" ]
  [ "$(field max_iterations)" = "null" ]
  [ "$(field proposal_text)" = "null" ]
  [ "$(field rationale)" = '"No loop pattern matched — single-shot response appropriate"' ]
  gate "refactor del módulo de pagos"
  [ "$(field decision)" = '"CLARIFY_NEEDED"' ]
  [ "$(field loop_skill)" = "null" ]
  [ "$(field convergence_criterion)" = "null" ]
  [ "$(field max_iterations)" = "null" ]
}

@test "una sola mitad de la condición no basta: bug sin señal, spec sin criterio, investigación sin profundidad" {
  gate "hay un bug raro en el menú"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "lee la spec del proyecto"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "investiga el mercado"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "hay que ser exhaustivo con el informe"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "haz un test del login"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
}

@test "las palabras deben ser enteras: debug, refactoring y prefactor no disparan" {
  gate "debug del test"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "prefactor con test"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  gate "specification con tests"
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
}

@test "precedencia: spec+test gana a bug y a refactor; bug gana a refactor; refactor+test gana a review" {
  gate "spec con test, hay un bug y quiero refactor"
  [ "$(field loop_skill)" = '"tdd-vertical-slices"' ]
  [ "$(field max_iterations)" = "8" ]
  gate "bug que falla y quiero refactor con test"
  [ "$(field max_iterations)" = "5" ]
  gate "refactor con test y code review"
  [ "$(field loop_skill)" = '"code-improvement-loop"' ]
  gate "code review e investiga a fondo"
  [ "$(field loop_skill)" = '"court-orchestrator"' ]
}

@test "refactor con review pero sin test sigue siendo review (no CLARIFY)" {
  gate "refactor y revisar código"
  [ "$(field decision)" = '"PROPOSE_LOOP"' ]
  [ "$(field loop_skill)" = '"court-orchestrator"' ]
}

@test "mayúsculas no importan" {
  gate "IMPLEMENTA LA SPEC CON TEST"
  [ "$(field loop_skill)" = '"tdd-vertical-slices"' ]
}

@test "variantes de review: code-review, code review, pr_review, review de código, revisar pr" {
  local r
  for r in "haz un code-review" "necesito code review" "hazme un pr review rápido" "review de código del equipo" "revisar pr urgente" "revisar código"; do
    gate "$r"
    [ "$(field loop_skill)" = '"court-orchestrator"' ] || { echo "no casó: $r"; return 1; }
  done
}

@test "texto de propuesta exacto para PROPOSE_LOOP y para CLARIFY_NEEDED" {
  gate "implementa la spec con test"
  python3 - "$output" <<'EOP'
import json, sys
d = json.loads(sys.argv[1])
assert d["proposal_text"] == ("Detecto que esta tarea tiene DoD verificable.\\n  Loop sugerido: tdd-vertical-slices\\n"
    "  Criterio de parada: todos los tests en verde y DoD cumplido\\n  Budget máximo: 8 iteraciones\\n\\n"
    "¿Activo el loop? [sí / no / ajustar budget]"), d["proposal_text"]
EOP
  gate "refactor general"
  [[ "$(field proposal_text)" == *"no incluye criterio de convergencia"* ]]
  [[ "$(field proposal_text)" == *"coverage >80%"* ]]
}

@test "etiqueta del criterio por skill en el texto de propuesta" {
  gate "bug que falla"; [[ "$(field proposal_text)" == *"bug reproducido y test en verde"* ]]
  gate "refactor con coverage"; [[ "$(field proposal_text)" == *"cobertura alcanza el umbral configurado"* ]]
  gate "code review"; [[ "$(field proposal_text)" == *"Code Review Court sin hallazgos bloqueantes"* ]]
  gate "investiga a fondo"; [[ "$(field proposal_text)" == *"saturación de fuentes"* ]]
}

@test "la guarda de recursión devuelve SINGLE_SHOT con el contexto en la razón y exit 0 aunque falte --request" {
  SAVIA_LOOP_CONTEXT="loop-padre" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  [[ "$(field rationale)" == *"recursion blocked (context: loop-padre)"* ]]
  [ "$(field convergence_criterion)" = "null" ]
}

@test "SAVIA_LOOP_CONTEXT vacío no activa la guarda" {
  SAVIA_LOOP_CONTEXT="" run bash "$SCRIPT" --request "spec con test"
  [ "$(field decision)" = '"PROPOSE_LOOP"' ]
}

@test "petición vacía: SINGLE_SHOT con razón de vacío y exit 0" {
  run bash "$SCRIPT" --request ""
  [ "$status" -eq 0 ]
  [ "$(field decision)" = '"SINGLE_SHOT"' ]
  [ "$(field rationale)" = '"empty request — no pattern to classify"' ]
}

@test "sin --request: exit 1 con error por stderr y nada en stdout" {
  run bash -c "bash '$SCRIPT' 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run bash "$SCRIPT"
  [[ "$output" == *"ERROR: --request is required"* ]]
  run bash "$SCRIPT" --context /tmp/x
  [ "$status" -eq 1 ]
}

@test "--context y argumentos desconocidos se aceptan sin cambiar la decisión" {
  run bash "$SCRIPT" --context /tmp/nada --nada --request "bug que falla"
  [ "$status" -eq 0 ]
  [ "$(field max_iterations)" = "5" ]
}

@test "comillas y barras en la petición no rompen el JSON" {
  run bash "$SCRIPT" --request 'spec "con" tests \ y dod'
  [ "$status" -eq 0 ]
  [ "$(field decision)" = '"PROPOSE_LOOP"' ]
}
