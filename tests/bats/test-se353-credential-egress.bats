#!/usr/bin/env bats
# test-se353-credential-egress.bats — BATS tests for SE-353 Sentinel Credential Substitution
# Ref: SE-353 — credenciales fuera del contexto del modelo, resolución solo en egress

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  EGRESS="$REPO_ROOT/scripts/credential-egress.sh"
  export EGRESS
  # Store aislado por test (tmpdir, se limpia en teardown)
  export SAVIA_CRED_STORE_DIR="$(mktemp -d)"
}

teardown() {
  if [[ -d "${SAVIA_CRED_STORE_DIR:-}" ]]; then
    rm -rf "$SAVIA_CRED_STORE_DIR"
  fi
}

# ── T1: store / resolve / status ──────────────────────────────────────────────

@test "store crea keys.json con permisos 0600" {
  run bash -c 'printf "%s" "secreto-123" | "$EGRESS" store pat-test'
  [[ "$status" -eq 0 ]]
  local perms
  perms=$(stat -c "%a" "$SAVIA_CRED_STORE_DIR/keys.json")
  [[ "$perms" == "600" ]]
}

@test "store guarda cifrado (no contiene el valor en plano)" {
  printf "%s" "VALOR-PLANO-SUPERSECRETO-999" | "$EGRESS" store "pat-test" >/dev/null
  run grep -q "VALOR-PLANO-SUPERSECRETO-999" "$SAVIA_CRED_STORE_DIR/keys.json"
  [[ "$status" -ne 0 ]]
}

@test "resolve devuelve el valor real para destino autorizado" {
  printf "%s" "valor-real-abc" | "$EGRESS" store "pat-test" >/dev/null
  run "$EGRESS" resolve "pat-test" --dest dev.azure.com
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-real-abc" ]]
}

@test "resolve REFUSE destino no autorizado" {
  printf "%s" "valor-real-abc" | "$EGRESS" store "pat-test" >/dev/null
  run "$EGRESS" resolve "pat-test" --dest evil.com
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"REFUSE"* ]]
}

@test "resolve REFUSE marcador no registrado" {
  printf "%s" "valor-abc" | "$EGRESS" store "pat-existente" >/dev/null
  run "$EGRESS" resolve "no-existe-xyz" --dest dev.azure.com
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"REFUSE"* ]]
}

@test "resolve REFUSE store no existe" {
  run "$EGRESS" resolve "pat-test" --dest dev.azure.com
  [[ "$status" -ne 0 ]]
}

# ── T2: run (sustitución en subproceso) ───────────────────────────────────────

@test "run sustituye savia:cred:<key> en args y ejecuta" {
  printf "%s" "valor-run-42" | "$EGRESS" store "pat-test" >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "recibido:$(cat "$1")"' _ savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "recibido:valor-run-42" ]]
}

@test "run con marcador no registrado → exit != 0" {
  run "$EGRESS" run --dest github.com bash -c 'echo x' _ savia:cred:no-existe
  [[ "$status" -ne 0 ]]
}

# ── T3: status (nunca valores) ────────────────────────────────────────────────

@test "status lista keys sin exponer valores" {
  printf "%s" "secreto-a" | "$EGRESS" store "pat-a" >/dev/null
  printf "%s" "secreto-b" | "$EGRESS" store "pat-b" >/dev/null
  run "$EGRESS" status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"pat-a"* ]]
  [[ "$output" == *"pat-b"* ]]
  [[ "$output" != *"secreto-a"* ]]
  [[ "$output" != *"secreto-b"* ]]
}

# ── T4: audit ─────────────────────────────────────────────────────────────────

@test "audit produce output de diagnóstico" {
  run "$EGRESS" audit
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Audit"* ]]
}

@test "audit detecta PAT-shaped en tests de hooks" {
  run "$EGRESS" audit "$REPO_ROOT"
  # los tests de hooks contienen ghp_ de ejemplo — el audit debe encontrarlos
  [[ "$output" == *"ghp_"* ]]
}

# ── T5: integridad / fail-safe ────────────────────────────────────────────────

@test "store sin valor (stdin vacío) → error y no crea store" {
  run "$EGRESS" store "solo-key" </dev/null
  [[ "$status" -ne 0 ]]
  [[ ! -f "$SAVIA_CRED_STORE_DIR/keys.json" ]]
}

