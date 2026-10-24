#!/usr/bin/env bats
# BATS tests for scripts/model-gateway.py (SE-342 S4 / Labs L20)
# Ref: SE-342 S4, hypothesis l20-model-gateway.md, CRIT-001

SCRIPT="scripts/model-gateway.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP_GW_LOG="$(mktemp -t gw.XXXXXX)"
  rm -f "$TMP_GW_LOG"
  export SAVIA_GW_LOG="$TMP_GW_LOG"
}

teardown() {
  [[ -n "$TMP_GW_LOG" && -f "$TMP_GW_LOG" ]] && rm -f "$TMP_GW_LOG"
  cd /
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "passes py_compile" {
  run python3 -m py_compile "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "--version prints semver" {
  run python3 "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ── Redacción de payloads N3+ (núcleo determinista) ────────────────────

@test "redact hashes configured keys (text/content), keeps other fields" {
  run python3 - <<'PY'
import importlib.util, os
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.REDACT_KEYS = {"text", "content", "password"}
r = gw._redact({"text": "secreto N3", "content": "otro", "model": "llama", "n": 2})
assert r["model"] == "llama" and r["n"] == 2
assert r["text"].startswith("sha256:") and "secreto" not in r["text"]
assert r["content"].startswith("sha256:")
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "redact is deterministic (same input -> same hash)" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.REDACT_KEYS = {"content"}
a = gw._redact({"content": "x"})["content"]
b = gw._redact({"content": "x"})["content"]
assert a == b, "hash must be stable"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "redact recurses into nested dicts" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.REDACT_KEYS = {"content"}
r = gw._redact({"messages": [{"role": "user", "content": "privado"}]})
inner = r["messages"][0]["content"]
assert inner.startswith("sha256:") and "privado" not in inner
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "redact hashes 'input' key (embeddings field, default key)" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
# default keys include input/prompt
assert "input" in gw.REDACT_KEYS and "prompt" in gw.REDACT_KEYS
r = gw._redact({"model": "nomic", "input": "texto confidencial N3"})
assert r["input"].startswith("sha256:") and "confidencial" not in r["input"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "redact hashes string items inside sensitive lists" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.REDACT_KEYS = {"input"}
r = gw._redact({"input": ["secreto1", "secreto2"]})
assert r["input"][0].startswith("sha256:") and r["input"][0] != "secreto1"
assert r["input"][1].startswith("sha256:")
# non-sensitive lists stay intact
gw.REDACT_KEYS = {"input"}
r2 = gw._redact({"metadata": ["public", "x"]})
assert r2["metadata"] == ["public", "x"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

# ── Rate limiting ──────────────────────────────────────────────────────

@test "allowed(): first N calls pass, then blocked" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.RPM = 3
gw._hits = {}
assert gw.allowed("a") and gw.allowed("a") and gw.allowed("a")
assert not gw.allowed("a")  # 4th hit exceeds 3 rpm
assert gw.allowed("b")      # different caller unaffected
print("ok")
PY
  [ "$status" -eq 0 ]
}

# ── Health (no runtime -> reports down, still 200) ─────────────────────

@test "GET /health returns json even with no local runtimes" {
  run python3 - <<'PY'
import importlib.util, threading
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.OLLAMA = "http://127.0.0.1:1"   # nothing listening
gw.EMBED = "http://127.0.0.1:1"
h = gw._reachable(gw.OLLAMA)
assert h is False
print("ok", h)
PY
  [ "$status" -eq 0 ]
}
# ── Comportamiento: gateway real contra un upstream falso en localhost ────

# Prelude: carga el módulo, levanta un upstream falso (registra lo recibido) y
# el gateway en puertos efímeros. gw_run ejecuta el cuerpo del test tras él.
gw_run() {
  local prelude="$BATS_TEST_TMPDIR/prelude.py"
  cat > "$prelude" <<'PY'
import importlib.util, json, threading, urllib.request, urllib.error, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
received = []
class Up(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        received.append((self.path, self.rfile.read(n)))
        code = 418 if "/teapot" in self.path else 200
        body = json.dumps({"echo": self.path}).encode()
        self.send_response(code); self.send_header("Content-Type", "application/x-test")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
def serve(handler):
    s = HTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s
up = serve(Up)
upurl = "http://127.0.0.1:%d" % up.server_address[1]
gw.OLLAMA = upurl; gw.EMBED = upurl
gwsrv = serve(gw.Handler)
base = "http://127.0.0.1:%d" % gwsrv.server_address[1]
def call(path, data=None, headers=None, method="POST"):
    body = data if isinstance(data, (bytes, type(None))) else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers
def logs(n=None):
    # el gateway escribe el log DESPUÉS de responder: esperar a que aparezca
    import time
    for _ in range(100):
        ls = [json.loads(l) for l in open(gw.LOG_PATH)] if os.path.exists(gw.LOG_PATH) else []
        if n is None or len(ls) >= n: return ls
        time.sleep(0.05)
    return ls
PY
  cat > "$BATS_TEST_TMPDIR/body.py"
  cat "$prelude" "$BATS_TEST_TMPDIR/body.py" > "$BATS_TEST_TMPDIR/all.py"
  run python3 "$BATS_TEST_TMPDIR/all.py"
}

@test "chat: POST se proxea a /v1/chat/completions del upstream y la respuesta vuelve intacta" {
  gw_run <<'PY'
st, body, h = call("/v1/chat/completions", {"model": "m", "messages": []}, {"X-Caller": "agente-a"})
assert st == 200, st
assert json.loads(body) == {"echo": "/v1/chat/completions"}, body
assert h["Content-Type"] == "application/x-test"
assert len(received) == 1 and json.loads(received[0][1])["model"] == "m"
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "chat: si OLLAMA ya apunta a /api/chat se usa ese destino" {
  gw_run <<'PY'
gw.OLLAMA = upurl + "/api/chat"
st, body, _ = call("/v1/chat/completions", {"model": "m"}, {"X-Caller": "a"})
assert json.loads(body) == {"echo": "/api/chat/api/chat"}, body
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "embeddings: POST se proxea a /embed del servidor de embeddings" {
  gw_run <<'PY'
st, body, _ = call("/v1/embeddings", {"input": "hola"}, {"X-Caller": "a"})
assert st == 200 and json.loads(body) == {"echo": "/embed"}, (st, body)
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "ruta desconocida: 404 en POST y GET sin llegar al upstream" {
  gw_run <<'PY'
st, body, _ = call("/v1/otra", {"a": 1})
assert st == 404 and json.loads(body)["error"] == "not found"
st, body, _ = call("/nada", method="GET")
assert st == 404
assert received == []
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "log de uso: guarda kind, caller, status y payload con el texto redactado, nunca en claro" {
  gw_run <<'PY'
call("/v1/chat/completions", {"model": "llama", "messages": [{"role": "user", "content": "dato-confidencial-N3"}]}, {"X-Caller": "agente-a"})
call("/v1/embeddings", {"input": "otro-secreto"}, {"X-Caller": "agente-b"})
ls = logs(2)
assert [l["kind"] for l in ls] == ["chat", "embed"], ls
assert ls[0]["caller"] == "agente-a" and ls[0]["status"] == 200
assert ls[0]["payload"]["model"] == "llama"
assert ls[0]["payload"]["messages"][0]["content"].startswith("sha256:")
assert ls[0]["payload"]["messages"][0]["role"] == "user"
assert ls[1]["payload"]["input"].startswith("sha256:")
raw = open(gw.LOG_PATH).read()
assert "dato-confidencial-N3" not in raw and "otro-secreto" not in raw
assert isinstance(ls[0]["ts"], float) and isinstance(ls[0]["ms"], int)
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "caller: X-Caller gana a X-Client-Id; sin cabeceras es 'unknown'" {
  gw_run <<'PY'
call("/v1/embeddings", {"input": "x"}, {"X-Caller": "uno", "X-Client-Id": "dos"})
call("/v1/embeddings", {"input": "x"}, {"X-Client-Id": "dos"})
call("/v1/embeddings", {"input": "x"})
assert [l["caller"] for l in logs(3)] == ["uno", "dos", "unknown"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "rate limit: tras RPM llamadas el caller recibe 429 y el upstream no se entera" {
  gw_run <<'PY'
gw.RPM = 2; gw._hits = {}
codes = [call("/v1/embeddings", {"input": "x"}, {"X-Caller": "ruidoso"})[0] for _ in range(4)]
assert codes == [200, 200, 429, 429], codes
assert len(received) == 2
st, body, _ = call("/v1/embeddings", {"input": "x"}, {"X-Caller": "tranquilo"})
assert st == 200
assert json.loads(call("/v1/embeddings", {"input": "x"}, {"X-Caller": "ruidoso"})[1])["error"] == "rate limit exceeded"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "rate limit: la ventana se reinicia pasados 60 s, no antes" {
  run python3 - <<'PY'
import importlib.util, time
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.RPM = 1
now = time.time()
gw._hits = {"a": (now - 59, 1), "b": (now - 61, 5)}
assert gw.allowed("a") is False   # dentro de la ventana, ya consumió
assert gw.allowed("b") is True    # ventana vencida: contador a cero
assert gw._hits["b"][1] == 1
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "JSON inválido: 400 sin proxear ni registrar" {
  gw_run <<'PY'
st, body, _ = call("/v1/chat/completions", b"{no json", {"X-Caller": "a"})
assert st == 400 and json.loads(body)["error"] == "invalid json"
assert received == [] and logs() == []
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "cuerpo vacío se proxea con payload vacío" {
  gw_run <<'PY'
st, _, _ = call("/v1/embeddings", None, {"X-Caller": "a"})
assert st == 200
assert logs(1)[0]["payload"] == {}
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "errores del upstream: el código HTTP se propaga y se registra" {
  gw_run <<'PY'
gw.EMBED = upurl + "/teapot"
st, body, _ = call("/v1/embeddings", {"input": "x"}, {"X-Caller": "a"})
assert st == 418, st
assert logs(1)[0]["status"] == 418
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "upstream caído: 502 con error en JSON" {
  gw_run <<'PY'
gw.EMBED = "http://127.0.0.1:1"
st, body, _ = call("/v1/embeddings", {"input": "x"}, {"X-Caller": "a"})
assert st == 502 and "error" in json.loads(body)
assert logs(1)[0]["status"] == 502
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "log ilegible no rompe la respuesta (OSError se traga)" {
  gw_run <<'PY'
gw.LOG_PATH = "/proc/no-se-puede/log.jsonl"
st, _, _ = call("/v1/embeddings", {"input": "x"}, {"X-Caller": "a"})
assert st == 200
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "GET /health: gateway ok, uptime entero y alcanzabilidad real de cada runtime" {
  gw_run <<'PY'
class Ok(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
ok = serve(Ok)
gw.OLLAMA = "http://127.0.0.1:%d" % ok.server_address[1]
gw.EMBED = "http://127.0.0.1:1"
st, body, _ = call("/health", method="GET")
h = json.loads(body)
assert st == 200 and h["gateway"] == "ok"
assert isinstance(h["uptime_s"], int) and h["uptime_s"] >= 0
assert h["ollama"] is True and h["embed"] is False, h
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "_reachable: 500 del servidor cuenta como caído; /health se añade solo a URLs de embed" {
  run python3 - <<'PY'
import importlib.util, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
paths = []
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        paths.append(self.path)
        code = 500 if self.path == "/caido" else 200
        self.send_response(code); self.send_header("Content-Length", "0"); self.end_headers()
s = HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=s.serve_forever, daemon=True).start()
u = "http://127.0.0.1:%d" % s.server_address[1]
assert gw._reachable(u + "/caido") is False
assert gw._reachable(u) is True
assert gw._reachable(u + "/embed") is True
assert paths[-1] == "/embed/health", paths
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "redact: no muta el original, respeta no-strings y claves no sensibles con strings" {
  run python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("gw", "scripts/model-gateway.py")
gw = importlib.util.module_from_spec(spec); spec.loader.exec_module(gw)
gw.REDACT_KEYS = {"content"}
orig = {"content": 42, "model": "m", "items": [1, "texto", {"content": "x"}], "n": None}
r = gw._redact(orig)
assert r["content"] == 42 and r["n"] is None            # no-string sensible: intacto
assert r["items"][1] == "texto"                          # lista no sensible: strings intactos
assert r["items"][2]["content"].startswith("sha256:")    # dict en lista: se recorre
assert orig["items"][2]["content"] == "x"                # original sin mutar
h = gw._redact({"content": "abc"})["content"]
assert len(h) == len("sha256:") + 16
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "--check refleja el entorno: puerto, rpm, nº de claves y destino; clave por defecto incluye password" {
  SAVIA_GW_PORT=9191 SAVIA_GW_RATELIMIT=7 SAVIA_GW_OLLAMA=http://x:1 SAVIA_GW_REDACT_KEYS="a,b" \
    run python3 "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$output" = "config ok: port=9191 ratelimit=7 rpm redact_keys=2 ollama=http://x:1" ]
  run python3 "$SCRIPT" --check
  [[ "$output" == *"port=8787 ratelimit=30 rpm redact_keys=7 "* ]]
}

@test "arranque: sin flags escucha en 127.0.0.1 y responde /health; nunca en 0.0.0.0" {
  local port=18787
  SAVIA_GW_PORT=$port python3 "$SCRIPT" > "$BATS_TEST_TMPDIR/gw.out" 2>&1 &
  local pid=$!
  local ok=0
  for _ in $(seq 1 50); do
    if curl -s "http://127.0.0.1:$port/health" > "$BATS_TEST_TMPDIR/h.json" 2>/dev/null; then ok=1; break; fi
    sleep 0.1
  done
  local listen
  listen="$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep ":$port\$" || true)"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  [ "$ok" -eq 1 ]
  [ "$(jq -r .gateway "$BATS_TEST_TMPDIR/h.json")" = "ok" ]
  [[ "$(cat "$BATS_TEST_TMPDIR/gw.out")" == "model-gateway listening on :$port"* ]]
  [ "$listen" = "127.0.0.1:$port" ]
}

@test "log: caracteres no ASCII se guardan tal cual (ensure_ascii off), una entrada JSON por línea" {
  gw_run <<'PY'
call("/v1/embeddings", {"model": "ñandú-ü"}, {"X-Caller": "agénte"})
logs(1)
raw = open(gw.LOG_PATH, encoding="utf-8").read()
assert "agénte" in raw and "ñandú-ü" in raw, raw
assert raw.count("\n") == 1
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "SIGINT detiene el servidor con exit 0 (KeyboardInterrupt capturado)" {
  # Popen restaura SIGINT por defecto: un hijo en segundo plano de bash lo hereda ignorado
  run env SAVIA_GW_PORT=18788 python3 - "$SCRIPT" <<'PY'
import signal, subprocess, sys, time, urllib.request
p = subprocess.Popen([sys.executable, sys.argv[1]], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
for _ in range(100):
    try:
        urllib.request.urlopen("http://127.0.0.1:18788/health", timeout=1); break
    except Exception:
        time.sleep(0.1)
p.send_signal(signal.SIGINT)
out, err = p.communicate(timeout=10)
assert p.returncode == 0, (p.returncode, err)
assert b"Traceback" not in err, err
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}
