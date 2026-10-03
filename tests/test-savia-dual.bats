#!/usr/bin/env bats
# SE-376 — savia-dual: comportamiento real del proxy de failover y del instalador.
# Todo es local: upstreams falsos en 127.0.0.1 (API de mensajes estilo Anthropic y uno
# solo compatible con OpenAI), HOME temporal y stubs de ollama/curl/sudo/systemctl.
# Nunca se contacta un proveedor real ni se lee una clave real.
# Ref: docs/rules/domain/savia-dual.md · docs/savia-dual.md · .claude/skills/savia-dual/SKILL.md
set -uo pipefail

PROXY="scripts/savia-dual-proxy.py"
SCRIPT="scripts/setup-savia-dual.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  PIDS=()
  FAKE_KEY="sk-ant-FAKE-$RANDOM-NOT-A-KEY"
  PROMPT_MARK="PROMPT-$RANDOM-MARK"
  # Upstream falso. Uso: fake.py <port_file> <record_file> <modo> [nombre]
  # Registra (path, método, cabeceras en minúsculas) de cada petición recibida.
  cat > "$WORK/fake.py" <<'PY'
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port_file, record, mode = sys.argv[1], sys.argv[2], sys.argv[3]
name = sys.argv[4] if len(sys.argv) > 4 else "upstream"
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass
    def _rec(self):
        n = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        with open(record, "a") as fh:
            fh.write(json.dumps({"path": self.path, "method": self.command,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body}) + "\n")
    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers(); self.wfile.write(data)
    def _serve(self):
        self._rec()
        if mode == "ok":
            self._json(200, {"type": "message", "content": [{"type": "text", "text": name}]})
        elif mode.startswith("status:"):
            self._json(int(mode.split(":")[1]), {"type": "error", "error": {"type": "fake"}})
        elif mode.startswith("slow:"):
            time.sleep(float(mode.split(":")[1]))
            self._json(200, {"type": "message", "content": [{"type": "text", "text": name}]})
        elif mode == "openai":
            if self.path.startswith("/v1/chat/completions"):
                self._json(200, {"object": "chat.completion", "choices": []})
            else:
                self._json(404, {"error": {"message": "not found"}})
        elif mode == "ssechunkcut":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            ev = b"event: message_start\ndata: {}\n\n"
            self.wfile.write(b"%x\r\n%s\r\n" % (len(ev), ev))
            self.wfile.flush()
        elif mode.startswith("sse"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            if mode == "ssecut":
                self.send_header("Content-Length", "100000")
            self.end_headers()
            self.wfile.write(b"event: message_start\ndata: {\"type\":\"message_start\"}\n\n")
            self.wfile.flush()
            time.sleep(3)
            if mode == "ssecut":
                return
            self.wfile.write(b"event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
    do_GET = do_POST = _serve
s = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
}

teardown() {
  local p
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$WORK"
}

wait_file() { local i; for i in $(seq 1 100); do [[ -s "$1" ]] && return 0; sleep 0.1; done; return 1; }

# start_fake <alias> <modo>: exporta <ALIAS>_PORT y deja el registro en $WORK/<alias>.rec
start_fake() {
  : > "$WORK/$1.rec"
  python3 "$WORK/fake.py" "$WORK/$1.port" "$WORK/$1.rec" "$2" "$1" &
  PIDS+=("$!")
  wait_file "$WORK/$1.port"
  printf -v "${1^^}_PORT" '%s' "$(cat "$WORK/$1.port")"
}

# write_config <primary_port> <ollama_port> [timeout] [listen_host]
write_config() {
  cat > "$WORK/config.json" <<JSON
{"listen_host": "${4:-127.0.0.1}", "listen_port": 0,
 "anthropic_upstream": "http://127.0.0.1:$1", "ollama_upstream": "http://127.0.0.1:$2",
 "fallback_triggers": {"timeout_seconds": ${3:-5}},
 "circuit_breaker": {"consecutive_failures": 3, "cooldown_seconds": 60},
 "local_model": "gemma4:e2b", "log_path": "$WORK/events.jsonl"}
JSON
}

start_proxy() {
  PROXY_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 "$REPO_ROOT/$PROXY" --config "$WORK/config.json" --port "$PROXY_PORT" "$@" 2> "$WORK/proxy.log" &
  PIDS+=("$!")
  local i
  for i in $(seq 1 100); do
    curl -s -o /dev/null "http://127.0.0.1:$PROXY_PORT/health" && return 0
    sleep 0.1
  done
  cat "$WORK/proxy.log"; return 1
}

post() { # post <path> [curl args...] → cuerpo en $WORK/resp, código en stdout
  local p="$1"; shift
  curl -s -o "$WORK/resp" -w '%{http_code}' -X POST "http://127.0.0.1:$PROXY_PORT$p" \
    -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' \
    -H "X-API-Key: $FAKE_KEY" -H "Authorization: Bearer $FAKE_KEY" -H "Cookie: s=$FAKE_KEY" \
    -d "{\"model\":\"claude-x\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT_MARK\"}]}" "$@"
}

count() { wc -l < "$WORK/$1.rec" | tr -d ' '; }

# `! grep` no hace fallar un test de bats; esta función sí.
refute_grep() { if grep -q "$@"; then echo "encontrado: $*" >&2; return 1; fi; }

# ── Proxy: rutas felices ─────────────────────────────────────────────────────

@test "proxy: primario 200 se devuelve tal cual y ollama no recibe nada" {
  start_fake primary ok; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "200" ]
  grep -q '"primary"' "$WORK/resp"
  [ "$(count ollama)" = 0 ]
  grep -q '"route": "anthropic"' "$WORK/events.jsonl"
}

