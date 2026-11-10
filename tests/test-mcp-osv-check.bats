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
  malodd)  printf '{"vulns":[{"id":"MAL-2026 1","aliases":["MAL/../x"]}]}\n200' ;;
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
  [ -s "$SAVIA_OSV_RECEIPT_FILE" ]
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
  printf '{"mcpServers":{"x":{"command":"npx","args":["-y","pkg@1.0.0"],"description":"d"}}}' > "$BATS_TEST_TMPDIR/cfg.json"
  run bash "$SCRIPT" --config "$BATS_TEST_TMPDIR/cfg.json"
  [ "$status" -eq 0 ]
  [ ! -e "$CAPTURE/args" ]
}

@test "ningún hook ni settings invoca --osv" {
  # Cualquier fichero de arranque que mencione --osv cuenta, aunque la llamada vaya por
  # variable o en otra línea. Solo se miran las rutas que existen, para que grep no dé 2.
  local paths=() p
  for p in .claude/hooks .claude/settings.json .opencode/plugins; do [[ -e "$p" ]] && paths+=("$p"); done
  [ "${#paths[@]}" -gt 0 ]
  run grep -rlF -- '--osv' "${paths[@]}"
  [ "$status" -eq 1 ]
}

# ── Opciones del ejecutor que cambian qué se instala → ASK (revisión PR #1500) ─
@test "npx --package=evil left-pad → 2 y sin llamar a OSV" {
  FAKE_OSV=clean osv npx --package=evil@1.0.0 left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" == *"VERDICT: ASK"* ]]
  [[ "$output" == *"opción del ejecutor no admitida"* ]]
  [ ! -e "$CAPTURE/body" ]
}

@test "npx -p evil left-pad → 2" {
  FAKE_OSV=clean osv npx -p evil@1.0.0 left-pad@1.3.0
  [ "$status" -eq 2 ]
  [ ! -e "$CAPTURE/body" ]
}

@test "npx --registry URL pkg → 2" {
  FAKE_OSV=clean osv npx --registry https://registry.example left-pad@1.3.0
  [ "$status" -eq 2 ]
  [ ! -e "$CAPTURE/body" ]
}

@test "uvx --from=evil tool → 2" {
  FAKE_OSV=clean osv uvx --from=evil==1.0 tool==1.0
  [ "$status" -eq 2 ]
  [ ! -e "$CAPTURE/body" ]
}

@test "uvx --with evil good → 2" {
  FAKE_OSV=clean osv uvx --with evil==1.0 good==1.0
  [ "$status" -eq 2 ]
  [ ! -e "$CAPTURE/body" ]
}

@test "opciones inofensivas (--yes, -q) antes del paquete siguen dando 0" {
  FAKE_OSV=clean osv npx --yes -q left-pad@1.3.0 --port 3000
  [ "$status" -eq 0 ]
  run jq -r '.package.name' "$CAPTURE/body"
  [ "$output" = "left-pad" ]
}

# ── Saneado de IDs no oculta malware ─────────────────────────────────────────
@test "aviso MAL-* con IDs no imprimibles → 1 con marcador, no 0" {
  FAKE_OSV=malodd osv npx evil-pkg@1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERDICT: FAIL"* ]]
  [[ "$output" == *"MAL-id-no-imprimible"* ]]
  [[ "$output" != *"MAL/../x"* ]]
}

# ── Nombres ──────────────────────────────────────────────────────────────────
@test "npm legacy con mayúsculas (JSONStream) se consulta, no ASK" {
  FAKE_OSV=clean osv npx JSONStream@1.3.5
  [ "$status" -eq 0 ]
  run jq -r '.package.name' "$CAPTURE/body"
  [ "$output" = "JSONStream" ]
}

@test "PyPI: el nombre se envía normalizado (PEP 503)" {
  FAKE_OSV=clean osv uvx MCP_Server..Fetch==1.0
  [ "$status" -eq 0 ]
  run jq -r '.package.name' "$CAPTURE/body"
  [ "$output" = "mcp-server-fetch" ]
}

