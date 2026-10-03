#!/usr/bin/env bats
# BATS tests for session-init.sh
# SCRIPT=.opencode/hooks/session-init.sh
# SPEC: SPEC-032 Security Benchmarks — session initialization
# Ref: docs/rules/domain/async-hooks-config.md (sin red síncrona en el arranque)
#
# El arranque no puede esperar a la red: los sondeos de Ollama y Shield corren en
# segundo plano y escriben un fichero de estado que lee el SIGUIENTE arranque.
# Los tests usan un puerto cerrado y un servidor que acepta y nunca responde.

SCRIPT=".opencode/hooks/session-init.sh"
MOCK="tests/fixtures/hook-net-mock/server.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  export TMPDIR="$TMP"
  export CLAUDE_PROJECT_DIR="$(pwd)"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  export SAVIA_PROBE_STATE="$TMP/probes.state"
  : > "$TMP/pids"
}

teardown() {
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  done < "$TMP/pids"
  rm -rf "$TMP"
}

# start_mock MODE → imprime el puerto de un servidor local (ok|blackhole).
start_mock() {
  python3 "$MOCK" "$1" "$TMP/port.$1" >/dev/null 2>&1 &
  echo "$!" >> "$TMP/pids"
  local i
  for i in $(seq 1 50); do
    [[ -s "$TMP/port.$1" ]] && { cat "$TMP/port.$1"; return 0; }
    sleep 0.1
  done
  return 1
}

closed_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

# point_services_to PORT — Ollama y Shield (daemon y proxy) al mismo puerto.
point_services_to() {
  export OLLAMA_URL="http://127.0.0.1:$1"
  export SAVIA_SHIELD_PORT="$1" SAVIA_SHIELD_PROXY_PORT="$1"
}

# run_timed — ejecuta el hook capturando stdout hasta EOF (como un harness que
# espera a que se cierre la tubería) y deja ELAPSED_MS, STATUS y OUT.
run_timed() {
  local s e
  s=$(date +%s%N)
  OUT=$(bash "$SCRIPT" </dev/null 2>/dev/null)
  STATUS=$?
  e=$(date +%s%N)
  ELAPSED_MS=$(( (e - s) / 1000000 ))
}

wait_for_state() {
  local i
  for i in $(seq 1 80); do
    grep -q "^$1$" "$SAVIA_PROBE_STATE" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "script has set -uo pipefail" {
  head -3 "$SCRIPT" | grep -q "set -uo pipefail"
}

@test "positive: runs without error and emits valid SessionStart JSON" {
  point_services_to "$(closed_port)"
  run_timed
  [ "$STATUS" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart"' "$OUT"
}

@test "positive: does not require stdin" {
  point_services_to "$(closed_port)"
  run bash "$SCRIPT" < /dev/null
  [[ "$status" -eq 0 ]]
}

@test "boundary: services that accept and never answer do not block startup (<4s to EOF)" {
  local bh
  bh=$(start_mock blackhole)
  point_services_to "$bh"
  run_timed
  [ "$STATUS" -eq 0 ]
  # Antes: 6.9 s hasta la salida y 14-20 s hasta EOF de stdout.
  [ "$ELAPSED_MS" -lt 4000 ]
}

@test "boundary: closed ports keep startup fast and stdout closes with the process (<4s)" {
  point_services_to "$(closed_port)"
  run_timed
  [ "$STATUS" -eq 0 ]
  # Con HOME aislado el hook antiguo también pasa; la retención de stdout la
  # discrimina el test de mantenimiento lento de fondo.
  [ "$ELAPSED_MS" -lt 4000 ]
}

@test "boundary: slow background maintenance does not hold stdout open (<4s to EOF)" {
  point_services_to "$(closed_port)"
  # Python de memoria vectorial que tarda 8 s: la reconstrucción del índice va
  # en segundo plano y no debe heredar el stdout del hook.
  printf '#!/bin/bash\nsleep 8\nexit 0\n' > "$TMP/slow-python"
  chmod +x "$TMP/slow-python"
  export SAVIA_MEMORY_PYTHON="$TMP/slow-python"
  run_timed
  [ "$STATUS" -eq 0 ]
  [ "$ELAPSED_MS" -lt 4000 ]
}

@test "positive: background probe records Ollama up and next banner reports it" {
  local ok
  ok=$(start_mock ok)
  point_services_to "$ok"
  run_timed
  [ "$STATUS" -eq 0 ]
  wait_for_state "ollama=up"
  grep -q '^shield_daemon=up$' "$SAVIA_PROBE_STATE"
  grep -q '^shield_proxy=up$' "$SAVIA_PROBE_STATE"
  run_timed
  [[ "$OUT" == *"Ollama: activo"* ]]
  [[ "$OUT" == *"Shield: daemon activo"* ]]
}

@test "negative: unresponsive Ollama is recorded down and never claimed active" {
  local bh
  bh=$(start_mock blackhole)
  point_services_to "$bh"
  run_timed
  wait_for_state "ollama=down"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" != *"Ollama: activo"* ]]
  [[ "$OUT" != *"Shield: daemon activo"* ]]
}

@test "edge: first startup without state says the probe runs in background" {
  point_services_to "$(closed_port)"
  run_timed
  [[ "$OUT" == *"Servicios locales: sondeo en segundo plano"* ]]
}

@test "invalid: tampered state file is not executed nor echoed into the banner" {
  point_services_to "$(closed_port)"
  printf 'ts=abc\nollama=up; touch %s/pwned\n$(touch %s/pwned2)\nshield_daemon=maybe\n' \
    "$TMP" "$TMP" > "$SAVIA_PROBE_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ ! -e "$TMP/pwned" && ! -e "$TMP/pwned2" ]]
  [[ "$OUT" != *"touch"* ]]
  [[ "$OUT" != *"Ollama: activo"* ]]
  [[ "$OUT" != *"Shield: daemon activo"* ]]
}

@test "boundary: probe older than 24h is not announced as active" {
  point_services_to "$(closed_port)"
  printf 'ts=%s\nollama=up\nshield_daemon=up\nshield_proxy=up\n' "$(( $(date +%s) - 90000 ))" \
    > "$SAVIA_PROBE_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" != *"Ollama: activo"* ]]
  [[ "$OUT" != *"Shield: daemon activo"* ]]
  [[ "$OUT" == *"caducado"* ]]
}

@test "edge: empty state file is tolerated" {
  point_services_to "$(closed_port)"
  : > "$SAVIA_PROBE_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" == *"PM-Workspace Init"* ]]
}

@test "edge: handles empty environment gracefully" {
  run env -i HOME="$HOME" PATH="$PATH" bash "$SCRIPT"
  [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "coverage: reports PAT status from the local file only" {
  point_services_to "$(closed_port)"
  run_timed
  [[ "$OUT" == *"PAT no configurado"* ]]
  mkdir -p "$HOME/.azure" && echo "x" > "$HOME/.azure/devops-pat"
  run_timed
  [[ "$OUT" == *"PAT ok"* ]]
}
