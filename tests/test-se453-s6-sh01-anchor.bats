#!/usr/bin/env bats
# SE-453 S6 — la lista «parece código» (SH01) de data-sovereignty-gate.sh se ancla a la entidad entera.
# Antes: un grep -viE sin ancla final rebajaba a aviso cualquier entidad que empezara, terminara o
# contuviera una palabra de código (docs/evidence/SE-453-S4-evidence-grading.md). Entidades sintéticas.
# Daemon falso: /health 200 y /gate devuelve el JSON de $GATE_JSON.

HOOK=".claude/hooks/data-sovereignty-gate.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
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

# gate <ruta> <tipo> <texto> [<tipo> <texto>...] → ejecuta el hook con esas entidades
gate() {
  local path="$1"; shift
  local ents="[]"
  while (( $# >= 2 )); do
    ents=$(jq -c --arg t "$1" --arg x "$2" '. + [{type:$t,text:$x,score:0.9,action:"BLOCK",layer:2}]' <<<"$ents")
    shift 2
  done
  jq -nc --argjson e "$ents" '{verdict:"BLOCK",entities:$e}' > "$GATE_JSON"
  run bash "$HOOK" < <(jq -nc --arg p "$path" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')
}

# IP privada montada en tiempo de ejecución: el propio gate bloquea escribirla literal.
priv_ip() { printf '%s.%s.%s.%s' 10 20 30 40; }

# ── Casos de S4: antes se rebajaban, ahora deben bloquear ──────────────────
@test "S4: Microsoft + cliente bloquea (antes ^Microsoft)" {
  gate scripts/demo.py ORG "Microsoft Contoso confidential client"; [ "$status" -eq 2 ]
}
@test "S4: IP interna con :8080 bloquea (antes 8080\$)" {
  gate scripts/demo.py LOCATION "$(priv_ip):8080"; [ "$status" -eq 2 ]
}
@test "S4: host interno con :8443 bloquea" {
  gate scripts/demo.py LOCATION "db-prod-acme.internal:8443"; [ "$status" -eq 2 ]
}
@test "S4: clave=valor con secreto bloquea (antes =[0-9]+\$)" {
  gate scripts/demo.py PERSON "ACME_pwd=12345678"; [ "$status" -eq 2 ]
}
@test "S4: API-prod-key-ClientX bloquea (antes ^API)" {
  gate scripts/demo.py ORG "API-prod-key-ClientX"; [ "$status" -eq 2 ]
}
@test "S4: github.com/org/repo privado bloquea (antes ^github)" {
  gate scripts/demo.py ORG "github.com/acme-corp/secret-roadmap"; [ "$status" -eq 2 ]
}
@test "S4: from + nombre y dos apellidos bloquea (antes ^from )" {
  gate scripts/demo.py PERSON "from Juan Perez Garcia"; [ "$status" -eq 2 ]
}
@test "contiene timeout= + nombre bloquea (antes timeout= sin ancla)" {
  gate scripts/demo.py PERSON "timeout=5 Laura Gomez"; [ "$status" -eq 2 ]
}
@test "Chrome + nombre bloquea (antes ^Chrome)" {
  gate scripts/demo.py PERSON "Chrome de Laura Gomez"; [ "$status" -eq 2 ]
}

# ── Tipo de credencial / IP / URL: nunca se rebaja ─────────────────────────
@test "tipo internal_ip con texto de código bloquea" {
  gate scripts/demo.py internal_ip "timeout=5"; [ "$status" -eq 2 ]
}
@test "tipo URL con texto de código bloquea" {
  gate scripts/demo.py URL "github"; [ "$status" -eq 2 ]
}
@test "entidad sin tipo no se rebaja (fail-closed)" {
  jq -nc '{verdict:"BLOCK",entities:[{text:"timeout=5"}]}' > "$GATE_JSON"
  run bash "$HOOK" < <(jq -nc '{tool_name:"Write",tool_input:{file_path:"scripts/demo.py",content:"x"}}')
  [ "$status" -eq 2 ]
}

# ── Caso negativo: los tokens de código legítimos siguen en aviso ──────────
@test "negativo: tokens de código legítimos se rebajan a aviso" {
  local t
  for t in "timeout=5" "retries=3" "ValueError" "urllib.parse" "Microsoft" "Microsoft.VSTS.Scheduling.Effort" \
           "System.AssignedTo" "Azure.Identity" "localhost" "HTTPError" "HTTP" "API" "SPEC-SH01" "%Y-%m-%d" \
           "H:%M" "YYYY-MM-DD HH:MM" "Chrome" "Playwright" "github" "True" "kwargs" "from os" "import json" \
           "datetime" "timedelta(" "8080" "127.0.0.1" "IterationPath" "SharePoint" ".xlsx" "tenant_url" \
           "DedupKey" "page.goto" "class Foo" "Counter(" "default=10" "debug=True"; do
    gate scripts/demo.py PERSON "$t"
    [ "$status" -eq 0 ] || { echo "no se rebajó: $t (status $status)"; return 1; }
  done
}
@test "negativo: varias entidades, todas código, se rebaja" {
  gate scripts/demo.py PERSON "timeout=5" ORG "Microsoft" MISC "ValueError"; [ "$status" -eq 0 ]
  [[ "$output" == *"SH01"* ]]
}

# ── Regresiones que ya pasaban ─────────────────────────────────────────────
@test "mezcla código + nombre real bloquea" {
  gate scripts/demo.py PERSON "timeout=5" PERSON "Laura Gomez"; [ "$status" -eq 2 ]
}
@test "destino no código no aplica SH01" {
  gate docs/nota.md PERSON "timeout=5"; [ "$status" -eq 2 ]
}
@test "nombre sin palabra de código bloquea" {
  gate scripts/demo.py PERSON "Juan Perez"; [ "$status" -eq 2 ]
}
