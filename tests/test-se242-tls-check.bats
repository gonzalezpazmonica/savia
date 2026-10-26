#!/usr/bin/env bats
# SE-242 — TLS Security Check tests
# Tests: tls-security-check.sh, web-headers-check.sh, SKILL.md, policy doc

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export TLS_SCRIPT="$REPO_ROOT/scripts/tls-security-check.sh"
  export HEADERS_SCRIPT="$REPO_ROOT/scripts/web-headers-check.sh"
  export SKILL_FILE="$REPO_ROOT/.opencode/skills/tls-security-checker/SKILL.md"
  export POLICY_FILE="$REPO_ROOT/docs/rules/domain/web-security-headers-policy.md"
}

# Test 1: tls-security-check.sh existe y pasa bash -n
@test "tls-security-check.sh existe y pasa bash -n" {
  [[ -f "$TLS_SCRIPT" ]]
  run bash -n "$TLS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 2: web-headers-check.sh existe y pasa bash -n
@test "web-headers-check.sh existe y pasa bash -n" {
  [[ -f "$HEADERS_SCRIPT" ]]
  run bash -n "$HEADERS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 3: tls-security-checker/SKILL.md existe y tiene ≤150 líneas
@test "tls-security-checker/SKILL.md existe y tiene 150 lineas o menos" {
  [[ -f "$SKILL_FILE" ]]
  LINE_COUNT=$(wc -l < "$SKILL_FILE")
  [[ "$LINE_COUNT" -le 150 ]]
}

# Test 4: web-security-headers-policy.md existe y tiene ≤150 líneas
@test "web-security-headers-policy.md existe y tiene 150 lineas o menos" {
  [[ -f "$POLICY_FILE" ]]
  LINE_COUNT=$(wc -l < "$POLICY_FILE")
  [[ "$LINE_COUNT" -le 150 ]]
}

# Test 5: Con testssl.sh no disponible → muestra Docker fallback
@test "tls-security-check.sh muestra Docker fallback cuando testssl no instalado" {
  # PATH sin testssl pero con bash, mkdir, date, etc.
  # Usar directorio temporal vacío como PATH adicional al principio
  FAKE_BIN=$(mktemp -d)
  trap 'rm -rf "$FAKE_BIN"' RETURN
  # El script detecta que testssl.sh no está y debe mencionar docker
  run env PATH="$FAKE_BIN:$PATH" bash "$TLS_SCRIPT" --host example.com
  # Debe mencionar Docker fallback o drwetter
  [[ "$output" == *"docker"* ]] || [[ "$output" == *"Docker"* ]] || [[ "$output" == *"drwetter"* ]]
}

# Test 6: web-headers-check.sh solo usa curl (no requiere testssl)
@test "web-headers-check.sh no tiene referencias a testssl ni MobSF" {
  run grep -i "testssl\|mobsf\|nikto" "$HEADERS_SCRIPT"
  # No debe mencionar testssl ni herramientas externas no-curl
  [[ "$status" -ne 0 ]]
}

# Test 7: web-headers-check.sh acepta --url
@test "web-headers-check.sh acepta argumento --url" {
  run grep "\-\-url" "$HEADERS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 8: tls-security-check.sh acepta --host
@test "tls-security-check.sh acepta argumento --host" {
  run grep "\-\-host" "$TLS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 9: tls-security-check.sh acepta --port
@test "tls-security-check.sh acepta argumento --port" {
  run grep "\-\-port" "$TLS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 10: El report va a output/security/
@test "tls-security-check.sh escribe report en output/security/" {
  run grep "output/security" "$TLS_SCRIPT"
  [[ "$status" -eq 0 ]]
  run grep "output/security" "$HEADERS_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 11: web-security-headers-policy.md menciona Content-Security-Policy
@test "web-security-headers-policy.md menciona Content-Security-Policy" {
  run grep -i "Content-Security-Policy\|CSP" "$POLICY_FILE"
  [[ "$status" -eq 0 ]]
}

# Test 12: web-security-headers-policy.md menciona HSTS
@test "web-security-headers-policy.md menciona HSTS" {
  run grep -i "HSTS\|Strict-Transport-Security" "$POLICY_FILE"
  [[ "$status" -eq 0 ]]
}


# ═══════════════════════════════════════════════════════════════════════════
# Comportamiento: scripts copiados a un árbol temporal (su output/ es propio),
# testssl.sh / wafw00f simulados en el PATH y un servidor HTTP local real.
# ═══════════════════════════════════════════════════════════════════════════

mk_tree242() {
  T242="$(mktemp -d)"
  mkdir -p "$T242/scripts" "$T242/bin"
  cp "$TLS_SCRIPT" "$HEADERS_SCRIPT" "$T242/scripts/"
  OUT="$T242/output/security"
  # PATH mínimo sin testssl ni wafw00f
  for b in bash python3 date mkdir cat grep sed head tr echo curl dirname env rm; do
    p="$(command -v $b)" && ln -sf "$p" "$T242/bin/$b"
  done
  BASEPATH="$T242/bin"
}

# testssl.sh falso: vuelca $FAKE_TESTSSL_JSON en el fichero de --jsonfile y registra argumentos.
# Como el real, se niega a sobrescribir un --jsonfile existente (sin --overwrite).
fake_testssl() {
  cat > "$T242/bin/testssl.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--jsonfile" ]] && out="$2"
  shift
done
[[ -e "$out" ]] && { echo "Fatal error: $out exists" >&2; exit 251; }
[[ -n "${FAKE_TESTSSL_JSON:-}" ]] && printf '%s' "$FAKE_TESTSSL_JSON" > "$out"
exit "${FAKE_TESTSSL_EXIT:-0}"
EOS
  chmod +x "$T242/bin/testssl.sh"
  export FAKE_ARGS="$T242/args.txt"
}

tls() { run env PATH="$BASEPATH" FAKE_ARGS="${FAKE_ARGS:-/dev/null}" "$@"; }

jget() { python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print(($2))" "$1"; }

@test "SE242-B01: tls check without --host prints usage and exits 1" {
  mk_tree242
  tls bash "$T242/scripts/tls-security-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "SE242-B02: tls check rejects unknown arguments" {
  mk_tree242
  tls bash "$T242/scripts/tls-security-check.sh" --bogus x
  [ "$status" -eq 1 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
}

@test "SE242-B03: tls check rejects hosts that would break the JSON report" {
  mk_tree242
  tls bash "$T242/scripts/tls-security-check.sh" --host 'a"b'
  [ "$status" -eq 1 ]
  [[ "$output" == *"host inválido"* ]]
  [ ! -d "$OUT" ]
}

@test "SE242-B04: tls check rejects non-numeric and out-of-range ports" {
  mk_tree242
  for p in abc 0 65536 "80;ls" 0443 09; do
    tls bash "$T242/scripts/tls-security-check.sh" --host example.org --port "$p"
    [ "$status" -eq 1 ]
    [[ "$output" == *"puerto inválido"* ]]
  done
  # Puerto válido: se acepta (sin testssl, fallback sin nota → exit 2, no 1)
  tls bash "$T242/scripts/tls-security-check.sh" --host example.org --port 65535
  [ "$status" -eq 2 ]
  [[ "$output" == *"DOCKER_FALLBACK"* ]]
}

@test "SE242-B05: without testssl the fallback report is UNKNOWN and exits 2" {
  mk_tree242
  tls bash "$T242/scripts/tls-security-check.sh" --host example.org --port 8443 --severity HIGH
  [ "$status" -eq 2 ]
  [[ "$output" == *"DOCKER_FALLBACK"* ]]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
  f="$(ls "$OUT"/tls-check-example.org-*.json)"
  [ "$(jget "$f" "d['grade'], d['mode'], d['findings'], d['port']")" = "('UNKNOWN', 'docker_fallback', [], 8443)" ]
  [[ "$(jget "$f" "d['message']")" == *"--severity HIGH example.org:8443"* ]]
}

@test "SE242-B06: host with a port colon is made file-safe in the report name" {
  mk_tree242
  tls bash "$T242/scripts/tls-security-check.sh" --host "a:b"
  [ "$status" -eq 2 ]
  ls "$OUT"/tls-check-a_b-*.json
}

@test "SE242-B07: testssl is called with host:port, severity and the check groups" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org --port 8443 --severity LOW
  [ "$status" -eq 0 ]
  grep -qx -- 'example.org:8443' "$FAKE_ARGS"
  grep -qx -- '--severity' "$FAKE_ARGS"
  grep -qx -- 'LOW' "$FAKE_ARGS"
  for o in --protocols --ciphers --headers --vulnerable; do grep -qx -- "$o" "$FAKE_ARGS"; done
}

@test "SE242-B08: a clean scan gets grade B with an empty findings list" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"x","severity":"INFO","finding":"all good"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE: B"* ]]
  f="$(ls "$OUT"/tls-check-example.org-*.json)"
  [ "$(jget "$f" "d['grade'], d['findings'], d['min_severity_filter']")" = "('B', [], 'MEDIUM')" ]
}

@test "SE242-B09: findings below the minimum severity are dropped, those at it are kept" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"a","severity":"LOW","finding":"minor"},{"id":"b","severity":"medium","finding":"mid","cve":"CVE-1"},{"id":"c","severity":"HIGH","finding":"big"}]' \
    tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity MEDIUM
  [ "$status" -eq 0 ]
  f="$(ls "$OUT"/tls-check-example.org-*.json)"
  [ "$(jget "$f" "[x['id'] for x in d['findings']]")" = "['b', 'c']" ]
  [ "$(jget "$f" "d['findings'][0]['severity'], d['findings'][0]['cve']")" = "('MEDIUM', 'CVE-1')" ]
}

@test "SE242-B10: grade F for SSLv3 or an expired certificate" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"SSLv3","severity":"CRITICAL","finding":"offered SSLv3"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: F"* ]]
  FAKE_TESTSSL_JSON='[{"id":"cert","severity":"HIGH","finding":"certificate expired"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: F"* ]]
}