@test "resolve sin key → error" {
  run "$EGRESS" resolve
  [[ "$status" -ne 0 ]]
}

# ── T6: G2 (savia-labs#12) — resolve fail-closed y secreto fuera de argv ────────

@test "G2: resolve sin --dest → REFUSE, exit != 0 y stdout vacío" {
  printf '%s' "valor-sin-dest-777" | "$EGRESS" store pat-test >/dev/null
  local out rc=0
  out=$("$EGRESS" resolve pat-test 2>/dev/null) || rc=$?
  [[ "$rc" -ne 0 ]]
  [[ -z "$out" ]]
  run "$EGRESS" resolve pat-test
  [[ "$output" == *"REFUSE"* ]]
  [[ "$output" != *"valor-sin-dest-777"* ]]
}

@test "G2: resolve con --dest vacío o sin valor → REFUSE sin valor en stdout" {
  printf '%s' "valor-dest-vacio-778" | "$EGRESS" store pat-test >/dev/null
  local out rc=0
  out=$("$EGRESS" resolve pat-test --dest "" 2>/dev/null) || rc=$?
  [[ "$rc" -ne 0 ]]
  [[ -z "$out" ]]
  rc=0
  out=$("$EGRESS" resolve pat-test --dest 2>/dev/null) || rc=$?
  [[ "$rc" -ne 0 ]]
  [[ -z "$out" ]]
}

@test "G2: resolve con dest no autorizado → nada en stdout" {
  printf '%s' "valor-evil-779" | "$EGRESS" store pat-test >/dev/null
  local out rc=0
  out=$("$EGRESS" resolve pat-test --dest evil.com 2>/dev/null) || rc=$?
  [[ "$rc" -ne 0 ]]
  [[ -z "$out" ]]
}

@test "G2: allowlist exacta — subcadenas y comodines regex no autorizan" {
  printf '%s' "valor-sub-780" | "$EGRESS" store pat-test >/dev/null
  local d
  for d in azure.com dev com githubXcom "github.com.evil.io" "dev.azure.com evil.com"; do
    run "$EGRESS" resolve pat-test --dest "$d"
    [[ "$status" -ne 0 ]]
    [[ "$output" != *"valor-sub-780"* ]]
  done
}

@test "G2: store lee el valor por stdin con '-' explícito" {
  printf '%s' "valor-stdin-781" | "$EGRESS" store pat-test - >/dev/null
  run "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-stdin-781" ]]
}

@test "G2: store con VALUE por argv → rechazado y no se almacena" {
  run "$EGRESS" store pat-test "valor-argv-782" </dev/null
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"argv"* ]]
  [[ ! -f "$SAVIA_CRED_STORE_DIR/keys.json" ]]
}

@test "G2: run sin destino determinable → REFUSE y no ejecuta" {
  printf '%s' "valor-run-783" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "recibido:$1"' _ savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" != *"valor-run-783"* ]]
  [[ "$output" != *"recibido"* ]]
}

@test "G2: run deduce el destino del host de la URL autorizada" {
  printf '%s' "valor-run-784" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "recibido:$(cat "$2")"' _ https://api.github.com/user savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "recibido:valor-run-784" ]]
}

@test "G2: run con URL a host no autorizado → REFUSE" {
  printf '%s' "valor-run-785" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "recibido:$2"' _ https://evil.com/x savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" != *"valor-run-785"* ]]
}

@test "G2: run con --dest que no coincide con el host de la URL → REFUSE" {
  printf '%s' "valor-run-786" | "$EGRESS" store pat-test >/dev/null
  # Ambos hosts están en la allowlist: el rechazo viene de la discrepancia.
  run "$EGRESS" run --dest github.com bash -c 'echo "recibido:$2"' _ https://dev.azure.com/x savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no coincide"* ]]
  [[ "$output" != *"valor-run-786"* ]]
}

@test "G2: run con URLs a dos hosts autorizados distintos → REFUSE" {
  printf '%s' "valor-run-787" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "$3"' _ https://github.com/a https://dev.azure.com/b savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" != *"valor-run-787"* ]]
}

# ── T7: revisión PR #1457 — URLs en cualquier posición, autoridad ambigua, límites ─

