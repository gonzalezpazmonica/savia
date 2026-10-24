#!/usr/bin/env bats
# SE-336 S3 — discovery-order-telemetry: orden de descubrimiento por turno
# Ref: docs/specs/SE-336-turn-sdlc.spec.md
# Spec: docs/specs/SE-336-turn-sdlc.spec.md (AC-06, AC-07)

HOOK=".claude/hooks/discovery-order-telemetry.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  export SAVIA_DISCOVERY_TELEMETRY=on
  FIXDIR=$(mktemp -d)
  export SAVIA_DISCOVERY_TELEMETRY_LOG_DIR="$FIXDIR/log"
  export TMPDIR="$FIXDIR/tmp"
  mkdir -p "$TMPDIR"
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "el hook existe, tiene sintaxis valida y usa set -uo pipefail" {
  [[ -f "$HOOK" ]]
  run bash -n "$HOOK"
  [ "$status" -eq 0 ]
  run grep -c '^set -uo pipefail' "$HOOK"
  [[ "$output" -ge 1 ]]
}

tool_call() {
  local tool="$1" prompt="$2" session="$3"
  echo "{\"tool_name\":\"$tool\",\"session_id\":\"$session\",\"prompt_text\":\"$prompt\"}"
}

@test "AC-06a: turno grep-first → order_ok=false" {
  local s="t1"
  rm -f "$TMPDIR"/discovery-order-$s.state
  bash "$HOOK" <<< "$(tool_call grep "buscar SAGI" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call grep "buscar SAGI" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call grep "buscar SAGI" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call savia-vaults_vault_search "buscar SAGI" $s)" >/dev/null
  [[ -f "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl" ]]
  grep -q '"order_ok":"false"' "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
}

@test "AC-06b: turno vault-first → order_ok=true" {
  local s="t2"
  rm -f "$TMPDIR"/discovery-order-$s.state
  bash "$HOOK" <<< "$(tool_call savia-vaults_vault_search "buscar SAGI" $s)" >/dev/null
  [[ -f "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl" ]]
  grep -q '"order_ok":"true"' "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
}

@test "AC-06c: turno solo-escritura → n/a (consolidado por ventana)" {
  local s="t3"
  rm -f "$TMPDIR"/discovery-order-$s.state
  bash "$HOOK" <<< "$(tool_call edit "editar fichero" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call bash "correr tests" $s)" >/dev/null
  # sin knowledge tool: no consolida línea todavía (espera ventana o knowledge)
  # al superar MAX_TOOLS con puro write/exec, el siguiente turno arranca limpio
  for i in $(seq 1 13); do
    bash "$HOOK" <<< "$(tool_call bash "correr tests $i" $s)" >/dev/null
  done
  # tras ventana agotada, siguiente tool knowledge en turno nuevo → ok
  bash "$HOOK" <<< "$(tool_call savia-vaults_vault_search "nueva pregunta" $s)" >/dev/null
  grep -q '"order_ok":"true"' "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
}

@test "AC-06d: 3 filesearch seguidos sin knowledge → order_ok=false" {
  local s="t4"
  rm -f "$TMPDIR"/discovery-order-$s.state
  bash "$HOOK" <<< "$(tool_call glob "buscar md" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call read "fichero" $s)" >/dev/null
  bash "$HOOK" <<< "$(tool_call grep "patron" $s)" >/dev/null
  grep -q '"order_ok":"false"' "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
}

@test "AC-07: JSONL no contiene el prompt en claro (solo query_hash)" {
  local s="t5"
  rm -f "$TMPDIR"/discovery-order-$s.state
  bash "$HOOK" <<< "$(tool_call savia-vaults_vault_search "SECRETO-MARCADOR-QWERTY789" $s)" >/dev/null
  [[ -f "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl" ]]
  ! grep -q "SECRETO-MARCADOR-QWERTY789" "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
  grep -q '"query_hash"' "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"
}

@test "master switch off → exit 0 sin log" {
  local s="t6"
  rm -f "$TMPDIR"/discovery-order-$s.state
  run env SAVIA_DISCOVERY_TELEMETRY=off bash "$HOOK" <<< "$(tool_call savia-vaults_vault_search "x" $s)"
  [[ "$status" -eq 0 ]]
  [[ ! -e "$TMPDIR/discovery-order-$s.state" ]]
  [[ ! -f "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl" ]]
}

