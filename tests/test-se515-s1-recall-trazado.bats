#!/usr/bin/env bats
# SE-515 S1 — Recall trazado: learning-recall.sh y el guard de OpenCode registran qué criterios
# devolvieron/emitieron y si la emisión terminó (AC-3); la métrica con valores por defecto sale
# «no medido» y el orquestador usa el recall efectivo o declara shadow (AC-4); arnés de ablación
# P10 (AC-5); interruptor SAVIA_LEARNING_APPLIED=off deja todo como antes (AC-16).
# El registro en el hook de Claude Code y su paridad fila a fila con el guard viven en
# tests/test-se515-s1-hook-trace.bats.
# Ref: docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md (S1)
# Ref: docs/evidence/SE-515-S0-auditoria-linea-base.md §2 (cambio mínimo para S1)

HOOK=".claude/hooks/learning-recall-hook.sh"
RECALL="scripts/learning-recall.sh"
METRIC="scripts/learning-metric.sh"
ORCH="scripts/savia-orchestrator.sh"
ABL="scripts/learning-recall.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.." || exit 1
  REPO="$PWD"
  unset SAVIA_LEARNING_APPLIED SAVIA_LEARNING_RECALL SCL_RECALL_TIMEOUT_S SCL_CRITERIO_PATH
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/scripts"
  export CLAUDE_PROJECT_DIR="$PROJ"
  export SCL_EMISSION_LOG="$BATS_TEST_TMPDIR/emission.jsonl"
  TS_RUNTIME=""
  if command -v bun >/dev/null 2>&1; then TS_RUNTIME="bun"
  elif [[ -x "$HOME/.bun/bin/bun" ]]; then TS_RUNTIME="$HOME/.bun/bin/bun"
  elif node --experimental-strip-types --no-warnings -e '' >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
}

teardown() {
  # Ningún recall falso de este test puede quedar vivo (los de tope y SIGKILL duermen).
  pkill -KILL -f "$PROJ/scripts/learning-recall.sh" 2>/dev/null || true
}

# fake_recall BODY: learning-recall.sh falso con el cuerpo bash dado.
fake_recall() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$PROJ/scripts/learning-recall.sh"
}
HITS='{"effective_hits":[{"criterion_id":"CRIT-001","principle":"Soberania del dato"},{"criterion_id":"CRIT-007","principle":"Otro"}]}'
PROMPT='{"content":"como publico la rama del sprint"}'

hook() { run bash -c 'printf "%s" "$1" | bash "$0"' "$HOOK" "${1:-$PROMPT}"; }
# last_end FIELD: campo de la fila final (phase=end) más reciente.
last_end() { jq -rc "select(.phase==\"end\") | .$1" "$SCL_EMISSION_LOG" | tail -1; }

@test "seguridad: los scripts tocados usan set -uo pipefail y pasan bash -n" {
  for f in "$RECALL" "$METRIC" "$ORCH"; do
    grep -qE '^set -[eu]*o pipefail' "$f" || { echo "sin pipefail: $f"; return 1; }
    bash -n "$f"
  done
}

# ── AC-3: fila por cada inyección ────────────────────────────────────────────

@test "AC-3 missing vault: learning-recall.sh sale 3 y deja fila outcome=no_vault con criterios vacíos" {
  local log="$BATS_TEST_TMPDIR/recall.jsonl"
  run bash "$RECALL" --query "consulta de prueba" --vault "$BATS_TEST_TMPDIR/no-existe" --recall-log "$log"
  [ "$status" -eq 3 ]
  [ "$(jq -r .outcome "$log")" = "no_vault" ]
  [ "$(jq -rc .returned_criteria "$log")" = "[]" ]
}

@test "AC-3 missing CLI: learning-recall.sh sale 3 y deja fila outcome=no_cli" {
  local log="$BATS_TEST_TMPDIR/recall.jsonl" v="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$v"; printf 'CRIT-001 x\n' > "$BATS_TEST_TMPDIR/C.md"
  SCL_VAULT_CLI="$BATS_TEST_TMPDIR/no-cli.js" run bash "$RECALL" --query "consulta" --vault "$v" \
    --criterio "$BATS_TEST_TMPDIR/C.md" --recall-log "$log"
  [ "$status" -eq 3 ]
  [ "$(jq -r .outcome "$log")" = "no_cli" ]
}