@test "proxy: escucha en loopback por defecto y /health responde ok" {
  start_fake primary ok; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  grep -q 'listening on http://127.0.0.1:' "$WORK/proxy.log"
  run curl -s "http://127.0.0.1:$PROXY_PORT/health"
  [ "$output" = '{"status": "ok"}' ]
}

# ── Proxy: failover y fugas de credenciales ─────────────────────────────────

@test "failover: 503 del primario cae a ollama sin filtrar x-api-key, authorization ni cookie" {
  start_fake primary status:503; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "200" ]
  grep -q '"ollama"' "$WORK/resp"
  [ "$(count ollama)" = 1 ]
  refute_grep "$FAKE_KEY" "$WORK/ollama.rec"
  run python3 -c 'import json,sys; print(json.loads(json.loads(open(sys.argv[1]).readline())["body"])["model"])' "$WORK/ollama.rec"
  [ "$output" = "gemma4:e2b" ]
}

@test "failover: 429 cae a ollama con motivo http_429 en el log" {
  start_fake primary status:429; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "200" ]
  grep -q '"fallback_reason": "http_429"' "$WORK/events.jsonl"
}

@test "log: events.jsonl no contiene la clave ni el prompt (failover y ruta primaria)" {
  start_fake primary status:500; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  post /v1/messages >/dev/null
  [ -s "$WORK/events.jsonl" ]
  refute_grep "$FAKE_KEY" "$WORK/events.jsonl" "$WORK/proxy.log"
  refute_grep "$PROMPT_MARK" "$WORK/events.jsonl" "$WORK/proxy.log"
}

@test "reject: 401 del primario se devuelve al cliente sin caer a ollama" {
  start_fake primary status:401; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "401" ]
  [ "$(count ollama)" = 0 ]
}

@test "reject: 4xx repetidos no abren el circuit breaker" {
  start_fake primary status:400; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  local i; for i in 1 2 3 4; do post /v1/messages >/dev/null; done
  [ "$(count primary)" = 4 ]
  [ "$(count ollama)" = 0 ]
}

@test "breaker: tras 3 fallos 5xx el primario deja de recibir peticiones" {
  start_fake primary status:502; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  local i; for i in 1 2 3 4 5; do post /v1/messages >/dev/null; done
  [ "$(count primary)" = 3 ]
  [ "$(count ollama)" = 5 ]
  grep -q '"fallback_reason": "circuit_open"' "$WORK/events.jsonl"
}

@test "timeout: primario lento por encima de timeout_seconds cae a ollama" {
  start_fake primary slow:4; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT" 1; start_proxy
  run post /v1/messages
  [ "$output" = "200" ]
  grep -q '"ollama"' "$WORK/resp"
  grep -q '"fallback_reason": "network_error' "$WORK/events.jsonl"
}

@test "error: primario y ollama caídos devuelven 503 JSON con route none" {
  # Puertos de servidores ya parados: conexión rechazada en ambos.
  start_fake primary ok; start_fake ollama ok
  kill "${PIDS[0]}" "${PIDS[1]}"; sleep 0.3
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "503" ]
  grep -q '"upstream_unavailable"' "$WORK/resp"
  grep -q '"route": "none"' "$WORK/events.jsonl"
}