@test "tool_name vacío → exit 0 silencioso" {
  run bash "$HOOK" <<< '{"session_id":"t7"}'
  [[ "$status" -eq 0 ]]
}

# ── Comportamiento: secuencia, ventana, hash y aislamiento por sesión ───────────────

LOG() { echo "$SAVIA_DISCOVERY_TELEMETRY_LOG_DIR/discovery-order.jsonl"; }
feed() { bash "$HOOK" <<< "$(tool_call "$1" "${3:-pregunta}" "$2")"; }
field() { python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).read().splitlines()[int(sys.argv[3])])[sys.argv[2]])' "$(LOG)" "$1" "${2:--1}"; }
lines() { wc -l < "$(LOG)" | tr -d ' '; }

@test "first_tools registra la secuencia completa del turno en orden, sin la coma final" {
  feed edit s1 >/dev/null; feed bash s1 >/dev/null; feed savia-vaults_vault_read s1 >/dev/null
  [ "$(lines)" -eq 1 ]
  [ "$(field first_tools)" = "edit,bash,savia-vaults_vault_read" ]
  [ "$(field order_ok)" = "true" ]
}

@test "un solo grep antes de la herramienta de conocimiento ya marca order_ok=false" {
  feed grep s2 >/dev/null; feed vault_search s2 >/dev/null
  [ "$(field order_ok)" = "false" ]
  [ "$(field first_tools)" = "grep,vault_search" ]
}

@test "escritura y ejecucion previas no cuentan como busqueda en ficheros" {
  for t in edit write bash webfetch task todowrite; do feed "$t" s3 >/dev/null; done
  feed vault_graph s3 >/dev/null
  [ "$(field order_ok)" = "true" ]
}

@test "cada herramienta de conocimiento cierra el turno con order_ok=true" {
  n=0
  for t in vault_search vault_read vault_graph vault_list vault_domes memory-store.sh \
           search_graph trace_path codegraph_explore get_code_snippet mcp__x__vault_search; do
    n=$((n+1))
    feed "$t" "k$n" >/dev/null
    [ "$(lines)" -eq "$n" ] || { echo "no emite con $t"; return 1; }
    [ "$(field order_ok)" = "true" ] || { echo "order_ok != true con $t"; return 1; }
  done
}

@test "herramientas desconocidas ni cierran ni cuentan como filesearch" {
  for t in vault_write webfetch notebook unknown_tool; do feed "$t" s4 >/dev/null; done
  [ ! -f "$(LOG)" ]
}

@test "dos filesearch sin conocimiento no consolidan; la tercera si, y limpia el estado" {
  feed read s5 >/dev/null; feed find s5 >/dev/null
  [ ! -f "$(LOG)" ]
  [ -f "$TMPDIR/discovery-order-s5.state" ]
  feed glob s5 >/dev/null
  [ "$(lines)" -eq 1 ]
  [ "$(field order_ok)" = "false" ]
  [ "$(field first_tools)" = "read,find,glob" ]
  [ ! -f "$TMPDIR/discovery-order-s5.state" ]
}

@test "los filesearch no consecutivos tambien suman al umbral de tres" {
  feed grep s6 >/dev/null; feed bash s6 >/dev/null; feed read s6 >/dev/null; feed edit s6 >/dev/null
  [ ! -f "$(LOG)" ]
  feed glob s6 >/dev/null
  [ "$(field order_ok)" = "false" ]
  [ "$(field first_tools)" = "grep,bash,read,edit,glob" ]
}

@test "el estado guarda la secuencia y el contador en dos lineas" {
  feed bash s7 >/dev/null; feed edit s7 >/dev/null
  [ "$(sed -n 1p "$TMPDIR/discovery-order-s7.state")" = "bash,edit," ]
  [ "$(sed -n 2p "$TMPDIR/discovery-order-s7.state")" = "2" ]
}

@test "la ventana se reinicia al llegar a MAX_TOOLS y el turno nuevo empieza limpio" {
  export SAVIA_DISCOVERY_TELEMETRY_MAX_TOOLS=3
  feed bash s8 >/dev/null; feed bash s8 >/dev/null; feed bash s8 >/dev/null
  feed vault_search s8 >/dev/null
  [ "$(field first_tools)" = "vault_search" ]
}