@test "AC-3: learning-recall.sh efectivo registra el criterion_id devuelto (outcome=ok)" {
  local v="$BATS_TEST_TMPDIR/vault" log="$BATS_TEST_TMPDIR/recall.jsonl"
  mkdir -p "$v/learning"
  cat > "$v/learning/LP-1.md" <<'EOF'
---
id: LP-1
provenance: human_authored
lifecycle: active
target: criterio
criterion_id: CRIT-001
---
EOF
  printf 'CRIT-001 Soberania\n  principio: Soberania del dato\n  provenance: human_authored\n' > "$BATS_TEST_TMPDIR/C.md"
  printf '#!/usr/bin/env bash\necho %s\n' "'[{\"path\":\"learning/LP-1.md\",\"score\":20}]'" > "$BATS_TEST_TMPDIR/cli.js"
  # node ejecuta el CLI; se sustituye por bash con un "node" falso
  printf '#!/usr/bin/env bash\nexec bash "$@"\n' > "$BATS_TEST_TMPDIR/node"; chmod +x "$BATS_TEST_TMPDIR/node"
  SCL_VAULT_CLI="$BATS_TEST_TMPDIR/cli.js" run bash "$RECALL" --query "soberania" --mode effective --json \
    --vault "$v" --criterio "$BATS_TEST_TMPDIR/C.md" --node-path "$BATS_TEST_TMPDIR/node" --recall-log "$log"
  [ "$status" -eq 0 ]
  [ "$(jq -r .outcome "$log")" = "ok" ]
  [ "$(jq -rc .returned_criteria "$log")" = '["CRIT-001"]' ]
}

# ── AC-16: interruptor ───────────────────────────────────────────────────────

@test "AC-16 disabled: SAVIA_LEARNING_APPLIED=off → learning-recall.sh no escribe fila nueva al salir con 3" {
  local log="$BATS_TEST_TMPDIR/recall.jsonl"
  SAVIA_LEARNING_APPLIED=off run bash "$RECALL" --query "x consulta" --vault "$BATS_TEST_TMPDIR/no" --recall-log "$log"
  [ "$status" -eq 3 ]
  [ ! -e "$log" ]
}

# ── AC-4: métrica no medida ──────────────────────────────────────────────────

@test "AC-4 reject: learning-metric sin --measured → status 'no medido'" {
  run bash "$METRIC" --p-consistent 0.5 --divergence 0.2 --ignorance-resolved 0.1 --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<<"$output")" = "no medido" ]
  [ "$(jq -r .measured <<<"$output")" = "false" ]
  run bash "$METRIC" --p-consistent 0.5 --divergence 0.2 --ignorance-resolved 0.1
  [[ "$output" == *"no medido"* ]]
}

@test "AC-4: learning-metric con --measured → status 'medido' y mismo L" {
  run bash "$METRIC" --p-consistent 0.7 --divergence 0.3 --ignorance-resolved 0.6 --json --measured
  [ "$(jq -r .status <<<"$output")" = "medido" ]
  jq -e ".L == 0.68" <<<"$output" >/dev/null
}

@test "AC-16 disabled: learning-metric con el interruptor off no añade status" {
  SAVIA_LEARNING_APPLIED=off run bash "$METRIC" --p-consistent 0.5 --divergence 0.2 --ignorance-resolved 0.1 --json
  [ "$(jq -r 'has("status")' <<<"$output")" = "false" ]
}

@test "AC-4 reject: el orquestador con valores por defecto marca 'no medido' y nunca dice 'aprendió'" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  unset SAGI_P_CONSISTENT SAGI_L_DIVERGENCE SAGI_L_IGNORANCE_RESOLVED
  run bash "$ORCH" --task "fixture se515 metrica" --iterations 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[medir\].*no medido'
  if echo "$output" | grep -qi 'aprendi'; then echo 'negación falló: echo "$output" | grep -qi aprendi'; return 1; fi
}