@test "SE242-B11: grade D for TLS 1.0/1.1 and C for RC4, export or NULL ciphers" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"t","severity":"HIGH","finding":"TLSv1.0 offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: D"* ]]
  FAKE_TESTSSL_JSON='[{"id":"r","severity":"HIGH","finding":"RC4 ciphers"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: C"* ]]
}

@test "SE242-B12: the word 'description' or 'destination' alone does not lower the grade to C" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"h","severity":"MEDIUM","finding":"missing header, see description at destination"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: B"* ]]
}

@test "SE242-B13: a worse finding wins over a lighter one" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"a","severity":"HIGH","finding":"RC4"},{"id":"b","severity":"HIGH","finding":"TLSv1.1"},{"id":"c","severity":"CRITICAL","finding":"SSLv3"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: F"* ]]
}

@test "SE242-B14: testssl that writes no report is never graded (UNKNOWN, warning)" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='' FAKE_TESTSSL_EXIT=1 tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 2 ]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
  [[ "$output" == *"no produjo un informe legible"* ]]
}

@test "SE242-B15: an unreadable testssl report is never graded either" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='not json {' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 2 ]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
  f="$(ls "$OUT"/tls-check-example.org-*.json)"
  [ "$(jget "$f" "d['grade'], d['findings']")" = "('UNKNOWN', [])" ]
}

