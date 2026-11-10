#!/usr/bin/env bats
# SE-515 S1 — Recall trazado (parte del hook de Claude Code): el hook y el guard registran qué criterios emitieron y si la
# emisión terminó (AC-3); la métrica con valores por defecto sale «no medido» y el orquestador
# usa el recall efectivo o declara shadow (AC-4); arnés de ablación P10 (AC-5); interruptor
# SAVIA_LEARNING_APPLIED=off deja todo como antes (AC-16).
# Spec: docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md (S1)

HOOK=".claude/hooks/learning-recall-hook.sh"
RECALL="scripts/learning-recall.sh"
METRIC="scripts/learning-metric.sh"
ORCH="scripts/savia-orchestrator.sh"
ABL="scripts/learning-recall-ablation.sh"

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

# fake_recall BODY: learning-recall.sh falso con el cuerpo bash dado.
fake_recall() {
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$PROJ/scripts/learning-recall.sh"
}
HITS='{"effective_hits":[{"criterion_id":"CRIT-001","principle":"Soberania del dato"},{"criterion_id":"CRIT-007","principle":"Otro"}]}'
PROMPT='{"content":"como publico la rama del sprint"}'

hook() { run bash -c 'printf "%s" "$1" | bash "$0"' "$HOOK" "${1:-$PROMPT}"; }
# last_end FIELD: campo de la fila final (phase=end) más reciente.
last_end() { jq -rc "select(.phase==\"end\") | .$1" "$SCL_EMISSION_LOG" | tail -1; }

# ── AC-3: fila por cada inyección ────────────────────────────────────────────

@test "AC-3: emisión completa deja fila end con emitted=true y los ids emitidos" {
  fake_recall "printf '%s' '$HITS'"
  hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"[CRIT-001]"* ]]
  [ "$(last_end emitted)" = "true" ]
  [ "$(last_end criteria)" = '["CRIT-001","CRIT-007"]' ]
  [ "$(last_end reason)" = "emitted" ]
  [ "$(last_end frontend)" = "claude" ]
  # start y end comparten event_id; la clave de cruce con recall.jsonl es query_hash
  [ "$(jq -r .event_id "$SCL_EMISSION_LOG" | sort -u | wc -l)" -eq 1 ]
  expected=$(printf '%s' "como publico la rama del sprint" | sha256sum | cut -d' ' -f1)
  [ "$(last_end query_hash)" = "$expected" ]
}

@test "AC-3: la fila no contiene el texto del prompt ni el principio" {
  fake_recall "printf '%s' '$HITS'"
  hook
  [ -s "$SCL_EMISSION_LOG" ]
  if grep -q "publico la rama" "$SCL_EMISSION_LOG"; then echo 'negación falló: grep -q "publico la rama" "$SCL_EMISSION_LOG"'; return 1; fi
  if grep -q "Soberania" "$SCL_EMISSION_LOG"; then echo 'negación falló: grep -q "Soberania" "$SCL_EMISSION_LOG"'; return 1; fi
}

@test "AC-3 negativo: hook que vence su tope interno → fila emitted=false reason=timeout" {
  fake_recall "sleep 5; printf '%s' '$HITS'"
  SCL_RECALL_TIMEOUT_S=1 hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_end emitted)" = "false" ]
  [ "$(last_end reason)" = "timeout" ]
  [ "$(last_end criteria)" = "[]" ]
}

@test "AC-3 negativo: hook matado sin poder limpiar (SIGKILL) → queda la fila start con emitted=false" {
  fake_recall "sleep 20 # se515-kill-probe"
  bash -c 'printf "%s" "$1" | SCL_RECALL_TIMEOUT_S=20 bash "$0"' "$HOOK" "$PROMPT" &
  local pid=$!
  for _ in $(seq 1 50); do [[ -s "$SCL_EMISSION_LOG" ]] && break; sleep 0.1; done
  kill -KILL "$pid" 2>/dev/null || true
  pkill -KILL -f "se515-kill-probe" 2>/dev/null || true
  pkill -KILL -f "$PROJ/scripts/learning-recall.sh" 2>/dev/null || true
  [ -s "$SCL_EMISSION_LOG" ]
  [ "$(jq -r 'select(.phase=="start") | .emitted' "$SCL_EMISSION_LOG")" = "false" ]
  [ "$(jq -r 'select(.phase=="start") | .reason' "$SCL_EMISSION_LOG")" = "started" ]
  if jq -e 'select(.phase=="end")' "$SCL_EMISSION_LOG" >/dev/null; then echo 'negación falló: jq -e select(.phase=="end") "$SCL_EMISSION_LOG" >/dev/null'; return 1; fi
}

@test "AC-3 negativo: sin aciertos → fila emitted=false reason=no_hits" {
  fake_recall "printf '%s' '{\"effective_hits\":[]}'"
  hook
  [ -z "$output" ]
  [ "$(last_end emitted)" = "false" ]
  [ "$(last_end reason)" = "no_hits" ]
}

@test "AC-3 negativo: recall que falla (exit 1) → reason=error; exit 3 → reason=unavailable" {
  fake_recall "exit 1"
  hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(last_end reason)" = "error" ]
  fake_recall "exit 3"
  hook
  [ "$(last_end reason)" = "unavailable" ]
  [ "$(last_end emitted)" = "false" ]
}

@test "AC-3 negativo: salida no JSON → reason=bad_output, emitted=false" {
  fake_recall "echo esto-no-es-json"
  hook
  [ -z "$output" ]
  [ "$(last_end reason)" = "bad_output" ]
}

@test "AC-3: los filtros previos (slash, corto, trivial) no abren evento ni dejan fila" {
  fake_recall "printf '%s' '$HITS'"
  hook '{"content":"/sprint-status x"}'
  hook '{"content":"1234567"}'
  hook '{"content":"vale"}'
  [ ! -e "$SCL_EMISSION_LOG" ]
}

@test "AC-16: SAVIA_LEARNING_APPLIED=off → mismo stdout del hook y ninguna fila de emisión" {
  fake_recall "printf '%s' '$HITS'"
  SAVIA_LEARNING_APPLIED=off hook
  local off_out="$output"
  [ ! -e "$SCL_EMISSION_LOG" ]
  hook
  [ "$output" = "$off_out" ]
}

@test "paridad: el guard TS registra las mismas filas que el hook ante la misma entrada" {
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript"
  for body in "printf '%s' '$HITS'" "printf '%s' '{\"effective_hits\":[]}'" "exit 1" "exit 3" "echo no-json"; do
    fake_recall "$body"
    rm -f "$SCL_EMISSION_LOG"; hook; local b; b=$(norm)
    rm -f "$SCL_EMISSION_LOG"; ts_rows "como publico la rama del sprint"; local t; t=$(norm)
    [ -n "$b" ]
    [ "$b" = "$t" ] || { echo "body=$body"; echo "bash=$b"; echo "ts=$t"; return 1; }
  done
  [ "$(jq -r .frontend "$SCL_EMISSION_LOG" | sort -u)" = "opencode" ]
}

ts_rows() {  # TEXT: ejecuta el guard TS con el mismo recall falso; filas normalizadas
  SAVIA_WORKSPACE_DIR="$PROJ" $TS_RUNTIME "$REPO/.opencode/plugins/__tests__/learning-recall-guard-cli.ts" "$1" >/dev/null
}
norm() { jq -c 'del(.ts, .event_id, .frontend)' "$SCL_EMISSION_LOG"; }