@test "G2r: run detecta la URL dentro de '--url=' y rechaza la discrepancia" {
  printf '%s' "valor-r-801" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "recibido:$2"' _ --url=https://evil.example/ savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no coincide"* ]]
  [[ "$output" != *"valor-r-801"* ]]
}

@test "G2r: run detecta la URL dentro de un script de 'bash -c'" {
  printf '%s' "valor-r-802" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "https://evil.example/?t=$1"' _ savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"REFUSE"* ]]
  [[ "$output" != *"valor-r-802"* ]]
}

@test "G2r: run rechaza autoridad con '\\' o '%' (discrepancia de parsers)" {
  printf '%s' "valor-r-803" | "$EGRESS" store pat-test >/dev/null
  local u
  for u in 'https://evil.example\@github.com/' 'https://evil.example%2f@github.com/'; do
    run "$EGRESS" run bash -c 'echo "recibido:$2"' _ "$u" savia:cred:pat-test
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"ambigua"* ]]
    [[ "$output" != *"valor-r-803"* ]]
  done
}

@test "G2r: run sin marcadores no valida hosts (sin credencial, sin cambio)" {
  run "$EGRESS" run bash -c 'echo "ok:$1:$2"' _ https://github.com/a https://example.org/b
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ok:https://github.com/a:https://example.org/b" ]]
}

@test "G2r: --dest no distingue mayúsculas en resolve y run" {
  printf '%s' "valor-r-804" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" resolve pat-test --dest GitHub.COM
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-r-804" ]]
  run "$EGRESS" run --dest GITHUB.com bash -c 'echo "r:$(cat "$2")"' _ https://github.com/x savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "r:valor-r-804" ]]
}

@test "G2r: store KEY - EXTRA → rechazado y no se almacena" {
  run bash -c 'printf "%s" "valor-r-805" | "$EGRESS" store pat-test - extra'
  [[ "$status" -ne 0 ]]
  [[ ! -f "$SAVIA_CRED_STORE_DIR/keys.json" ]]
}

@test "G2r: LÍMITE conocido — con --dest autodeclarado el hijo recibe el valor y puede imprimirlo" {
  # Documenta que la comprobación de host es salvaguarda de enrutado, no barrera
  # frente a un llamante hostil. Si este test empieza a fallar, la garantía ha
  # cambiado: actualizar secret-redaction-policy.md § Límites.
  printf '%s' "valor-r-807" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'cat "$1"' _ savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-r-807" ]]
}

# ── T8: G2 fd — ni el secreto ni la clave del store pasan por argv ────────────
# Lo que va por argv queda en /proc/<pid>/cmdline y en ps, legible por
# cualquier proceso del sistema mientras dura.

_derived_key() {
  printf '%s|%s' "$(cat /etc/machine-id 2>/dev/null || hostname)" "$HOME" | sha256sum | cut -d' ' -f1
}

# Envuelve openssl y python3 para registrar el argv real (/proc/$$/cmdline) de
# cada invocación antes de delegar en el binario real.
_install_argv_shims() {
  SHIM_DIR="$SAVIA_CRED_STORE_DIR/shims"; ARGV_LOG="$SAVIA_CRED_STORE_DIR/argv.log"
  mkdir -p "$SHIM_DIR"; : >"$ARGV_LOG"
  local tool real
  for tool in openssl python3; do
    real=$(command -v "$tool")
    printf '#!/bin/bash\n{ tr "\\0" " " </proc/$$/cmdline; echo; } >>"%s"\nexec "%s" "$@"\n' \
      "$ARGV_LOG" "$real" >"$SHIM_DIR/$tool"
    chmod +x "$SHIM_DIR/$tool"
  done
  export PATH="$SHIM_DIR:$PATH"
}

@test "G2fd: run entrega el valor por /dev/fd/N y no aparece en el cmdline del hijo" {
  printf '%s' "valor-fd-901" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c \
    'printf "argv=%s\n" "$(tr "\0" " " </proc/$$/cmdline)"; printf "arg=%s\n" "$1"; printf "val=%s\n" "$(cat "$1")"' \
    _ savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "${lines[0]}" == argv=* && "${lines[0]}" != *"valor-fd-901"* ]]
  [[ "${lines[1]}" =~ ^arg=/dev/fd/[0-9]+$ ]]
  [[ "${lines[2]}" == "val=valor-fd-901" ]]
}