@test "curl se llama con -q para ignorar ~/.curlrc" {
  FAKE_OSV=clean osv npx left-pad@1.3.0
  [ "$status" -eq 0 ]
  [ "$(head -1 "$CAPTURE/args")" = "-q" ]
}

# ── Recibo: nunca entrada cruda ni JSON roto (revisión PR #1500, 2.ª ronda) ────
@test "opción con comillas: recibo JSON válido y sin la entrada cruda" {
  osv npx '--x"y' p@1.0.0
  [ "$status" -eq 2 ]
  [[ "$output" != *'--x"y'* ]]
  run jq -e -s 'length == 1 and .[0].result == "unknown" and .[0].exit == 2' "$SAVIA_OSV_RECEIPT_FILE"
  [ "$status" -eq 0 ]
  run grep -cF -- '--x"y' "$SAVIA_OSV_RECEIPT_FILE"
  [ "$output" = "0" ]
}

@test "opción con credencial: ni stdout ni recibo la repiten" {
  osv npx --registry=https://user:S3CRET@registry.example left-pad@1.3.0
  [ "$status" -eq 2 ]
  [[ "$output" != *"S3CRET"* ]]
  run grep -cF "S3CRET" "$SAVIA_OSV_RECEIPT_FILE"
  [ "$output" = "0" ]
}

@test "sin jq: el recibo de respaldo sigue siendo JSON válido" {
  local p; p="$(minpath with-curl)"
  run env PATH="$p" bash "$SCRIPT" --osv npx left-pad@1.3.0
  [ "$status" -eq 2 ]
  run python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][0]; print(r["name"], r["version"], r["exit"], r["reason"])' "$SAVIA_OSV_RECEIPT_FILE"
  [ "$output" = "left-pad 1.3.0 2 jq ausente" ]
}

@test "escapador de respaldo: comillas, barras y controles dan JSON válido" {
  run bash -c 'source <(sed -n "/^osv_json_str()/p" "$1"); osv_json_str "$(printf "a\"b\\\\c\nd\te")"' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; print(json.loads(sys.argv[1]))' "$output"
  [ "$output" = 'a"b\cde' ]
}

# ── Versiones: solo formas que OSV recibe igual que las resuelve el ejecutor ────
@test "npm con metadatos de build (+x) → 2 y sin llamar a OSV" {
  FAKE_OSV=clean osv npx evil@1.0.0+x
  [ "$status" -eq 2 ]
  [ ! -e "$CAPTURE/body" ]
}

@test "npm con prerelease sigue consultándose" {
  FAKE_OSV=clean osv npx pkg@1.0.0-beta.1
  [ "$status" -eq 0 ]
  run jq -r '.version' "$CAPTURE/body"
  [ "$output" = "1.0.0-beta.1" ]
}

@test "PyPI con versión no canónica (1.0.0-RC1, 1.0+local, 1.x) → 2" {
  local i=0 v
  for v in 1.0.0-RC1 1.0+local 1.x 1.0.dev-foo; do
    i=$((i + 1)); export CAPTURE="$BATS_TEST_TMPDIR/cap$i"; mkdir -p "$CAPTURE"
    FAKE_OSV=clean osv uvx tool=="$v"
    [ "$status" -eq 2 ]
    [ ! -e "$CAPTURE/body" ]
  done
}

@test "PyPI con versión canónica (1.0rc1, 2.1.post1, 1!2.0.dev3) se consulta" {
  local v
  for v in 1.0rc1 2.1.post1 '1!2.0.dev3'; do
    FAKE_OSV=clean osv uvx tool=="$v"
    [ "$status" -eq 0 ]
    run jq -r '.version' "$CAPTURE/body"
    [ "$output" = "$v" ]
  done
}