@test "efectos: rutas distintas de /v1/messages no se repiten contra ollama" {
  start_fake primary status:503; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages/batches
  [ "$output" = "503" ]
  run curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PROXY_PORT/v1/models"
  [ "$output" = "503" ]
  [ "$(count ollama)" = 0 ]
}

@test "upstream OpenAI-only como fallback: el 404 se propaga, sin reintentos" {
  start_fake primary status:503; start_fake ollama openai
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run post /v1/messages
  [ "$output" = "404" ]
  [ "$(count ollama)" = 1 ]
  [ "$(count primary)" = 1 ]
}

# ── Proxy: streaming SSE ────────────────────────────────────────────────────

@test "sse: el primer evento llega antes de que el upstream termine (sin bufferizar)" {
  start_fake primary sse; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  local ttfb
  ttfb="$(curl -s -N -o "$WORK/resp" -w '%{time_starttransfer}' -X POST \
    "http://127.0.0.1:$PROXY_PORT/v1/messages" -H 'Content-Type: application/json' -d '{}')"
  [ -n "$ttfb" ]
  grep -q 'message_stop' "$WORK/resp"
  awk -v t="$ttfb" 'BEGIN { exit !(t < 2.5) }'
}

@test "sse: un stream cortado termina con evento error y no se repite contra ollama" {
  start_fake primary ssecut; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  post /v1/messages -N >/dev/null || true
  grep -q 'message_start' "$WORK/resp"
  grep -q '^event: error' "$WORK/resp"
  [ "$(count ollama)" = 0 ]
  grep -q '"stream_interrupted"' "$WORK/events.jsonl"
  # El proxy sigue vivo tras el corte.
  run curl -s "http://127.0.0.1:$PROXY_PORT/health"
  [ "$output" = '{"status": "ok"}' ]
}

@test "sse: corte de un stream chunked (como el de Anthropic) también se señala" {
  start_fake primary ssechunkcut; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  post /v1/messages -N >/dev/null || true
  grep -q 'message_start' "$WORK/resp"
  grep -q '^event: error' "$WORK/resp"
  [ "$(count ollama)" = 0 ]
}

# ── Proxy: arranque, bind y exit codes ───────────────────────────────────────

@test "bind: listen_host 0.0.0.0 se rechaza con exit 2 sin abrir el puerto" {
  write_config 1 2 5 0.0.0.0
  run timeout 5 python3 "$REPO_ROOT/$PROXY" --config "$WORK/config.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"loopback"* ]]
}

@test "bind: --host 0.0.0.0 por CLI también se rechaza (boundary: override de la config)" {
  write_config 1 2
  run timeout 5 python3 "$REPO_ROOT/$PROXY" --config "$WORK/config.json" --host 0.0.0.0
  [ "$status" -eq 2 ]
}

@test "config: JSON inválido termina con exit 2 y mensaje, sin traceback" {
  printf '{ no es json' > "$WORK/config.json"
  run timeout 5 python3 "$REPO_ROOT/$PROXY" --config "$WORK/config.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"config"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "config: SAVIA_DUAL_CONFIG (lo que fija la unidad systemd) se respeta" {
  start_fake primary ok; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"
  HOME="$WORK" SAVIA_DUAL_CONFIG="$WORK/config.json" timeout 20 python3 "$REPO_ROOT/$PROXY" 2> "$WORK/proxy.log" &
  PIDS+=("$!")
  local i; for i in $(seq 1 100); do grep -q 'listening' "$WORK/proxy.log" && break; sleep 0.1; done
  grep -q "primary=http://127.0.0.1:$PRIMARY_PORT" "$WORK/proxy.log"
}

@test "invalid: Content-Length no numérico devuelve 400 sin contactar upstreams" {
  start_fake primary ok; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run python3 - "$PROXY_PORT" <<'PY'
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
s.sendall(b"POST /v1/messages HTTP/1.0\r\nContent-Length: abc\r\n\r\n")
print(s.recv(64).split(b"\r\n")[0].decode())
PY
  [[ "$output" == *" 400 "* ]]
  [ "$(count primary)" = 0 ]
}

@test "empty: cuerpo vacío en /v1/messages se reenvía sin romper el proxy" {
  start_fake primary ok; start_fake ollama ok
  write_config "$PRIMARY_PORT" "$OLLAMA_PORT"; start_proxy
  run curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PROXY_PORT/v1/messages"
  [ "$output" = "200" ]
}