@test "G2fd: /proc/<pid>/cmdline del hijo y del propio run, vistos desde fuera, no contienen el valor" {
  printf '%s' "valor-fd-902" | "$EGRESS" store pat-test >/dev/null
  local pidf="$SAVIA_CRED_STORE_DIR/child.pid" outf="$SAVIA_CRED_STORE_DIR/out"
  "$EGRESS" run --dest github.com bash -c 'echo $$ >"$0"; sleep 2; cat "$1"' \
    "$pidf" savia:cred:pat-test >"$outf" 2>&1 &
  local runpid=$! i child=""
  for i in $(seq 1 50); do [[ -s "$pidf" ]] && break; sleep 0.1; done
  child=$(cat "$pidf")
  [[ -n "$child" && -r "/proc/$child/cmdline" ]]
  local c_child c_run
  c_child=$(tr '\0' ' ' <"/proc/$child/cmdline")
  c_run=$(tr '\0' ' ' <"/proc/$runpid/cmdline" 2>/dev/null || true)
  wait "$runpid"
  [[ "$c_child" == *"/dev/fd/"* ]]
  [[ "$c_child" != *"valor-fd-902"* ]]
  [[ "$c_run" != *"valor-fd-902"* ]]
  [[ "$(cat "$outf")" == "valor-fd-902" ]]
}

@test "G2fd: varios marcadores → un descriptor distinto por valor" {
  printf '%s' "valor-fd-a" | "$EGRESS" store k-a >/dev/null
  printf '%s' "valor-fd-b" | "$EGRESS" store k-b >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "$1 $2|$(cat "$1")|$(cat "$2")"' \
    _ savia:cred:k-a savia:cred:k-b
  [[ "$status" -eq 0 ]]
  local a="${output%% *}" rest="${output#* }"
  [[ "$a" != "${rest%%|*}" ]]
  [[ "$output" == *"|valor-fd-a|valor-fd-b" ]]
}

@test "G2fd: store y resolve no pasan la clave derivada ni el valor por argv a openssl/python3" {
  local key; key=$(_derived_key)
  _install_argv_shims
  printf '%s' "valor-fd-903" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-fd-903" ]]
  # Los shims se ejecutaron (si no, el test no prueba nada).
  grep -q 'openssl enc' "$ARGV_LOG"
  grep -q 'python3' "$ARGV_LOG"
  [[ "$(grep -cF "$key" "$ARGV_LOG")" -eq 0 ]]
  [[ "$(grep -cF "valor-fd-903" "$ARGV_LOG")" -eq 0 ]]
}

@test "G2fd: blob legado (iv:ciph:mac) se resuelve una vez y se migra a v2 sin clave en argv" {
  local key iv ciph mac
  key=$(_derived_key)
  iv=$(openssl rand -hex 16)
  ciph=$(printf '%s' "valor-fd-904" | openssl enc -aes-256-cbc -K "$key" -iv "$iv" -a -A)
  mac=$(printf '%s|%s' "$iv" "$ciph" | openssl dgst -sha256 -hmac "$key" -hex | awk '{print $NF}')
  printf '{"pat-test": "%s:%s:%s"}' "$iv" "$ciph" "$mac" >"$SAVIA_CRED_STORE_DIR/keys.json"
  chmod 600 "$SAVIA_CRED_STORE_DIR/keys.json"
  run "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"migrada"* && "${lines[-1]}" == "valor-fd-904" ]]
  python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["pat-test"]; sys.exit(0 if b.startswith("v2:") else 1)' \
    "$SAVIA_CRED_STORE_DIR/keys.json"
  [[ "$(stat -c %a "$SAVIA_CRED_STORE_DIR/keys.json")" == "600" ]]
  _install_argv_shims
  run "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-fd-904" ]]
  grep -q 'openssl enc' "$ARGV_LOG"
  [[ "$(grep -cF "$key" "$ARGV_LOG")" -eq 0 ]]
}

@test "G2fd: MAC manipulado (v2 y legado) → fallo y nada en stdout" {
  printf '%s' "valor-fd-905" | "$EGRESS" store pat-test >/dev/null
  python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); b=d["pat-test"]
