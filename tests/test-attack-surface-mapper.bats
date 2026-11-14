#!/usr/bin/env bats
# SE-376 S03 — attack-surface-mapper: el mapeo solo corre con una autorización válida, vigente y
# del objetivo exacto; el objetivo se valida como nombre DNS. Se ejecutan los scripts reales en un
# árbol aislado con herramientas falsas (nunca red ni Docker).
# Ref: SE-243 · .claude/skills/attack-surface-mapper/SKILL.md · scripts/attack-surface-map.sh · scripts/surface-map-authorize.sh
set -uo pipefail

SCRIPT="scripts/attack-surface-map.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  P="$BATS_TEST_TMPDIR/proj"; B="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$P/scripts" "$B"
  cp "$REPO_ROOT/scripts/attack-surface-map.sh" "$REPO_ROOT/scripts/surface-map-authorize.sh" "$P/scripts/"
  MAP="$P/scripts/attack-surface-map.sh"; AUTH="$P/scripts/surface-map-authorize.sh"
  SEC="$P/output/security"
  # docker falso que falla: el camino de reserva nunca llega a ejecutar contenedores reales.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$B/docker"; chmod +x "$B/docker"
  export TOOL_LOG="$BATS_TEST_TMPDIR/tools.log"; : > "$TOOL_LOG"
  export PATH="$B:$PATH"
}

teardown() { unset TOOL_LOG; }

# Herramientas falsas: solo los casos que las necesitan las instalan.
install_tools() {
  cat > "$B/subfinder" <<'S'
#!/usr/bin/env bash
echo "subfinder $*" >> "$TOOL_LOG"
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
printf 'a.ejemplo.com\nb.ejemplo.com\n' > "$out"
S
  cat > "$B/httpx" <<'S'
#!/usr/bin/env bash
echo "httpx $*" >> "$TOOL_LOG"
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
echo '{"url":"https://a.ejemplo.com"}' > "$out"
S
  cat > "$B/theHarvester" <<'S'
#!/usr/bin/env bash
echo "theHarvester $*" >> "$TOOL_LOG"
S
  cat > "$B/dnstwist" <<'S'
#!/usr/bin/env bash
echo "dnstwist $*" >> "$TOOL_LOG"
echo '[{"domain":"ejemp1o.com"}]'
S
  chmod +x "$B/subfinder" "$B/httpx" "$B/theHarvester" "$B/dnstwist"
}

authorize() { printf 'AUTHORIZED\n' | bash "$AUTH" --target "$1"; }

@test "positivo: autorizar con la palabra exacta crea el fichero con objetivo, caducidad y alcance" {
  run authorize ejemplo.com
  [ "$status" -eq 0 ]
  [ "$(head -1 "$SEC/authorization-ejemplo.com.txt")" = "AUTHORIZED" ]
  grep -q "^target: ejemplo.com$" "$SEC/authorization-ejemplo.com.txt"
  grep -q "^valid_days: 30$" "$SEC/authorization-ejemplo.com.txt"
}

@test "negativo: respuesta distinta de AUTHORIZED (minúsculas, sí, vacía) aborta y no crea fichero" {
  for r in authorized yes si ""; do
    run bash -c "printf '%s\n' '$r' | bash '$AUTH' --target ejemplo.com"
    [ "$status" -eq 1 ] || { echo "respuesta '$r' aceptada"; false; }
  done
  [ ! -e "$SEC/authorization-ejemplo.com.txt" ]
}

@test "positivo: con autorización vigente el mapa corre las herramientas y escribe el informe JSON con el recuento" {
  install_tools
  authorize ejemplo.com >/dev/null
  run bash "$MAP" --target ejemplo.com --tools subfinder,httpx
  [ "$status" -eq 0 ]
  [[ "$output" == *"[auth] Authorization verified for target: ejemplo.com"* ]]
  grep -q "^subfinder -d ejemplo.com" "$TOOL_LOG"
  grep -q "^httpx " "$TOOL_LOG"
  rep="$(ls "$SEC"/surface-map-ejemplo.com-*.json)"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['target']=='ejemplo.com' and d['subdomains_found']==2, d" "$rep"
}

@test "negativo: sin fichero de autorización no se ejecuta ninguna herramienta (exit 1)" {
  install_tools
  run bash "$MAP" --target ejemplo.com --tools subfinder
  [ "$status" -eq 1 ]
  [[ "$output" == *"Authorization file not found"* ]]
  [ ! -s "$TOOL_LOG" ]
}

@test "negativo: la autorización de otro dominio no vale para este, y cada dominio usa la suya" {
  install_tools
  authorize otro.com >/dev/null
  run bash "$MAP" --target otro.com --tools subfinder
  [ "$status" -eq 0 ]
  : > "$TOOL_LOG"
  run bash "$MAP" --target ejemplo.com --tools subfinder
  [ "$status" -eq 1 ]
  [ ! -s "$TOOL_LOG" ]
}

