#!/usr/bin/env bats
# SE-443 S2 — `scripts/mcp-security-audit.sh --osv`: aviso de malware en OSV antes de habilitar
# un MCP npx/uvx. Sin red real: un `curl` simulado en PATH captura el cuerpo y responde según
# FAKE_OSV. Ref: docs/specs/SE-443-mcp-connector-governance.spec.md (AC2, AC3 parte script, AC4).
SCRIPT="scripts/mcp-security-audit.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  FAKEBIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$FAKEBIN"
  export CAPTURE="$BATS_TEST_TMPDIR/captured"; mkdir -p "$CAPTURE"
  export SAVIA_OSV_RECEIPT_FILE="$BATS_TEST_TMPDIR/receipts/osv.jsonl"
  cat > "$FAKEBIN/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CAPTURE/args"
cat > "$CAPTURE/body"
case "${FAKE_OSV:-clean}" in
  mal)     printf '{"vulns":[{"id":"MAL-2026-0001","aliases":["GHSA-xxxx-yyyy-zzzz"],"summary":"Malicious code in evil-pkg"}]}\n200' ;;
  cve)     printf '{"vulns":[{"id":"GHSA-aaaa-bbbb-cccc","aliases":["CVE-2026-1"]}]}\n200' ;;
  alias)   printf '{"vulns":[{"id":"GHSA-aaaa-bbbb-cccc","aliases":["MAL-2026-0002"]}]}\n200' ;;
  paged)   printf '{"vulns":[{"id":"GHSA-aaaa-bbbb-cccc"}],"next_page_token":"abc"}\n200' ;;
  clean)   printf '{}\n200' ;;
  down)    echo "curl: (7) Failed to connect" >&2; exit 7 ;;
  timeout) echo "curl: (28) Operation timed out" >&2; exit 28 ;;
  html)    printf '<html>proxy</html>\n200' ;;
  empty)   printf '\n200' ;;
  e503)    printf '{"error":"unavailable"}\n503' ;;
  notobj)  printf '[1,2]\n200' ;;
esac
SH
  chmod +x "$FAKEBIN/curl"
  export PATH="$FAKEBIN:$PATH"
}

osv() { run bash "$SCRIPT" --osv "$@"; }

# ── AC2 ──────────────────────────────────────────────────────────────────────
@test "AC2: aviso MAL-* para evil-pkg@1.0.0 → exit 1 y nombra el aviso" {
  FAKE_OSV=mal osv npx evil-pkg@1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"MAL-2026-0001"* ]]
  [[ "$output" == *"VERDICT: FAIL"* ]]
  [[ "$output" == *'"result":"findings"'* ]]
}

@test "AC2: left-pad@1.3.0 sin avisos → exit 0" {
  FAKE_OSV=clean osv npx left-pad@1.3.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: PASS"* ]]
  [[ "$output" == *'"result":"clean"'* ]]
}

@test "MAL-* solo como alias de un GHSA también bloquea" {
  FAKE_OSV=alias osv npx evil-pkg@1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"MAL-2026-0002"* ]]
}

@test "aviso no-malware (CVE) no es malware: exit 0 (vulnerabilidades son SE-244)" {
  FAKE_OSV=cve osv npx left-pad@1.3.0
  [ "$status" -eq 0 ]
}

@test "respuesta paginada sin MAL-* en la primera página → 2, no 0" {
  FAKE_OSV=paged osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *'"reason":"limit"'* ]]
}

# ── AC3 (parte del script): OSV inaccesible → 2, nunca 0 ─────────────────────
@test "AC3: red caída → 2 (ASK)" {
  FAKE_OSV=down osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
}

@test "AC3: tiempo agotado → 2 con motivo timeout" {
  FAKE_OSV=timeout osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *'"reason":"timeout"'* ]]
}

@test "AC3: respuesta no JSON → 2" {
  FAKE_OSV=html osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
}

@test "AC3: cuerpo vacío con HTTP 200 → 2" {
  FAKE_OSV=empty osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
}

@test "AC3: JSON que no es objeto → 2" {
  FAKE_OSV=notobj osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
}

@test "AC3: HTTP 5xx → 2" {
  FAKE_OSV=e503 osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *"HTTP 503"* ]]
}

# PATH mínimo: solo las herramientas que usa el modo --osv, para quitar curl o jq de verdad.
minpath() {
  local d="$BATS_TEST_TMPDIR/min"; mkdir -p "$d"
  local t; for t in bash date mkdir dirname cat; do ln -sf "$(command -v "$t")" "$d/$t"; done
  [[ "$1" == with-curl ]] && ln -sf "$FAKEBIN/curl" "$d/curl"
  [[ "$1" == with-jq ]] && ln -sf "$(command -v jq)" "$d/jq"
  echo "$d"
}

@test "AC3: curl ausente → 2 con missing_tool" {
  local p; p="$(minpath with-jq)"
  run env PATH="$p" bash "$SCRIPT" --osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *'"check":"curl","reason":"missing_tool"'* ]]
}