d["pat-test"]=b[:-1]+("0" if b[-1]!="0" else "1"); json.dump(d,open(p,"w"))' \
    "$SAVIA_CRED_STORE_DIR/keys.json"
  run --separate-stderr "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -ne 0 ]]
  [[ -z "$output" ]]
  local key iv ciph
  key=$(_derived_key); iv=$(openssl rand -hex 16)
  ciph=$(printf '%s' "valor-fd-906" | openssl enc -aes-256-cbc -K "$key" -iv "$iv" -a -A)
  printf '{"pat-test": "%s:%s:%s"}' "$iv" "$ciph" "$(printf '0%.0s' $(seq 64))" \
    >"$SAVIA_CRED_STORE_DIR/keys.json"
  run --separate-stderr "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -ne 0 ]]
  [[ -z "$output" ]]
}

# ── S03q (SE-376): casos que discriminan mutantes supervivientes ─────────────

@test "S03q: allowlist sin sufijos — evilgithub.com y evil.github.com no autorizan" {
  printf '%s' "valor-suf-901" | "$EGRESS" store pat-test >/dev/null
  local d
  for d in evilgithub.com evil.github.com xdev.azure.com; do
    run "$EGRESS" resolve pat-test --dest "$d"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no autorizado. REFUSE"* ]]
    [[ "$output" != *"valor-suf-901"* ]]
  done
}

@test "S03q: run toma el host tras el último @ y sin puerto" {
  printf '%s' "valor-host-902" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "ok:$(cat "$2")"' _ https://a@b@github.com:443/x savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ok:valor-host-902" ]]
}

@test "S03q: run rechaza host con caracteres fuera de [a-z0-9.-] (invalid)" {
  printf '%s' "valor-host-903" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "$2"' _ https://git_hub.com/x savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"autoridad ambigua"* ]]
  [[ "$output" != *"valor-host-903"* ]]
}

@test "S03q: run con tres hosts distintos → REFUSE (no solo con dos)" {
  printf '%s' "valor-host-904" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "$4"' _ https://github.com/a https://dev.azure.com/b https://api.github.com/c savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"varios destinos"* ]]
}

@test "S03q: la misma URL repetida cuenta como un único destino" {
  printf '%s' "valor-host-905" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run bash -c 'echo "ok:$(cat "$3")"' _ https://github.com/a https://GitHub.com/b savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ok:valor-host-905" ]]
}

@test "S03q: run entrega el valor exacto por el descriptor, sin salto final (boundary)" {
  printf '%s' "abc" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'wc -c < "$1"' _ savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" -eq 3 ]]
}

@test "S03q: resolve de marcador missing dice «no registrado», no fallo de descifrado" {
  printf '%s' "valor-906" | "$EGRESS" store pat-otro >/dev/null
  run "$EGRESS" resolve pat-test --dest github.com
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"marcador 'pat-test' no registrado. REFUSE"* ]]
}

@test "S03q: --dest como último argumento sin valor → mensaje propio, no unbound" {
  printf '%s' "valor-907" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" resolve pat-test --dest
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--dest sin valor. REFUSE"* ]]
}

@test "S03q: status no vuelca los blobs cifrados" {
  printf '%s' "valor-908" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"  - pat-test"* ]]
  [[ "$output" != *"v2:"* ]]
}

@test "S03q: audit encuentra ghp_ de 36 en scripts/ y no los cortos ni los de tests/" {
  local root="$BATS_TEST_TMPDIR/aud"
  mkdir -p "$root/scripts" "$root/.claude/tests" "$root/scripts/tests"
  printf 'T=ghp_%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$root/scripts/leak.sh"
  printf 'T=ghp_short\n' > "$root/scripts/corto.sh"
  printf 'T=ghp_%s\n' "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" > "$root/scripts/tests/fx.sh"
  run "$EGRESS" audit "$root"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"scripts/leak.sh:1:"* ]]
  [[ "$output" != *"corto.sh"* ]]
  [[ "$output" != *"fx.sh"* ]]
}

@test "S03q: con --dest explícito, dos hosts en los args siguen siendo REFUSE" {
  printf '%s' "valor-host-909" | "$EGRESS" store pat-test >/dev/null
  run "$EGRESS" run --dest github.com bash -c 'echo "ok:$(cat "$3")"' _ https://github.com/a https://dev.azure.com/b savia:cred:pat-test
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"varios destinos"* ]]
  [[ "$output" != *"valor-host-909"* ]]
}
