#!/usr/bin/env bats
# test-se353-credential-egress.bats — BATS tests for SE-353 Sentinel Credential Substitution
# Ref: SE-353 — credenciales fuera del contexto del modelo, resolución solo en egress

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
  run "$EGRESS" run --dest github.com bash -c 'echo "recibido:$1"' _ savia:cred:pat-test
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
  run "$EGRESS" run bash -c 'echo "recibido:$2"' _ https://api.github.com/user savia:cred:pat-test
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
  run "$EGRESS" run --dest GITHUB.com bash -c 'echo "r:$2"' _ https://github.com/x savia:cred:pat-test
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
  run "$EGRESS" run --dest github.com bash -c 'echo "$1"' _ savia:cred:pat-test
  [[ "$status" -eq 0 ]]
  [[ "$output" == "valor-r-807" ]]
}