@test "SE242-B16: wafw00f result is recorded when available and null when not" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"wafw00f no disponible"* ]]
  [ "$(jget "$(ls "$OUT"/tls-check-example.org-*.json)" "d['waf']")" = "None" ]
  printf '#!/usr/bin/env bash\necho "{\\"detected\\": \\"Cloudflare\\"}"\n' > "$T242/bin/wafw00f"
  chmod +x "$T242/bin/wafw00f"
  FAKE_TESTSSL_JSON='[]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$(jget "$(ls "$OUT"/tls-check-example.org-*.json)" "d['waf']")" = "Cloudflare" ]
}

# ── web-headers-check.sh ────────────────────────────────────────────────────

# Servidor HEAD local: las cabeceras de cada ruta salen del fichero $T242/hdr<ruta con / -> _>
start_http() {
  cat > "$T242/srv.py" <<'PY'
import sys, os
from http.server import BaseHTTPRequestHandler, HTTPServer
D = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def send_response(self, code, message=None):
        self.send_response_only(code, message)  # sin cabecera Server por defecto
    def do_HEAD(self):
        name = os.path.join(D, "hdr" + self.path.replace("/", "_"))
        status = 200
        lines = []
        for l in open(name).read().splitlines():
            if l.startswith("STATUS "): status = int(l.split()[1])
            elif l: lines.append(l)
        self.send_response(status)
        for l in lines:
            k, v = l.split(": ", 1); self.send_header(k, v)
        self.end_headers()
    def log_message(self, *a): pass
s = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
s.serve_forever()
PY
  python3 "$T242/srv.py" "$T242/port" "$T242" &
  SRV242=$!
  for _ in $(seq 1 50); do [[ -s "$T242/port" ]] && break; sleep 0.1; done
  URL="http://127.0.0.1:$(cat "$T242/port")"
}