@test "AC-4: el orquestador con los tres valores medidos marca 'medido'" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  SAGI_L_DIVERGENCE=0.3 SAGI_L_IGNORANCE_RESOLVED=0.6 run bash "$ORCH" --task "fixture se515 medida" --iterations 1 --p-consistent 0.7
  echo "$output" | grep -q '\[medir\] L=0.68.*(medido)'
  # basta que falte uno para que no cuente como medido
  SAGI_L_DIVERGENCE=0.3 run bash "$ORCH" --task "fixture se515 medida" --iterations 1 --p-consistent 0.7
  echo "$output" | grep -q '\[medir\].*no medido'
}

@test "S1 missing vault: el orquestador declara shadow o no disponible con motivo" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  # sin cúpula: el efectivo no está disponible y lo declara
  SCL_VAULT_DIR="$BATS_TEST_TMPDIR/no-vault" run bash "$ORCH" --task "fixture se515 recall" --iterations 1
  echo "$output" | grep -qE '\[leer\] recall=(shadow \(declarado|no disponible)'
  if echo "$output" | grep -q 'shadow hits de SaviaLearning'; then echo 'negación falló: echo "$output" | grep -q shadow hits de SaviaLearning'; return 1; fi
}

# vault_fixture: cúpula con LP-1 → CRIT-001, CRITERIO y CLI/node falsos; exporta las variables del recall.
vault_fixture() {
  local v="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$v/learning"
  printf -- '---\nid: LP-1\nprovenance: human_authored\nlifecycle: active\ntarget: criterio\ncriterion_id: CRIT-001\n---\n' > "$v/learning/LP-1.md"
  printf 'CRIT-001 Soberania\n  principio: Soberania del dato\n  provenance: human_authored\n' > "$BATS_TEST_TMPDIR/C.md"
  printf '#!/usr/bin/env bash\necho %s\n' "'[{\"path\":\"learning/LP-1.md\",\"score\":20}]'" > "$BATS_TEST_TMPDIR/cli.js"
  printf '#!/usr/bin/env bash\nexec bash "$@"\n' > "$BATS_TEST_TMPDIR/node"; chmod +x "$BATS_TEST_TMPDIR/node"
  export SCL_VAULT_DIR="$v" SCL_CRITERIO_PATH="$BATS_TEST_TMPDIR/C.md" SCL_VAULT_CLI="$BATS_TEST_TMPDIR/cli.js"
  export SCL_NODE_PATH="$BATS_TEST_TMPDIR/node" SCL_RECALL_LOG="$BATS_TEST_TMPDIR/recall.jsonl"
}

@test "S1: con cúpula, el orquestador usa el recall efectivo y nombra los criterios devueltos" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  vault_fixture
  run bash "$ORCH" --task "fixture se515 soberania" --iterations 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\[leer\] recall=effective criterios=\[CRIT-001\]'
  [ "$(jq -r .mode "$SCL_RECALL_LOG")" = "effective" ]
  if echo "$output" | grep -q 'recall=shadow'; then echo 'negación falló: grep -q recall=shadow'; return 1; fi
}

@test "S1 missing vault: el orquestador consulta una sola vez (sin reintento shadow que duplique la fila)" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  export SCL_RECALL_LOG="$BATS_TEST_TMPDIR/recall.jsonl"
  SCL_VAULT_DIR="$BATS_TEST_TMPDIR/no-vault" run bash "$ORCH" --task "fixture se515 una fila" --iterations 1
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SCL_RECALL_LOG")" -eq 1 ]
  [ "$(jq -r .outcome "$SCL_RECALL_LOG")" = "no_vault" ]
  echo "$output" | grep -q 'recall=no disponible (sin cúpula o sin CLI)'
}

@test "AC-16 disabled: orquestador con interruptor off conserva la línea antigua de lectura" {
  export SCL_PROPOSALS_DIR="$BATS_TEST_TMPDIR/lp"; mkdir -p "$SCL_PROPOSALS_DIR"
  SAVIA_LEARNING_APPLIED=off SCL_VAULT_DIR="$BATS_TEST_TMPDIR/no-vault" run bash "$ORCH" --task "fixture se515 off" --iterations 1
  echo "$output" | grep -q 'shadow hits de SaviaLearning'
  if echo "$output" | grep -q 'no medido'; then echo 'negación falló: echo "$output" | grep -q no medido'; return 1; fi
}

