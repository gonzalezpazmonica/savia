#!/usr/bin/env bats
# SE-453 S6 — tests que matan los supervivientes de la auditoría de mutación del 2026-11-27
# (S3, S4, S5, S7, S8, S14). Cada caso lleva su control: la misma forma con un dato de código
# legítimo se rebaja a aviso, para que el BLOCK se deba al contrato probado y no a otra cosa.
# Daemon falso: /health 200 y /gate devuelve el JSON de $GATE_JSON. Entidades sintéticas.

HOOK=".claude/hooks/data-sovereignty-gate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$PWD"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/ws"; mkdir -p "$CLAUDE_PROJECT_DIR/output"
  export SAVIA_HOOK_PROFILE=security
  unset SAVIA_SHIELD_ENABLED
  export GATE_JSON="$BATS_TEST_TMPDIR/gate.json"
  local portf="$BATS_TEST_TMPDIR/port"
  cat > "$BATS_TEST_TMPDIR/fake.py" <<'PY'
import http.server, os, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body):
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(body)
    def do_GET(self): self._send(b'{"status":"ok"}')
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        with open(os.environ["GATE_JSON"], "rb") as f: self._send(f.read())
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
  python3 -I "$BATS_TEST_TMPDIR/fake.py" "$portf" &
  echo $! > "$BATS_TEST_TMPDIR/pid"
  for _ in $(seq 50); do [[ -s "$portf" ]] && break; sleep 0.1; done
  export SAVIA_SHIELD_PORT="$(cat "$portf")"
}

teardown() {
  kill "$(cat "$BATS_TEST_TMPDIR/pid")" 2>/dev/null || true
}

# ents <tipo> <texto> [...] → escribe el JSON del daemon falso
ents() {
  local e="[]"
  while (( $# >= 2 )); do
    e=$(jq -c --arg t "$1" --arg x "$2" '. + [{type:$t,text:$x,score:0.9,action:"BLOCK",layer:2}]' <<<"$e")
    shift 2
  done
  jq -nc --argjson e "$e" '{verdict:"BLOCK",entities:$e}' > "$GATE_JSON"
}

# gate_with <hook> <ruta> <tipo> <texto> [...] → ejecuta ese hook con esas entidades
gate_with() {
  local hook="$1" path="$2"; shift 2
  ents "$@"
  run bash "$hook" < <(jq -nc --arg p "$path" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')
}
gate() { gate_with "$HOOK" "$@"; }

# copia mínima del hook en un árbol propio; con "sin-lib" falta scripts/lib/sh01-code-allowlist.sh
tree_copy() {
  local root="$BATS_TEST_TMPDIR/root-$1"
  mkdir -p "$root/.claude/hooks/lib" "$root/scripts/lib"
  cp "$REPO/$HOOK" "$root/.claude/hooks/"
  cp "$REPO/.claude/hooks/lib/profile-gate.sh" "$root/.claude/hooks/lib/"
  cp "$REPO/scripts/savia-env.sh" "$root/scripts/"
  cp "$REPO/scripts/lib/os-detect.sh" "$root/scripts/lib/"
  [[ "$1" == "con-lib" ]] && cp "$REPO/scripts/lib/sh01-code-allowlist.sh" "$root/scripts/lib/"
  printf '%s' "$root/$HOOK"
}

# ── S8: sin la librería no hay rebaja (fail-closed) ────────────────────────
@test "S8: sin la librería SH01, entidades de código en un .py siguen en BLOCK" {
  local h; h=$(tree_copy sin-lib)
  [ ! -e "$(dirname "$h")/../../scripts/lib/sh01-code-allowlist.sh" ]
  gate_with "$h" scripts/demo.py ORG "ValueError" PERSON "timeout=5"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOQUEADO"* ]]
  [[ "$output" != *"SH01"* ]]
}
@test "S8 control: la misma copia con la librería rebaja a aviso" {
  local h; h=$(tree_copy con-lib)
  gate_with "$h" scripts/demo.py ORG "ValueError" PERSON "timeout=5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SH01"* ]]
}

# ── S3 y S4: clave=valor con clave de secreto, una por palabra del filtro ──
# Todas casan con ${_I}=[0-9]{1,5}: solo el filtro de secreto las mantiene en BLOCK.
@test "S3/S4: clave de secreto = número corto bloquea, una por palabra del filtro" {
  local t
  for t in "pwd_x=1" "password=1234" "client_secret=7" "token=99" "api_key=12345" "auth=3" "cred_x=1"; do
    gate scripts/demo.py ORG "$t"
    [ "$status" -eq 2 ] || { echo "se rebajó: $t (status $status)"; return 1; }
  done
}
@test "S3/S4 control: clave sin secreto = número corto se rebaja" {
  gate scripts/demo.py ORG "retries=3"; [ "$status" -eq 0 ]
}

# ── S7: el tipo NER se compara entero, no como subcadena ───────────────────
@test "S7: tipo que contiene uno de nombre (ORG_SECRET, PERSON_ID) bloquea" {
  local t
  for t in ORG_SECRET PERSON_ID API_KEY_ORG; do
    gate scripts/demo.py "$t" "ValueError"
    [ "$status" -eq 2 ] || { echo "se rebajó con tipo $t (status $status)"; return 1; }
  done
}
@test "S7 control: el mismo texto con tipo ORG se rebaja" {
  gate scripts/demo.py ORG "ValueError"; [ "$status" -eq 0 ]
}

# ── S14: loopback solo con puerto, sin sufijos ─────────────────────────────
@test "S14: loopback con sufijo bloquea" {
  local t
  for t in "127.0.0.1.cliente.corp" "localhost-prod-db" "0.0.0.0/acme-interno"; do
    gate scripts/demo.py LOCATION "$t"
    [ "$status" -eq 2 ] || { echo "se rebajó: $t (status $status)"; return 1; }
  done
}
@test "S14 control: loopback con puerto se rebaja" {
  gate scripts/demo.py LOCATION "127.0.0.1:8080"; [ "$status" -eq 0 ]
}

# ── S5: una entidad con salto de línea nunca se rebaja (contrato de la cabecera) ──
@test "S5: entidad multilínea bloquea aunque cada línea parezca código" {
  gate scripts/demo.py ORG $'timeout=5\nValueError'; [ "$status" -eq 2 ]
}