@test "negativo: «NOT AUTHORIZED» y «UNAUTHORIZED» no cuentan como concesión; solo la primera línea exacta" {
  install_tools
  mkdir -p "$SEC"
  for l in "NOT AUTHORIZED" "UNAUTHORIZED" "authorized" " AUTHORIZED"; do
    printf '%s\n' "$l" > "$SEC/authorization-ejemplo.com.txt"
    run bash "$MAP" --target ejemplo.com --tools subfinder
    [ "$status" -eq 1 ] || { echo "'$l' aceptado"; false; }
  done
  [ ! -s "$TOOL_LOG" ]
  printf 'AUTHORIZED\r\n' > "$SEC/authorization-ejemplo.com.txt"
  run bash "$MAP" --target ejemplo.com --tools subfinder
  [ "$status" -eq 0 ]
}

@test "limite boundary: autorización de 29 días vale; de 31 días caduca y exige reautorizar" {
  install_tools
  authorize ejemplo.com >/dev/null
  touch -d "29 days ago" "$SEC/authorization-ejemplo.com.txt"
  run bash "$MAP" --target ejemplo.com --tools subfinder
  [ "$status" -eq 0 ]
  : > "$TOOL_LOG"
  touch -d "31 days ago" "$SEC/authorization-ejemplo.com.txt"
  run bash "$MAP" --target ejemplo.com --tools subfinder
  [ "$status" -eq 1 ]
  [[ "$output" == *"older than 30 days"* ]]
  [ ! -s "$TOOL_LOG" ]
}

@test "error: objetivo inválido (ruta, guion inicial, espacio, comillas, sin punto) se rechaza en ambos scripts sin crear ficheros" {
  for t in "../etc/passwd" "-d" "a b.com" "x'.com" "nodot" "a..com"; do
    run bash "$MAP" --target "$t"
    [ "$status" -eq 1 ] || { echo "mapa aceptó '$t'"; false; }
    [[ "$output" == *"must be a domain name"* ]] || { echo "mapa no validó '$t': $output"; false; }
    T="$t" run bash -c 'printf "AUTHORIZED\n" | bash "$0" --target "$T"' "$AUTH"
    [ "$status" -eq 1 ] || { echo "autorizador aceptó '$t'"; false; }
  done
  [ ! -d "$SEC" ] || [ -z "$(ls "$SEC")" ]
}

@test "error: --target sin valor, ausente u opción desconocida → exit 1 con uso" {
  run bash "$MAP" --target
  [ "$status" -eq 1 ]
  run bash "$MAP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--target is required"* ]]
  run bash "$MAP" --target ejemplo.com --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "degradación: sin la herramienta ni Docker se omite con SKIP y el informe se escribe igual con 0 subdominios" {
  PATH="$B:/usr/bin:/bin" command -v subfinder >/dev/null && skip "subfinder real instalado en el sistema"
  authorize ejemplo.com >/dev/null
  PATH="$B:/usr/bin:/bin" run bash "$MAP" --target ejemplo.com --tools subfinder,httpx
  [ "$status" -eq 0 ]
  [[ "$output" == *"[subfinder] SKIP"* ]]
  [[ "$output" == *"[httpx] SKIP — no input"* ]]
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['subdomains_found']==0, d" "$(ls "$SEC"/surface-map-ejemplo.com-*.json)"
}

@test "limite: una herramienta desconocida en --tools avisa y no ejecuta nada" {
  install_tools
  authorize ejemplo.com >/dev/null
  run bash "$MAP" --target ejemplo.com --tools nmap
  [ "$status" -eq 0 ]
  [[ "$output" == *"[warn] Unknown tool: nmap"* ]]
  [ ! -s "$TOOL_LOG" ]
}

@test "run_theharvester y run_dnstwist: se invocan con el objetivo autorizado y dnstwist deja su JSON en raw/" {
  install_tools
  authorize ejemplo.com >/dev/null
  run bash "$MAP" --target ejemplo.com --tools theharvester,dnstwist
  [ "$status" -eq 0 ]
  grep -q "^theHarvester -d ejemplo.com " "$TOOL_LOG"
  grep -q "^dnstwist --registered --format json ejemplo.com$" "$TOOL_LOG"
  grep -q "ejemp1o.com" "$(ls "$SEC"/attack-surface-ejemplo.com-*/raw/dnstwist.json)"
}

@test "usage: --help sale con 1 y nombra el fichero de autorización requerido; el autorizador igual (parse_args)" {
  run bash "$MAP" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"authorization-{target}.txt"* ]]
  run bash "$AUTH" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"Required before running attack-surface-map.sh"* ]]
}