stop_http() { kill "$SRV242" 2>/dev/null; wait "$SRV242" 2>/dev/null || true; }

hdr_report() { ls "$OUT"/headers-check-127_0_0_1-*.json | head -1; }

# comprueba la puntuación en el informe y en la salida
score_is() {
  [ "$(jget "$(hdr_report)" "d['score']")" = "$1" ]
  [[ "$output" == *"SCORE: $1/"* ]]
}

ALL_HEADERS='Content-Security-Policy: default-src '"'"'self'"'"'
Strict-Transport-Security: max-age=63072000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: no-referrer
Permissions-Policy: geolocation=()'

@test "SE242-B20: headers check without --url prints usage and exits 1" {
  mk_tree242
  tls bash "$T242/scripts/web-headers-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "SE242-B21: headers check rejects unknown arguments" {
  mk_tree242
  tls bash "$T242/scripts/web-headers-check.sh" --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"argumento desconocido: --nope"* ]]
}

@test "SE242-B22: unreachable server exits 1 with a connection error" {
  mk_tree242
  tls bash "$T242/scripts/web-headers-check.sh" --url http://127.0.0.1:1/
  [ "$status" -eq 1 ]
  [[ "$output" == *"No se pudo conectar a http://127.0.0.1:1/"* ]]
}

@test "SE242-B23: all six headers present gives the top score with no findings" {
  mk_tree242; start_http
  printf '%s\n' "$ALL_HEADERS" > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$status" -eq 0 ]
  score_is 100
  [ "$(jget "$(hdr_report)" "d['findings'], d['follow_redirects']")" = "([], False)" ]
}

@test "SE242-B24: no security headers scores 0 and reports six missing findings" {
  mk_tree242; start_http
  printf 'X-Other: 1\n' > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$status" -eq 0 ]
  score_is 0
  [ "$(jget "$(hdr_report)" "len(d['findings']), set(d['headers'].values())")" = "(6, {None})" ]
}

@test "SE242-B25: each header is worth its documented points" {
  mk_tree242; start_http
  declare -A pts=( ["Content-Security-Policy: default-src none"]=25 ["Strict-Transport-Security: max-age=31536000"]=20
                   ["X-Content-Type-Options: nosniff"]=15 ["X-Frame-Options: DENY"]=15
                   ["Referrer-Policy: no-referrer"]=15 ["Permissions-Policy: camera=()"]=10 )
  for h in "${!pts[@]}"; do
    printf '%s\n' "$h" > "$T242/hdr_"
    tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
    score_is "${pts[$h]}"
  done
  stop_http
}

@test "SE242-B26: CSP frame-ancestors substitutes X-Frame-Options" {
  mk_tree242; start_http
  printf "Content-Security-Policy: frame-ancestors 'none'\n" > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  score_is 40
}

@test "SE242-B27: HSTS max-age below one year earns the points but adds a MEDIUM finding" {
  mk_tree242; start_http
  printf 'Strict-Transport-Security: max-age=100\n' > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  score_is 20
  [[ "$(jget "$(hdr_report)" "[f['message'] for f in d['findings'] if f['header']=='HSTS']")" == *"max-age < 31536000"* ]]
  printf 'Strict-Transport-Security: max-age=31536000\n' > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$(jget "$(hdr_report)" "[f['header'] for f in d['findings']]")" = "['Content-Security-Policy', 'X-Content-Type-Options', 'X-Frame-Options', 'Referrer-Policy', 'Permissions-Policy']" ]
}