# ── Guard de OpenCode (la paridad con el hook está en test-se515-s1-hook-trace.bats) ──

ts_rows() {  # TEXT: ejecuta el guard TS con el recall falso de $PROJ
  SAVIA_WORKSPACE_DIR="$PROJ" $TS_RUNTIME "$REPO/.opencode/plugins/__tests__/learning-recall-guard-cli.ts" "$1" >/dev/null
}

need_ts() {
  if [[ -z "$TS_RUNTIME" && "${SAVIA_REQUIRE_TS:-}" == "1" ]]; then
    echo "SAVIA_REQUIRE_TS=1 y no hay runtime TypeScript" >&2; return 1
  fi
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.6)"
}

@test "AC-3 (OpenCode): emisión completa → filas start y end con emitted=true y los ids, sin el prompt" {
  need_ts
  fake_recall "printf '%s' '$HITS'"
  ts_rows "como publico la rama del sprint"
  [ "$(jq -r 'select(.phase=="start") | .emitted' "$SCL_EMISSION_LOG")" = "false" ]
  [ "$(last_end emitted)" = "true" ]
  [ "$(last_end criteria)" = '["CRIT-001","CRIT-007"]' ]
  [ "$(last_end frontend)" = "opencode" ]
  [ "$(jq -r .event_id "$SCL_EMISSION_LOG" | sort -u | wc -l)" -eq 1 ]
  expected=$(printf '%s' "como publico la rama del sprint" | sha256sum | cut -d' ' -f1)
  [ "$(last_end query_hash)" = "$expected" ]
  if grep -q "publico la rama" "$SCL_EMISSION_LOG"; then echo 'negación falló: grep -q "publico la rama" "$SCL_EMISSION_LOG"'; return 1; fi
  if grep -q "Soberania" "$SCL_EMISSION_LOG"; then echo 'negación falló: grep -q "Soberania" "$SCL_EMISSION_LOG"'; return 1; fi
}

@test "AC-3 error (OpenCode): empty hits, exit 1, exit 3 y salida no JSON → emitted=false con motivo" {
  need_ts
  local body reason
  while IFS='|' read -r body reason; do
    rm -f "$SCL_EMISSION_LOG"
    fake_recall "$body"
    ts_rows "como publico la rama del sprint"
    [ "$(last_end emitted)" = "false" ] || { echo "body=$body"; return 1; }
    [ "$(last_end reason)" = "$reason" ] || { echo "body=$body got=$(last_end reason)"; return 1; }
  done <<'EOF'
printf '%s' '{"effective_hits":[]}'|no_hits
exit 1|error
exit 3|unavailable
echo no-json|bad_output
EOF
}

@test "AC-3 skip (OpenCode): filtros previos (slash, corto, trivial) no abren evento" {
  need_ts
  fake_recall "printf '%s' '$HITS'"
  ts_rows "/sprint-status x"; ts_rows "1234567"; ts_rows "vale"
  [ ! -e "$SCL_EMISSION_LOG" ]
}

@test "AC-16 disabled (OpenCode): SAVIA_LEARNING_APPLIED=off → inyecta igual y no deja filas" {
  need_ts
  fake_recall "printf '%s' '$HITS'"
  run env SAVIA_LEARNING_APPLIED=off SAVIA_WORKSPACE_DIR="$PROJ" $TS_RUNTIME "$REPO/.opencode/plugins/__tests__/learning-recall-guard-cli.ts" "como publico la rama del sprint"
  [ "$output" = '{"injected":true}' ]
  [ ! -e "$SCL_EMISSION_LOG" ]
}

@test "AC-3 timeout (OpenCode): tope vencido → emitted=false reason=timeout" {
  need_ts
  fake_recall "sleep 5"
  SCL_RECALL_TIMEOUT_S=1 ts_rows "como publico la rama del sprint"
  [ "$(last_end reason)" = "timeout" ]
  [ "$(last_end emitted)" = "false" ]
}

# ── AC-5: ablación P10 ───────────────────────────────────────────────────────