@test "por debajo de MAX_TOOLS la secuencia se conserva" {
  export SAVIA_DISCOVERY_TELEMETRY_MAX_TOOLS=3
  feed bash s9 >/dev/null; feed bash s9 >/dev/null
  feed vault_search s9 >/dev/null
  [ "$(field first_tools)" = "bash,bash,vault_search" ]
}

@test "la ventana tambien descarta los grep acumulados: tras reiniciar ya no penalizan" {
  export SAVIA_DISCOVERY_TELEMETRY_MAX_TOOLS=2
  feed grep s10 >/dev/null; feed bash s10 >/dev/null
  feed vault_read s10 >/dev/null
  [ "$(field order_ok)" = "true" ]
}

@test "las sesiones llevan estado independiente" {
  feed grep sa >/dev/null
  feed vault_search sb >/dev/null
  [ "$(field order_ok)" = "true" ]
  feed vault_search sa >/dev/null
  [ "$(field order_ok)" = "false" ]
  [ "$(field first_tools)" = "grep,vault_search" ]
}

@test "query_hash es el sha256 truncado a 16 hex del prompt" {
  feed vault_search sh "pregunta concreta" >/dev/null
  exp=$(printf '%s' "pregunta concreta" | sha256sum | cut -c1-16)
  [ "$(field query_hash)" = "$exp" ]
}

@test "el hash cambia con el prompt y se calcula sobre content si no hay prompt_text" {
  feed vault_search sh1 "uno" >/dev/null
  feed vault_search sh2 "dos" >/dev/null
  [ "$(field query_hash 0)" != "$(field query_hash 1)" ]
  echo '{"tool_name":"vault_search","session_id":"sh3","content":"desde content"}' | bash "$HOOK"
  exp=$(printf '%s' "desde content" | sha256sum | cut -c1-16)
  [ "$(field query_hash 2)" = "$exp" ]
}

@test "solo los primeros 2000 caracteres del prompt entran en el hash" {
  a=$(printf 'a%.0s' $(seq 1 2000))
  feed vault_search sl1 "${a}XXXX" >/dev/null
  feed vault_search sl2 "${a}YYYY" >/dev/null
  [ "$(field query_hash 0)" = "$(field query_hash 1)" ]
  feed vault_search sl3 "b${a}" >/dev/null
  [ "$(field query_hash 2)" != "$(field query_hash 0)" ]
}

@test "cada linea es JSON valido con ts UTC y las cuatro claves" {
  feed vault_search sj >/dev/null
  run python3 -c '
import json,re,sys
d=json.loads(open(sys.argv[1]).read())
assert set(d)=={"ts","query_hash","first_tools","order_ok"}, d
assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", d["ts"]), d["ts"]
assert re.fullmatch(r"[0-9a-f]{16}", d["query_hash"]), d' "$(LOG)"
  [ "$status" -eq 0 ]
}

@test "las lineas se anaden al fichero, no lo sobrescriben" {
  feed vault_search sp1 >/dev/null
  feed grep sp2 >/dev/null; feed vault_search sp2 >/dev/null
  [ "$(lines)" -eq 2 ]
  [ "$(field order_ok 0)" = "true" ]
  [ "$(field order_ok 1)" = "false" ]
}

@test "sin session_id usa la sesion unknown" {
  echo '{"tool_name":"bash"}' | bash "$HOOK"
  [ -f "$TMPDIR/discovery-order-unknown.state" ]
}

@test "nunca escribe en stdout y siempre sale con 0" {
  run feed vault_search so
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run feed grep so2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "la entrada que no es JSON se ignora sin crear estado ni log" {
  run bash "$HOOK" <<< "esto no es json"
  [ "$status" -eq 0 ]
  [ ! -f "$(LOG)" ]
  [ -z "$(ls "$TMPDIR")" ]
}

@test "sin SAVIA_DISCOVERY_TELEMETRY_LOG_DIR escribe en output/learning-loop del cwd" {
  unset SAVIA_DISCOVERY_TELEMETRY_LOG_DIR
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W"
  ( cd "$W" && tool_call vault_search q sd | bash "$OLDPWD/$HOOK" )
  [ -f "$W/output/learning-loop/discovery-order.jsonl" ]
}

@test "SAVIA_DISCOVERY_TELEMETRY distinto de off sigue activo" {
  SAVIA_DISCOVERY_TELEMETRY=on feed vault_search sv >/dev/null
  [ "$(lines)" -eq 1 ]
}