@test "SE242-B28: Server version and X-Powered-By each cost 5 points, a bare Server name does not" {
  mk_tree242; start_http
  { echo "$ALL_HEADERS"; echo "Server: nginx/1.25.3"; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  score_is 95
  { echo "$ALL_HEADERS"; echo "Server: nginx"; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  score_is 100
  { echo "$ALL_HEADERS"; echo "Server: nginx/1.25.3"; echo "X-Powered-By: PHP/8.3"; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  score_is 90
  [[ "$(jget "$(hdr_report)" "[f['message'] for f in d['findings']]")" == *"X-Powered-By header exposes technology: PHP/8.3"* ]]
}

@test "SE242-B29: penalties never push the score below zero" {
  mk_tree242; start_http
  { echo "Server: nginx/1.25.3"; echo "X-Powered-By: PHP/8.3"; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  score_is 0
}

@test "SE242-B30: header values with double quotes still produce valid JSON" {
  mk_tree242; start_http
  { echo 'Content-Security-Policy: default-src "self"'; echo 'Server: ngx "x" 1.2'; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$status" -eq 0 ]
  [ "$(jget "$(hdr_report)" "d['headers']['content-security-policy']")" = 'default-src "self"' ]
}

@test "SE242-B31: redirects are only followed with --follow-redirects" {
  mk_tree242; start_http
  printf 'STATUS 301\nLocation: %s/final\n' "$URL" > "$T242/hdr_start"
  printf '%s\n' "$ALL_HEADERS" > "$T242/hdr_final"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/start"
  score_is 0
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/start" --follow-redirects
  stop_http
  score_is 100
  [ "$(jget "$(hdr_report)" "d['follow_redirects']")" = "True" ]
}

@test "SE242-B32: report records url, hostname and tool" {
  mk_tree242; start_http
  printf '%s\n' "$ALL_HEADERS" > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$(jget "$(hdr_report)" "d['url'], d['hostname'], d['tool']")" = "('$URL/', '127.0.0.1', 'web-headers-check')" ]
}

teardown() {
  [[ -n "${SRV242:-}" ]] && kill "$SRV242" 2>/dev/null
  [[ -n "${T242:-}" ]] && find "$T242" -delete
  true
}

@test "SE242-B40: real testssl ids for NULL, EXPORT and 3DES grade C" {
  mk_tree242; fake_testssl
  for id in cipherlist_NULL cipherlist_aNULL cipherlist_EXPORT cipherlist_3DES_IDEA TLS_RSA_WITH_3DES_EDE_CBC_SHA; do
    FAKE_TESTSSL_JSON='[{"id":"'"$id"'","severity":"HIGH","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
    [[ "$output" == *"GRADE: C"* ]] || { echo "id=$id output=$output"; false; }
  done
}

@test "SE242-B41: words that merely contain des or null do not grade C" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"cipherlist_OK","severity":"INFO","finding":"described, nullable, exported, destination"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: B"* ]]
}

@test "SE242-B42: a host starting with a dash is rejected" {
  mk_tree242; fake_testssl
  tls bash "$T242/scripts/tls-security-check.sh" --host "-x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"host inválido"* ]]
}

@test "SE242-B43: control characters in a header value keep the JSON valid" {
  mk_tree242; start_http
  { echo "$ALL_HEADERS"; printf 'Server: ngx\t1.2\n'; } > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "$URL/"
  stop_http
  [ "$status" -eq 0 ]
  [[ "$(jget "$(hdr_report)" "[f['message'] for f in d['findings']]")" == *"exposes version: ngx 1.2"* ]]
}

@test "SE242-B44: a retry on the same day never grades with the previous raw report" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"x","severity":"INFO","finding":"all good"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: B"* ]]
  # Segunda ejecución: testssl falla sin escribir; el informe crudo de antes no cuenta
  FAKE_TESTSSL_JSON='' FAKE_TESTSSL_EXIT=1 tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 2 ]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
  # Y un reintento con informe nuevo se califica con el nuevo, no con el viejo
  FAKE_TESTSSL_JSON='[{"id":"SSLv3","severity":"CRITICAL","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE: F"* ]]
}

@test "SE242-B45: a clean or a bad scan exits 0; only an ungraded scan exits 2" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"TLS1_2","severity":"OK","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE: B"* ]]
  FAKE_TESTSSL_JSON='[{"id":"SSLv3","severity":"CRITICAL","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE: F"* ]]
  FAKE_TESTSSL_JSON='' FAKE_TESTSSL_EXIT=1 tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 2 ]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
}

@test "SE242-B46: real testssl ids TLS1 and TLS1_1 grade D, TLS1_2 and TLS1_3 do not" {
  mk_tree242; fake_testssl
  for id in TLS1 TLS1_1; do
    FAKE_TESTSSL_JSON='[{"id":"'"$id"'","severity":"LOW","finding":"offered (deprecated)"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity LOW
    [[ "$output" == *"GRADE: D"* ]] || { echo "id=$id output=$output"; false; }
  done
  for id in TLS1_2 TLS1_3; do
    FAKE_TESTSSL_JSON='[{"id":"'"$id"'","severity":"LOW","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity LOW
    [[ "$output" == *"GRADE: B"* ]] || { echo "id=$id output=$output"; false; }
  done
}