mk_cases() {
  CASES="$BATS_TEST_TMPDIR/cases.jsonl"
  cat > "$CASES" <<'EOF'
{"case_id":"c1","prompt":"publica la rama con datos del cliente"}
{"case_id":"c2","prompt":"publica la documentacion del modulo"}
{"case_id":"k1","prompt":"resume el acta de ayer por favor","control":true}
EOF
  # recall falso: solo emite criterio si el prompt menciona "cliente"
  fake_recall 'case "$*" in *cliente*) printf "%s" '"'"'{"effective_hits":[{"criterion_id":"CRIT-001","principle":"Soberania"}]}'"'"' ;; *) printf "%s" '"'"'{"effective_hits":[]}'"'"' ;; esac'
  # decisor falso: bloquea si el contexto trae un criterio
  DECIDER="$BATS_TEST_TMPDIR/decider.sh"
  printf '#!/usr/bin/env bash\njq -e ".context | contains(\\"CRIT-\\")" >/dev/null && echo BLOCK || echo PROCEED\n' > "$DECIDER"
  chmod +x "$DECIDER"
  # inyector: el hook real de recall de Claude Code envuelto (el arnés no conoce el frontend)
  INJECTOR="$BATS_TEST_TMPDIR/injector.sh"
  printf '#!/usr/bin/env bash\nCLAUDE_PROJECT_DIR="$SAVIA_WORKSPACE_DIR" exec bash "%s/%s"\n' "$REPO" "$HOOK" > "$INJECTOR"
  chmod +x "$INJECTOR"
}

@test "AC-5: la ablación cuenta en cuántos casos cambió la decisión" {
  mk_cases
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ" --out "$BATS_TEST_TMPDIR/p10.jsonl"
  [ "$status" -eq 0 ]
  [ "$(jq -r .changed <<<"$output")" = "1" ]
  [ "$(jq -r .cases <<<"$output")" = "3" ]
  [ "$(jq -r .changed_controls <<<"$output")" = "0" ]
  [ "$(jq -r .verdict <<<"$output")" = "cambio" ]
  # formato legible por S09: caso, decisión con y sin recall, coste observado
  row=$(jq -c 'select(.case_id=="c1")' "$BATS_TEST_TMPDIR/p10.jsonl")
  [ "$(jq -r .decision_off <<<"$row")" = "PROCEED" ]
  [ "$(jq -r .decision_on <<<"$row")" = "BLOCK" ]
  jq -e '.cost_ms_on >= 0 and .cost_ms_off >= 0' <<<"$row" >/dev/null
  # sin texto del prompt en el informe
  if grep -q "datos del cliente" "$BATS_TEST_TMPDIR/p10.jsonl"; then echo 'negación falló: grep -q "datos del cliente" "$BATS_TEST_TMPDIR/p10.jsonl"'; return 1; fi
}

@test "AC-5 zero: cero cambios con criterios emitidos es un resultado válido ('sin efecto')" {
  mk_cases
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo PROCEED\n' > "$DECIDER"
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .changed <<<"$output")" = "0" ]
  [ "$(jq -r .verdict <<<"$output")" = "sin efecto" ]
}

@test "AC-5 empty sample: sin ningún criterio emitido el veredicto es 'sin muestra', no 'sin efecto'" {
  mk_cases
  fake_recall "exit 3"
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict <<<"$output")" = "sin muestra" ]
  [ "$(jq -r .emitting_cases <<<"$output")" = "0" ]
}

@test "AC-5 fail: decisor que falla → veredicto 'incompleto' y exit 1" {
  mk_cases
  printf '#!/usr/bin/env bash\nexit 7\n' > "$DECIDER"
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 1 ]
  [ "$(jq -r .verdict <<<"$output")" = "incompleto" ]
}

@test "AC-5 fail: inyector que falla (exit 1, salida rota, sin additionalContext) → 'incompleto' y exit 1, nunca 'sin muestra'" {
  mk_cases
  local body
  for body in 'exit 1' 'echo no-json' 'echo "{\"otro\":1}"'; do
    printf '#!/usr/bin/env bash\ncat >/dev/null\n%s\n' "$body" > "$INJECTOR"
    run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ" --out "$BATS_TEST_TMPDIR/p10.jsonl"
    [ "$status" -eq 1 ] || { echo "body=$body status=$status"; return 1; }
    [ "$(jq -r .verdict <<<"$output")" = "incompleto" ] || { echo "body=$body out=$output"; return 1; }
    [ "$(jq -r .errors <<<"$output")" = "3" ]
    [ "$(jq -s 'map(.injector_failed) | all' "$BATS_TEST_TMPDIR/p10.jsonl")" = "true" ]
  done
}