@test "AC3: jq ausente → 2 con missing_tool" {
  local p; p="$(minpath with-curl)"
  run env PATH="$p" bash "$SCRIPT" --osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *'"check":"jq","reason":"missing_tool"'* ]]
}

# ── AC4: el cuerpo solo lleva {ecosystem, name, version} ────────────────────
@test "AC4: cuerpo capturado tiene exactamente ecosystem, name y version" {
  export SECRET_CANARY="tok-$RANDOM-canary"
  FAKE_OSV=clean osv npx @org/pkg@1.2.3
  [ "$status" -eq 0 ]
  run jq -c '[paths(scalars) | map(tostring) | join(".")] | sort' "$CAPTURE/body"
  [ "$output" = '["package.ecosystem","package.name","version"]' ]
  run jq -r '.package.ecosystem, .package.name, .version' "$CAPTURE/body"
  [ "$output" = $'npm\n@org/pkg\n1.2.3' ]
  # Nada del entorno ni rutas locales en el cuerpo ni en los argumentos de curl
  run grep -lF "$SECRET_CANARY" "$CAPTURE/body" "$CAPTURE/args"; [ "$status" -eq 1 ]
  run grep -lF "$HOME" "$CAPTURE/body"; [ "$status" -eq 1 ]
  run grep -lF "$PWD" "$CAPTURE/body" "$CAPTURE/args"; [ "$status" -eq 1 ]
  grep -qx 'https://api.osv.dev/v1/query' "$CAPTURE/args"
}

@test "AC4: uvx → ecosistema PyPI con pkg==ver" {
  FAKE_OSV=clean osv uvx mcp-server-fetch==2025.1.17
  [ "$status" -eq 0 ]
  run jq -r '.package.ecosystem, .package.name, .version' "$CAPTURE/body"
  [ "$output" = $'PyPI\nmcp-server-fetch\n2025.1.17' ]
}

@test "flags del ejecutor (npx -y) se saltan y no se envían" {
  FAKE_OSV=clean osv npx -y left-pad@1.3.0 --stdio
  [ "$status" -eq 0 ]
  run jq -r '.package.name, .version' "$CAPTURE/body"
  [ "$output" = $'left-pad\n1.3.0' ]
}

# ── Casos límite: nunca 0 sin comprobar, y sin salir a la red ────────────────
@test "sin versión → 2 con motivo y sin llamar a OSV" {
  osv npx left-pad
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *"sin versión exacta"* ]]
  [ ! -e "$CAPTURE/body" ]
}

@test "scope sin versión → 2 y sin llamar a OSV" {
  osv npx @org/pkg
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [ ! -e "$CAPTURE/body" ]
}

@test "versión no exacta (latest, rango) → 2" {
  osv npx left-pad@latest
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  osv npx left-pad@^1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [ ! -e "$CAPTURE/body" ]
}

@test "ruta local como paquete → 2 y no se envía" {
  osv npx "$HOME/evil/pkg@1.0.0"
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [ ! -e "$CAPTURE/body" ]
  run grep -cF "$HOME" "$SAVIA_OSV_RECEIPT_FILE"; [ "$output" = "0" ]
}

@test "ejecutor desconocido → 2" {
  osv docker evil-pkg@1.0.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *"ejecutor no soportado"* ]]
  [ ! -e "$CAPTURE/body" ]
}

@test "sin argumentos → 2" {
  osv
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
}

# ── Recibo ───────────────────────────────────────────────────────────────────
@test "recibo: una línea JSON por consulta con resultado y avisos" {
  FAKE_OSV=mal osv npx evil-pkg@1.0.0
  FAKE_OSV=down osv npx left-pad@1.3.0
  [ "$(wc -l < "$SAVIA_OSV_RECEIPT_FILE")" -eq 2 ]
  run jq -r '[.ecosystem,.name,.version,.result,(.exit|tostring),(.advisories|join(","))] | join("|")' "$SAVIA_OSV_RECEIPT_FILE"
  [ "${lines[0]}" = "npm|evil-pkg|1.0.0|findings|1|GHSA-xxxx-yyyy-zzzz,MAL-2026-0001" ]
  [ "${lines[1]}" = "npm|left-pad|1.3.0|unknown|2|" ]
}

@test "recibo no escribible: un resultado limpio pasa a 2" {
  export SAVIA_OSV_RECEIPT_FILE="/proc/no-such-dir/osv.jsonl"
  FAKE_OSV=clean osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *"recibo"* ]]
}

# ── El arranque no usa red ───────────────────────────────────────────────────
@test "auditoría por defecto (sin --osv) no llama a curl" {
  run bash "$SCRIPT" --config "$BATS_TEST_TMPDIR/none.json"
  [ ! -e "$CAPTURE/args" ]
}

@test "ningún hook ni settings invoca --osv" {
  run grep -rlE 'mcp-security-audit\.sh[^|;]*--osv' .claude/hooks .claude/settings.json .opencode/plugins
  [ "$status" -eq 1 ]
}