@test "SE242-B47: protocols reported as not offered never lower the grade" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"SSLv3","severity":"LOW","finding":"not offered"},{"id":"TLS1","severity":"LOW","finding":"not offered"}]' \
    tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity LOW
  [[ "$output" == *"GRADE: B"* ]]
}

@test "SE242-B48: a JSON null cve does not grade C" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"BREACH","severity":"MEDIUM","finding":"potentially vulnerable","cve":null}]' \
    tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [[ "$output" == *"GRADE: B"* ]]
  f="$(ls "$OUT"/tls-check-example.org-*.json)"
  [ "$(jget "$f" "d['findings'][0]['cve']")" = "" ]
}

@test "SE242-B49: userinfo in the URL never reaches the report and keeps the JSON valid" {
  mk_tree242; start_http
  printf '%s\n' "$ALL_HEADERS" > "$T242/hdr_"
  tls bash "$T242/scripts/web-headers-check.sh" --url "http://u\"x:pw@${URL#http://}/"
  stop_http
  [ "$status" -eq 0 ]
  f="$(hdr_report)"
  [ "$(jget "$f" "d['hostname']")" = "127.0.0.1" ]
  [ "$(jget "$f" "d['url']")" = "${URL}/" ]
  run grep -c 'pw' "$f"
  [ "$output" = "0" ]
}

@test "SE242-B50: userinfo never reaches the connection error message" {
  mk_tree242
  tls bash "$T242/scripts/web-headers-check.sh" --url "http://u:pw@127.0.0.1:1/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No se pudo conectar a http://127.0.0.1:1/"* ]]
  [[ "$output" != *"pw"* ]]
}

@test "SE242-B51: the grade ignores --severity; LOW TLS1 and 3DES still lower it" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"TLS1","severity":"LOW","finding":"offered (deprecated)"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity HIGH
  [[ "$output" == *"GRADE: D"* ]]
  # testssl recibe siempre LOW; la lista de hallazgos sí respeta --severity HIGH
  grep -qx -- 'LOW' "$FAKE_ARGS"
  run ! grep -qx -- 'HIGH' "$FAKE_ARGS"
  [ "$(jget "$(ls "$OUT"/tls-check-example.org-*.json)" "d['findings']")" = "[]" ]
  FAKE_TESTSSL_JSON='[{"id":"cipherlist_3DES_IDEA","severity":"MEDIUM","finding":"offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity HIGH
  [[ "$output" == *"GRADE: C"* ]]
}

@test "SE242-B52: OK and INFO entries that name old protocols never lower the grade" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"POODLE_SSL","severity":"OK","finding":"not vulnerable, no SSLv3 support"},{"id":"FREAK","severity":"OK","finding":"not vulnerable, no RSA EXPORT ciphers"},{"id":"TLS1_2","severity":"INFO","finding":"TLSv1.0 disabled"}]' \
    tls bash "$T242/scripts/tls-security-check.sh" --host example.org --severity LOW
  [ "$status" -eq 0 ]
  [[ "$output" == *"GRADE: B"* ]]
}

@test "SE242-B53: TLS 1.0/1.1 grade D in any spelling, TLS 1.2/1.3 do not" {
  mk_tree242; fake_testssl
  for t in "TLS 1.0" "TLS 1.1" "TLSv1" "TLS1.0" "TLSv1.1"; do
    FAKE_TESTSSL_JSON='[{"id":"proto","severity":"LOW","finding":"'"$t"' offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
    [[ "$output" == *"GRADE: D"* ]] || { echo "t=$t output=$output"; false; }
  done
  for t in "TLS 1.2" "TLSv1.3" "TLS1.2" "TLS1_3"; do
    FAKE_TESTSSL_JSON='[{"id":"proto","severity":"LOW","finding":"'"$t"' offered"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
    [[ "$output" == *"GRADE: B"* ]] || { echo "t=$t output=$output"; false; }
  done
}

@test "SE242-B54: a testssl scanProblem or FATAL entry is ungraded and exits 2" {
  mk_tree242; fake_testssl
  FAKE_TESTSSL_JSON='[{"id":"scanProblem","severity":"FATAL","finding":"No engine or GET request"}]' tls bash "$T242/scripts/tls-security-check.sh" --host example.org
  [ "$status" -eq 2 ]
  [[ "$output" == *"GRADE: UNKNOWN"* ]]
}
