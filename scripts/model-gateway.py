#!/usr/bin/env python3
"""model-gateway.py — Local agent model gateway (SE-342 S4 / Labs L20).

Single local entry point for agents to reach local runtimes (Ollama/LocalAI
and the embedding-server) with:
  - usage logging (JSONL): model, caller, tokens, latency
  - payload redaction: fields marked N3+ are hashed, never logged in clear
  - per-caller rate limiting (local token bucket)

Zero data egress: every call is dispatched to a localhost runtime. CRIT-001.
This is the POC for SE-342 S4 -- usage/redaction/limits, no cloud, no keys.

Endpoints (OpenAI-compatible subset):
  POST /v1/chat/completions   -> proxied to OLLAMA (localhost:11434)
  POST /v1/embeddings         -> proxied to EMBED (localhost:7331)
  GET  /health                -> runtime reachability

Env:
  SAVIA_GW_PORT       (default 8787)
  SAVIA_GW_OLLAMA     (default http://localhost:11434)
  SAVIA_GW_EMBED      (default http://localhost:7331)
  SAVIA_GW_LOG        (default output/agent-runs/gateway-usage.jsonl)
  SAVIA_GW_RATELIMIT  (default 30 rpm per caller)
  SAVIA_GW_REDACT_KEYS(default "text,content,password,secret,authorization")
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Lock

PORT = int(os.environ.get("SAVIA_GW_PORT", "8787"))
OLLAMA = os.environ.get("SAVIA_GW_OLLAMA", "http://localhost:11434")
EMBED = os.environ.get("SAVIA_GW_EMBED", "http://localhost:7331")
LOG_PATH = os.environ.get("SAVIA_GW_LOG", "output/agent-runs/gateway-usage.jsonl")
RPM = int(os.environ.get("SAVIA_GW_RATELIMIT", "30"))
REDACT_KEYS = set(
    os.environ.get("SAVIA_GW_REDACT_KEYS", "text,content,input,prompt,password,secret,authorization")
    .replace(",", " ")
    .split()
)

_start = time.time()
_lock = Lock()
_hits = {}  # caller -> ((window_start), count)


def _redact(payload: dict) -> dict:
    """Deep-copy payload replacing every REDACT_KEYS value with an sha256 hash.

    Hash is stable for dedup/audit but never reveals the plaintext (N3+).
    Both dict values and string items inside lists are hashed."""

    def _h(s: str) -> str:
        return "sha256:" + hashlib.sha256(s.encode("utf-8", "ignore")).hexdigest()[:16]

    out = {}
    for k, v in payload.items():
        sensitive = k in REDACT_KEYS
        if sensitive and isinstance(v, str):
            out[k] = _h(v)
        elif isinstance(v, dict):
            out[k] = _redact(v)
        elif isinstance(v, list):
            out[k] = [
                _redact(i) if isinstance(i, dict)
                else (_h(i) if sensitive and isinstance(i, str) else i)
                for i in v
            ]
        else:
            out[k] = v
    return out


def _log(entry: dict) -> None:
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass  # never fail the gateway on log errors


def _proxy(method: str, url: str, body: bytes, timeout: int = 120) -> tuple[int, bytes, str]:
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(), resp.headers.get("Content-Type", "application/json")
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get("Content-Type", "application/json")
    except Exception as e:  # noqa: BLE001
        return 502, json.dumps({"error": str(e)}).encode(), "application/json"


def allowed(caller: str) -> bool:
    now = time.time()
    with _lock:
        w, c = _hits.get(caller, (0, 0))
        if now - w >= 60:
            w, c = now, 0
        c += 1
        _hits[caller] = (w, c)
        return c <= RPM


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # silence default stderr noise (banner footer)
        pass

    def _caller(self, headers) -> str:
        return headers.get("X-Caller", headers.get("X-Client-Id", "unknown"))

    def _handle(self, body: bytes, target: str, kind: str):
        caller = self._caller(self.headers)
        if not allowed(caller):
            self._send(429, b'{"error":"rate limit exceeded"}')
            return
        payload = {}
        if body:
            try:
                payload = json.loads(body)
            except ValueError:
                self._send(400, b'{"error":"invalid json"}')
                return
        t0 = time.time()
        status, resp, ctype = _proxy("POST", target, body)
        dt = round(time.time() - t0, 3)
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)
        # Usage log: redacted payload (N3+ never in clear).
        entry = {
            "ts": time.time(), "kind": kind, "caller": caller,
            "status": status, "ms": int(dt * 1000),
            "payload": _redact(payload)
        }
        _log(entry)

    def _send(self, code: int, payload: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else b""
        if self.path == "/v1/chat/completions":
            self._handle(body, OLLAMA + "/api/chat" if "/api/chat" in OLLAMA else OLLAMA + "/v1/chat/completions", "chat")
        elif self.path == "/v1/embeddings":
            self._handle(body, EMBED + "/embed", "embed")
        else:
            self._send(404, b'{"error":"not found"}')

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            h = {"gateway": "ok", "uptime_s": int(time.time() - _start),
                 "ollama": _reachable(OLLAMA), "embed": _reachable(EMBED)}
            body = json.dumps(h).encode()
            self._send(200, body)
        else:
            self._send(404, b'{"error":"not found"}')


def _reachable(url: str) -> bool:
    try:
        with urllib.request.urlopen(url + "/health" if "embed" in url else url, timeout=3) as r:
            return r.status < 500
    except Exception:  # noqa: BLE001
        return False


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if "--version" in argv:
        print("model-gateway.py 0.1.0 (SE-342 S4 / L20)")
        return 0
    if "--check" in argv:
        print("config ok: port=%d ratelimit=%d rpm redact_keys=%d ollama=%s" % (PORT, RPM, len(REDACT_KEYS), OLLAMA))
        return 0
    print(f"model-gateway listening on :{PORT} (ollama={OLLAMA} embed={EMBED} log={LOG_PATH})", flush=True)
    try:
        HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())