# ── Instalador: HOME temporal y stubs; nunca la configuración real ──────────

setup_installer() {
  export HOME="$WORK/home"; mkdir -p "$HOME" "$WORK/bin"
  printf '# rc original\n' > "$HOME/.bashrc"
  cat > "$WORK/bin/ollama" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) echo "ollama version 0.20.0" ;;
  list) printf 'NAME ID SIZE\n'; [[ -n "${FAKE_MODELS:-}" ]] && printf '%s x 1GB\n' $FAKE_MODELS ;;
  pull) echo "pull $2" >> "$CALLS" ;;
esac
SH
  printf '#!/usr/bin/env bash\necho "sudo $*" >> "$CALLS"; exit 1\n' > "$WORK/bin/sudo"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$CALLS"; exit 0\n' > "$WORK/bin/systemctl"
  printf '#!/usr/bin/env bash\ncase "$*" in *api/tags*) exit 0 ;; esac\nexit 7\n' > "$WORK/bin/curl"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/nvidia-smi"
  chmod +x "$WORK/bin/"*
  export CALLS="$WORK/calls" PATH="$WORK/bin:$PATH" SAVIA_OPTIN_AUDIT_LOG="$WORK/optin.log"
  unset SAVIA_TESTING SAVIA_DUAL_FAILOVER_ENABLED SAVIA_API_UPSTREAM
  : > "$CALLS"
}

@test "setup: declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$REPO_ROOT/$SCRIPT"
}

@test "setup: sin doble opt-in escribe solo ~/.savia/dual y no toca rc, sudo ni systemd" {
  setup_installer
  run bash "$REPO_ROOT/$SCRIPT" --no-launch
  [ "$status" -eq 0 ]
  [ -f "$HOME/.savia/dual/config.json" ]
  [ -f "$HOME/.savia/dual/env" ]
  [ "$(cat "$HOME/.bashrc")" = "# rc original" ]
  refute_grep '^sudo' "$CALLS"
  [[ "$output" == *"--confirm-autonomous"* ]]
  [[ "$output" != *"installed and running"* ]]
}

@test "setup: con solo la variable (sin --confirm-autonomous) sigue bloqueando lo global" {
  setup_installer
  SAVIA_DUAL_FAILOVER_ENABLED=true run bash "$REPO_ROOT/$SCRIPT" --no-launch
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.bashrc")" = "# rc original" ]
  refute_grep '^sudo' "$CALLS"
}

@test "setup: con doble opt-in añade el bloque al rc una sola vez (idempotente)" {
  setup_installer
  SAVIA_DUAL_FAILOVER_ENABLED=true run bash "$REPO_ROOT/$SCRIPT" --no-launch --confirm-autonomous
  SAVIA_DUAL_FAILOVER_ENABLED=true run bash "$REPO_ROOT/$SCRIPT" --no-launch --confirm-autonomous
  [ "$(grep -c '>>> savia-dual >>>' "$HOME/.bashrc")" = 1 ]
}

@test "setup: --dry-run no escribe nada en HOME" {
  setup_installer
  run bash "$REPO_ROOT/$SCRIPT" --dry-run --no-launch
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.savia" ]
  [ "$(cat "$HOME/.bashrc")" = "# rc original" ]
}

@test "setup: argumento desconocido falla con exit 2 sin escribir nada" {
  setup_installer
  run bash "$REPO_ROOT/$SCRIPT" --no-lanch
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.savia" ]
}

@test "setup: variante gemma4 no listada instalada → local_model nunca queda vacío" {
  setup_installer
  FAKE_MODELS="gemma4:12b" run bash "$REPO_ROOT/$SCRIPT" --no-launch
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["local_model"])' "$HOME/.savia/dual/config.json"
  [ "$output" = "gemma4:12b" ]
  refute_grep '^pull' "$CALLS"
}

@test "setup: config existente no se sobrescribe sin --force (boundary de idempotencia)" {
  setup_installer
  mkdir -p "$HOME/.savia/dual"; printf '{"mine": true}\n' > "$HOME/.savia/dual/config.json"
  run bash "$REPO_ROOT/$SCRIPT" --no-launch
  [ "$(cat "$HOME/.savia/dual/config.json")" = '{"mine": true}' ]
}
