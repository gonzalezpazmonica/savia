#!/usr/bin/env bats
# SE-453 S6 — TDD cruzado, solo tests de contrato del override SH01.
# Ref: docs/evidence/SE-453-S4-evidence-grading.md
# Estrategia: hook real por stdin + daemon HTTP falso en puerto efímero.
# C1/C3 deben ser RED antes del arreglo; C2/C4 son controles ya GREEN.
# Todos los nombres, direcciones y textos sensibles son fixtures sintéticos.

setup() {
  set -uo pipefail
  cd "$BATS_TEST_DIRNAME/.."
  HOOK=".claude/hooks/data-sovereignty-gate.sh"
  local dependency
  for dependency in python3 jq curl; do
    command -v "$dependency" >/dev/null
  done

  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/workspace"
  export SAVIA_WORKSPACE_DIR="$CLAUDE_PROJECT_DIR"
  export SAVIA_HOOK_PROFILE=security SAVIA_SHIELD_ENABLED=true
  # La conexión local no debe depender del proxy de la máquina que ejecuta BATS.
  export NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
  mkdir -p "$HOME/.savia" "$CLAUDE_PROJECT_DIR"
  printf '%s\n' 'synthetic-shield-token' > "$HOME/.savia/shield-token"
  RESPONSE="$BATS_TEST_TMPDIR/response.json"
  REQUESTS="$BATS_TEST_TMPDIR/requests.jsonl"
  INPUT="$BATS_TEST_TMPDIR/input.json"
  PORT_FILE="$BATS_TEST_TMPDIR/port"
  SERVER_LOG="$BATS_TEST_TMPDIR/daemon.log"

  python3 - "$RESPONSE" "$REQUESTS" "$PORT_FILE" >"$SERVER_LOG" 2>&1 3>&- <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

response_file, requests_file, port_file = map(Path, sys.argv[1:])


class ShieldFixture(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(200 if self.path == "/health" else 404, {"status": "ok"})

    def do_POST(self):
        if self.path != "/gate":
            self.reply(404, {"error": "unknown endpoint"})
            return
        if self.headers.get("X-Shield-Token") != "synthetic-shield-token":
            self.reply(401, {"error": "missing or invalid fixture token"})
            return
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with requests_file.open("a") as stream:
            stream.write(json.dumps(payload) + "\n")
        self.reply(200, json.loads(response_file.read_text()))


with HTTPServer(("127.0.0.1", 0), ShieldFixture) as server:
    port_file.write_text(str(server.server_port))
    server.serve_forever()
PY
  DAEMON_PID=$!

  # Espera acotada de disponibilidad; un fallo de arranque falla el setup,
  # nunca se confunde con el fallback o con un test omitido.
  python3 - "$PORT_FILE" "$SERVER_LOG" <<'PY'
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

port_file, log_file = map(Path, sys.argv[1:])
deadline = time.monotonic() + 5
while time.monotonic() < deadline:
    try:
        port = int(port_file.read_text())
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=0.2) as reply:
            if reply.status == 200:
                sys.exit(0)
    except (OSError, ValueError, urllib.error.URLError):
        time.sleep(0.02)
raise SystemExit("Daemon falso no disponible:\n" + log_file.read_text())
PY
  export SAVIA_SHIELD_PORT
  SAVIA_SHIELD_PORT=$(cat "$PORT_FILE")
}

teardown() {
  if [[ -n "${DAEMON_PID:-}" ]]; then
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
      kill "$DAEMON_PID"
    fi
    # SIGTERM es el cierre esperado; cualquier otro resultado falla el teardown.
    local daemon_status=0
    wait "$DAEMON_PID" || daemon_status=$?
    [ "$daemon_status" -eq 143 ]
  fi
  # BATS elimina BATS_TEST_TMPDIR, incluidos HOME, auditoría y fixtures.
}

write_entity() {
  local text="$1" entity_type="$2"
  jq -nc --arg text "$text" --arg type "$entity_type" '
    {verdict:"BLOCK",entities:[{text:$text,layer:"ner"}
      + (if $type == "missing" then {} else {type:$type} end)]}
  ' > "$RESPONSE"
}

invoke_gate() {
  local destination="${1:-scripts/demo.py}"
  jq -nc --arg path "$destination" \
    '{tool_name:"Write",tool_input:{file_path:$path,content:"x"}}' > "$INPUT"
  run bash "$HOOK" < "$INPUT"
  # Evita falsos verdes por skip, daemon caído, proxy, auth o fallback:
  # cada invocación debe llegar a /gate con el JSON completo de stdin.
  [ -s "$REQUESTS" ]
  jq -se --slurpfile expected "$INPUT" \
    'length == 1 and .[0] == $expected[0]' "$REQUESTS" >/dev/null
}

assert_blocked_entity() {
  write_entity "$1" "$2"
  invoke_gate
  [ "$status" -eq 2 ]
}

assert_code_warning() {
  write_entity "$1" ORG
  invoke_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *WARNING* ]]
}

# C1: coincidencias parciales (prefijo, sufijo o contenido) no son tokens enteros.
@test "S6-C1 bloquea Microsoft Contoso confidential client (ORG)" {
  assert_blocked_entity 'Microsoft Contoso confidential client' ORG
}

@test "S6-C1 bloquea 10.20.30.40:8080 (ORG)" {
  assert_blocked_entity '10.20.30.40:8080' ORG
}

@test "S6-C1 bloquea db-prod-acme.internal:8443 (ORG)" {
  assert_blocked_entity 'db-prod-acme.internal:8443' ORG
}

