#!/usr/bin/env bats
# test-savia-shield-daemon-paths.bats — CodeQL #30/#31/#32 (py/path-injection)
# El /gate del daemon solo lee ficheros dentro del workspace (realpath) y el
# daemon nunca sirve sin token: oráculo de un bit cerrado.
# Ref: docs/evidence/graduacion-s27/SE-442-triaje-alertas.md (prioridad 2)
# Target: scripts/savia-shield-daemon.py

setup() {
  set -uo pipefail
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DAEMON="$REPO/scripts/savia-shield-daemon.py"
  BASE="$(mktemp -d "${BATS_TMPDIR:-/tmp}/sdp-XXXXXX")"
  WS="$BASE/ws"
  OUT_DIR="$BASE/fuera"
  mkdir -p "$WS/docs" "$OUT_DIR"
  # Credencial partida: la primera mitad en disco, la segunda en la escritura.
  # Se construye por trozos para no disparar el propio gate al editar este test.
  HALF_DISK="Serv""er=db01;"
  export HALF_WRITE="Pass""word=hunter2zz"
  # Sin salto de línea: la regex de credencial partida no cruza líneas.
  printf '%s' "$HALF_DISK" > "$OUT_DIR/secreto.txt"
  printf '%s' "$HALF_DISK" > "$WS/docs/config.txt"
  ln -s "$OUT_DIR/secreto.txt" "$WS/docs/enlace.txt"
  export FAKE_HOME="$BASE/home"
  mkdir -p "$FAKE_HOME"
  FREE_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
}

last_line() { printf '%s' "${lines[${#lines[@]}-1]}"; }

teardown() {
  rm -rf "$BASE" 2>/dev/null || true
}

# gate_verdict <file_path> [content] → veredicto de gate() con CWD=/ y PROJ=$WS
gate_verdict() {
  ( cd / && CLAUDE_PROJECT_DIR="$WS" HOME="$FAKE_HOME" python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ssd", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.gate({"tool_input": {"file_path": sys.argv[2], "content": sys.argv[3]}})
print(r["verdict"])
' "$DAEMON" "$1" "${2:-$HALF_WRITE}" )
}

# --- Dentro del workspace: la detección de credencial partida sigue viva ---

@test "absolute path inside workspace: split credential is BLOCKED" {
  run gate_verdict "$WS/docs/config.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "BLOCK" ]
}

@test "relative path resolves against the workspace, not the daemon CWD" {
  run gate_verdict "docs/config.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "BLOCK" ]
}

# --- Fuera del workspace: no se lee el fichero (sin oráculo) ---

@test "absolute path outside workspace: file is not read" {
  run gate_verdict "$OUT_DIR/secreto.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "ALLOW" ]
}

@test "dot-dot escape from workspace: file is not read" {
  run gate_verdict "$WS/docs/../../fuera/secreto.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "ALLOW" ]
}

@test "relative dot-dot escape: file is not read" {
  run gate_verdict "../fuera/secreto.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "ALLOW" ]
}

@test "symlink inside workspace pointing outside: file is not read" {
  run gate_verdict "$WS/docs/enlace.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "ALLOW" ]
}

@test "outside workspace: content is still scanned and credentials BLOCKED" {
  run gate_verdict "$OUT_DIR/nuevo.txt" "key=AKIA""ABCDEFGHIJKLMNOP"
  [ "$status" -eq 0 ]
  [ "$output" = "BLOCK" ]
}

# --- Token: nunca «open access» ---

@test "no token: daemon creates one with mode 0600 and requires it" {
  run env HOME="$FAKE_HOME" python3 -I -c '
import importlib.util, os, stat, sys
spec = importlib.util.spec_from_file_location("ssd", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ok = m.load_token()
tp = os.path.join(os.environ["HOME"], ".savia", "shield-token")
mode = stat.S_IMODE(os.stat(tp).st_mode)
class F: headers = {}
print(ok, bool(m.TOKEN), oct(mode), m.H._check_auth(F()))
' "$DAEMON"
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "True True 0o600 False" ]
}

@test "with token: wrong or missing header rejected, right header accepted" {
  mkdir -p "$FAKE_HOME/.savia"
  printf 'tok-123\n' > "$FAKE_HOME/.savia/shield-token"
  run env HOME="$FAKE_HOME" python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ssd", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.load_token()
class F: pass
res = []
for h in ({}, {"X-Shield-Token": "otro"}, {"X-Shield-Token": "tok-123"}):
    f = F(); f.headers = h; res.append(m.H._check_auth(f))
print(res)
' "$DAEMON"
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "[False, False, True]" ]
}

@test "empty token file: daemon refuses to start (fail-closed)" {
  mkdir -p "$FAKE_HOME/.savia"
  : > "$FAKE_HOME/.savia/shield-token"
  run env HOME="$FAKE_HOME" timeout 5 python3 -I "$DAEMON" --port "$FREE_PORT"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"token"* ]]
}

@test "token cannot be created: daemon refuses to start (fail-closed)" {
  # ~/.savia es un fichero: no se puede crear el token
  : > "$FAKE_HOME/.savia"
  run env HOME="$FAKE_HOME" timeout 5 python3 -I "$DAEMON" --port "$FREE_PORT"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"token"* ]]
}