@test "AC-5 fail: inyector cuyo recall falla por dentro (motivo error/bad_output en su traza) → 'incompleto'" {
  mk_cases
  local body
  for body in 'exit 1' 'echo no-json'; do
    fake_recall "$body"
    run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
    [ "$status" -eq 1 ] || { echo "body=$body status=$status out=$output"; return 1; }
    [ "$(jq -r .verdict <<<"$output")" = "incompleto" ]
  done
}

@test "AC-5 timeout: inyector colgado → 'incompleto', JSON de veredicto y sin directorio temporal huérfano" {
  mk_cases
  printf '{"case_id":"c1","prompt":"publica la rama con datos del cliente"}\n' > "$CASES"
  printf '#!/usr/bin/env bash\nexec sleep 40\n' > "$INJECTOR"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp" SCL_ABLATION_INJECTOR_TIMEOUT_S=2; mkdir -p "$TMPDIR"
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 1 ]
  [ "$(jq -r .verdict <<<"$output")" = "incompleto" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "AC-5 ruido: un control negativo que cambia de decisión → 'ruido' y exit 1, no 'cambio'" {
  mk_cases
  # decisor inestable: cambia de decisión en cada llamada, también en el control
  printf '#!/usr/bin/env bash\ncat >/dev/null; f="%s/n"; n=$(cat "$f" 2>/dev/null || echo 0); echo $((n+1)) > "$f"; (( n %% 2 )) && echo A || echo B\n' "$BATS_TEST_TMPDIR" > "$DECIDER"
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 1 ]
  [ "$(jq -r .changed_controls <<<"$output")" = "1" ]
  [ "$(jq -r .verdict <<<"$output")" = "ruido" ]
}

@test "AC-5 missing: casos ilegibles, decisor o inyector ausente → exit 2" {
  mk_cases
  run bash "$ABL" ablation --cases "$BATS_TEST_TMPDIR/no.jsonl" --injector "$INJECTOR" --decider /bin/true --root "$PROJ"
  [ "$status" -eq 2 ]
  mk_cases
  run bash "$ABL" ablation --cases "$CASES" --injector "$INJECTOR" --decider "$BATS_TEST_TMPDIR/no-decider" --root "$PROJ"
  [ "$status" -eq 2 ]
  run bash "$ABL" ablation --cases "$CASES" --injector "$BATS_TEST_TMPDIR/no-injector" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 2 ]
}

@test "AC-5: inyector y decisor con ruta relativa funcionan aunque el inyector corra en --root" {
  mk_cases
  cd "$BATS_TEST_TMPDIR"
  run bash "$REPO/$ABL" ablation --cases cases.jsonl --injector ./injector.sh --decider ./decider.sh --root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .changed <<<"$output")" = "1" ]
}

@test "AC-5 invalid: casos vacíos → sin muestra; sin case_id/prompt o no JSON → exit 2" {
  mk_cases
  : > "$BATS_TEST_TMPDIR/empty.jsonl"
  run bash "$ABL" ablation --cases "$BATS_TEST_TMPDIR/empty.jsonl" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict <<<"$output")" = "sin muestra" ]
  printf '{"case_id":"x"}\n' > "$BATS_TEST_TMPDIR/bad.jsonl"
  run bash "$ABL" ablation --cases "$BATS_TEST_TMPDIR/bad.jsonl" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 2 ]
  printf 'no-json\n' > "$BATS_TEST_TMPDIR/bad.jsonl"
  run bash "$ABL" ablation --cases "$BATS_TEST_TMPDIR/bad.jsonl" --injector "$INJECTOR" --decider "$DECIDER" --root "$PROJ"
  [ "$status" -eq 2 ]
}

@test "AC-5: el arnés no nombra ningún frontend (guard de agnosticismo SCL-001 S4)" {
  run bash scripts/learning-guard.sh --loop-dir "$REPO/scripts/" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r .vendor_hits <<<"$output")" = "0" ]
}