@test "S6-C1 bloquea ACME_pwd=12345678 (ORG)" {
  assert_blocked_entity 'ACME_pwd=12345678' ORG
}

@test "S6-C1 bloquea API-prod-key-ClientX (ORG)" {
  assert_blocked_entity 'API-prod-key-ClientX' ORG
}

@test "S6-C1 bloquea github.com/acme-corp/secret-roadmap (ORG)" {
  assert_blocked_entity 'github.com/acme-corp/secret-roadmap' ORG
}

@test "S6-C1 bloquea from Juan Perez Garcia (PERSON)" {
  assert_blocked_entity 'from Juan Perez Garcia' PERSON
}

@test "S6-C1 bloquea Chrome de Laura Gomez (PERSON)" {
  assert_blocked_entity 'Chrome de Laura Gomez' PERSON
}

@test "S6-C1 bloquea HTTP cliente Banco Ejemplo (ORG)" {
  assert_blocked_entity 'HTTP cliente Banco Ejemplo' ORG
}

@test "S6-C1 bloquea timeout=5 Laura Gomez (PERSON)" {
  assert_blocked_entity 'timeout=5 Laura Gomez' PERSON
}

# C2: casos negativos de regresión; código legítimo conserva el aviso.
@test "S6-C2 aviso para timeout=5" {
  assert_code_warning 'timeout=5'
}

@test "S6-C2 aviso para ValueError" {
  assert_code_warning 'ValueError'
}

@test "S6-C2 aviso para urllib.parse" {
  assert_code_warning 'urllib.parse'
}

@test "S6-C2 aviso para Microsoft.VSTS.Scheduling.Effort" {
  assert_code_warning 'Microsoft.VSTS.Scheduling.Effort'
}

@test "S6-C2 aviso para System.AssignedTo" {
  assert_code_warning 'System.AssignedTo'
}

@test "S6-C2 aviso para localhost" {
  assert_code_warning 'localhost'
}

@test "S6-C2 aviso para HTTPError" {
  assert_code_warning 'HTTPError'
}

@test "S6-C2 aviso para SPEC-SH01" {
  assert_code_warning 'SPEC-SH01'
}

@test "S6-C2 aviso para %Y-%m-%d" {
  assert_code_warning '%Y-%m-%d'
}

@test "S6-C2 aviso para YYYY-MM-DD HH:MM" {
  assert_code_warning 'YYYY-MM-DD HH:MM'
}

@test "S6-C2 aviso para Chrome" {
  assert_code_warning 'Chrome'
}

@test "S6-C2 aviso para github" {
  assert_code_warning 'github'
}

@test "S6-C2 aviso para True" {
  assert_code_warning 'True'
}

@test "S6-C2 aviso para kwargs" {
  assert_code_warning 'kwargs'
}

# C3: el tipo sensible o ausente prima aunque el texto entero parezca código.
@test "S6-C3 bloquea internal_ip con texto timeout=5" {
  assert_blocked_entity 'timeout=5' internal_ip
}

@test "S6-C3 bloquea aws_key con texto timeout=5" {
  assert_blocked_entity 'timeout=5' aws_key
}

@test "S6-C3 bloquea connection_string con texto timeout=5" {
  assert_blocked_entity 'timeout=5' connection_string
}

@test "S6-C3 bloquea private_key con texto timeout=5" {
  assert_blocked_entity 'timeout=5' private_key
}

@test "S6-C3 bloquea IP_ADDRESS con texto timeout=5" {
  assert_blocked_entity 'timeout=5' IP_ADDRESS
}

@test "S6-C3 bloquea URL con texto timeout=5" {
  assert_blocked_entity 'timeout=5' URL
}

@test "S6-C3 bloquea EMAIL_ADDRESS con texto timeout=5" {
  assert_blocked_entity 'timeout=5' EMAIL_ADDRESS
}

@test "S6-C3 bloquea CREDIT_CARD con texto timeout=5" {
  assert_blocked_entity 'timeout=5' CREDIT_CARD
}

@test "S6-C3 fail-closed si falta type aunque el texto sea timeout=5" {
  assert_blocked_entity 'timeout=5' missing
}

# C4: todas las entidades deben ser código, y el destino también debe serlo.
@test "S6-C4 bloquea mezcla de token de código y nombre sintético" {
  printf '%s\n' '{"verdict":"BLOCK","entities":[{"type":"ORG","text":"timeout=5","layer":"ner"},{"type":"PERSON","text":"Juan Perez Garcia","layer":"ner"}]}' > "$RESPONSE"
  invoke_gate
  [ "$status" -eq 2 ]
}

@test "S6-C4 bloquea mezcla también con el nombre antes del token" {
  printf '%s\n' '{"verdict":"BLOCK","entities":[{"type":"PERSON","text":"Juan Perez Garcia","layer":"ner"},{"type":"ORG","text":"timeout=5","layer":"ner"}]}' > "$RESPONSE"
  invoke_gate
  [ "$status" -eq 2 ]
}

@test "S6-C4 permite aviso si todas las entidades son tokens de código" {
  printf '%s\n' '{"verdict":"BLOCK","entities":[{"type":"ORG","text":"timeout=5","layer":"ner"},{"type":"PERSON","text":"ValueError","layer":"ner"}]}' > "$RESPONSE"
  invoke_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *WARNING* ]]
}

@test "S6-C4 bloquea timeout=5 en destino no código docs/nota.md" {
  write_entity 'timeout=5' ORG
  invoke_gate docs/nota.md
  [ "$status" -eq 2 ]
}
