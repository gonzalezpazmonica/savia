#!/usr/bin/env bats
# BATS tests for .opencode/hooks/shield-autostart.sh
# SessionStart hook — Savia Shield (daemon :8444 + proxy :8443), opt-in.
# Fire-and-forget: el launcher y la comprobación de salud corren en segundo
# plano; el hook nunca espera a la red. El resultado queda en un fichero de
# estado que lee el siguiente arranque.
# Ref: docs/rules/domain/async-hooks-config.md · SPEC-071 (Savia Shield)

HOOK=".opencode/hooks/shield-autostart.sh"
SCRIPT=".opencode/hooks/shield-autostart.sh"
MOCK="tests/fixtures/hook-net-mock/server.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP="$(mktemp -d)"
  export TMPDIR="$TMP"
  export HOME="$TMP/home"
  mkdir -p "$HOME" "$TMP/proj/scripts"
  export CLAUDE_PROJECT_DIR="$TMP/proj"
  export SAVIA_SHIELD_STATE="$TMP/shield.state"
  export FAKE_LAUNCH_LOG="$TMP/launch.log"
  # Launcher falso: registra la invocación y tarda FAKE_LAUNCH_SLEEP segundos.
  cat > "$TMP/proj/scripts/shield-launcher.py" <<'PY'
import os, sys, time
with open(os.environ["FAKE_LAUNCH_LOG"], "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
time.sleep(float(os.environ.get("FAKE_LAUNCH_SLEEP", "0")))
PY
  unset SAVIA_SHIELD_ENABLED CI GITHUB_ACTIONS CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true
  export SAVIA_SHIELD_AUTOSTART=on
  : > "$TMP/pids"
}

teardown() {
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
  done < "$TMP/pids"
  rm -rf "$TMP"
  cd /
}

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

ports_to() { export SAVIA_SHIELD_PORT="$1" SAVIA_SHIELD_PROXY_PORT="$1"; }

# run_timed — stdout capturado hasta EOF; deja OUT, STATUS y ELAPSED_MS.
run_timed() {
  local s e
  s=$(date +%s%N)
  OUT=$(bash "$HOOK" <<< "${1:-}" 2>/dev/null)
  STATUS=$?
  e=$(date +%s%N)
  ELAPSED_MS=$(( (e - s) / 1000000 ))
}

wait_for() {
  local i
  for i in $(seq 1 100); do
    grep -q "$1" "$2" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "hook exists and passes bash -n" {
  [[ -f "$HOOK" ]]
  run bash -n "$HOOK"
  [ "$status" -eq 0 ]
}

@test "uses set -uo pipefail" {
  head -3 "$HOOK" | grep -q 'set -uo pipefail'
}

@test "boundary: slow launcher and closed ports do not block the session (<2s)" {
  ports_to "$(closed_port)"
  export FAKE_LAUNCH_SLEEP=10
  run_timed
  [ "$STATUS" -eq 0 ]
  # Antes: 15.5 s esperando al daemon en primer plano.
  [ "$ELAPSED_MS" -lt 2000 ]
  [[ "$OUT" == *"arranque lanzado en segundo plano"* ]]
}

@test "boundary: unresponsive health endpoints do not block the session (<2s)" {
  ports_to "$(start_mock blackhole)"
  run_timed
  [ "$STATUS" -eq 0 ]
  [ "$ELAPSED_MS" -lt 2000 ]
}

@test "positive: launcher start runs in background" {
  ports_to "$(closed_port)"
  run_timed
  wait_for '^start$' "$FAKE_LAUNCH_LOG"
}

@test "positive: healthy daemon and proxy are recorded and reported next session" {
  ports_to "$(start_mock ok)"
  run_timed
  wait_for '^proxy=up$' "$SAVIA_SHIELD_STATE"
  grep -q '^daemon=up$' "$SAVIA_SHIELD_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" == *"daemon activo, proxy activo"* ]]
  python3 -c 'import json,sys; json.loads(sys.argv[1])' "$OUT"
}

@test "negative: hung Shield is recorded as not responding" {
  ports_to "$(start_mock blackhole)"
  run_timed
  wait_for '^proxy=down$' "$SAVIA_SHIELD_STATE"
  grep -q '^daemon=down$' "$SAVIA_SHIELD_STATE"
  run_timed
  [[ "$OUT" == *"daemon no responde, proxy no responde"* ]]
}

@test "negative: autostart off (default) skips without launching" {
  unset SAVIA_SHIELD_AUTOSTART
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ -z "$OUT" ]]
  sleep 0.3
  [[ ! -s "$FAKE_LAUNCH_LOG" ]]
}

@test "negative: SAVIA_SHIELD_ENABLED=false skips early" {
  SAVIA_SHIELD_ENABLED=false run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "negative: CI and SDK entrypoints skip" {
  CI=true run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]; [[ -z "$output" ]]
  CLAUDE_CODE_ENTRYPOINT=sdk-ts run bash "$HOOK" <<< ""
  [ "$status" -eq 0 ]; [[ -z "$output" ]]
}

@test "error: missing launcher is reported, not fatal" {
  mv "$TMP/proj/scripts/shield-launcher.py" "$TMP/launcher.bak"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" == *"launcher no encontrado"* ]]
}

@test "edge: concurrent sessions launch Shield only once" {
  command -v flock >/dev/null 2>&1 || skip "flock no disponible"
  ports_to "$(closed_port)"
  export FAKE_LAUNCH_SLEEP=2
  bash "$HOOK" <<< "" >/dev/null 2>&1 &
  bash "$HOOK" <<< "" >/dev/null 2>&1 &
  wait
  wait_for '^start$' "$FAKE_LAUNCH_LOG"
  sleep 2.5
  [ "$(grep -c '^start$' "$FAKE_LAUNCH_LOG")" -eq 1 ]
}

@test "invalid: tampered state file is neither executed nor echoed" {
  ports_to "$(closed_port)"
  printf 'ts=1\ndaemon=up; touch %s/pwned\n$(touch %s/pwned2)\nproxy=maybe\n' "$TMP" "$TMP" \
    > "$SAVIA_SHIELD_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ ! -e "$TMP/pwned" && ! -e "$TMP/pwned2" ]]
  [[ "$OUT" != *"touch"* ]]
  [[ "$OUT" != *"daemon activo"* ]]
}

@test "boundary: result older than 24h is not reported as current" {
  ports_to "$(closed_port)"
  printf 'ts=%s\ndaemon=up\nproxy=up\n' "$(( $(date +%s) - 90000 ))" > "$SAVIA_SHIELD_STATE"
  run_timed
  [ "$STATUS" -eq 0 ]
  [[ "$OUT" != *"daemon activo"* ]]
  [[ "$OUT" == *"arranque lanzado en segundo plano"* ]]
}

@test "edge: empty or random stdin always exits 0" {
  ports_to "$(closed_port)"
  local input
  for input in '' 'random' '{"type":"session-start"}'; do
    run_timed "$input"
    [ "$STATUS" -eq 0 ]
  done
}

@test "isolation: hook does not modify repo files" {
  ports_to "$(closed_port)"
  local before after
  before=$(git -C "$BATS_TEST_DIRNAME/.." status --porcelain | wc -l)
  run_timed
  after=$(git -C "$BATS_TEST_DIRNAME/.." status --porcelain | wc -l)
  [[ "$before" == "$after" ]]
}
