#!/usr/bin/env bats
# Ref: docs/propuestas/SPEC-032-security-benchmarks.md
# Tests for security-scan.sh — Security audit

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/security-scan.sh"
  TMPDIR_SS=$(mktemp -d)
}

teardown() { rm -rf "$TMPDIR_SS"; }

@test "script has safety flags" {
  head -10 "$SCRIPT" | grep -qE "set -[eu]o pipefail"
}

@test "ci mode runs and produces output" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --ci
  [[ "$output" == *"Results"* ]] || [[ "$output" == *"vulnerabilit"* ]] || [[ "$output" == *"scan"* ]]
}

@test "summary mode runs" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --summary
  [[ "$status" -le 1 ]]
}

@test "verbose mode runs" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --verbose
  [[ "$status" -le 1 ]]
}

@test "negative: handles nonexistent workspace" {
  cd "$TMPDIR_SS"
  run bash "$SCRIPT" --ci
  [[ "$status" -le 1 ]]
}

@test "edge: detects hardcoded paths pattern" {
  grep -q "hardcoded\|Hardcoded\|home" "$SCRIPT"
}

@test "coverage: checks for credentials" {
  grep -q "credential\|secret\|AKIA\|ghp_\|password" "$SCRIPT"
}

@test "coverage: vulnerability detection logic" {
  grep -q "vuln\|VULN\|Results\|findings" "$SCRIPT"
}

@test "negative: invalid mode handled" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --bogus
  [[ "$status" -le 1 ]]
}

@test "edge: scan produces structured output" {
  cd "$REPO_ROOT"
  run bash "$SCRIPT" --ci
  [[ "$output" == *"---"* ]] || [[ "$output" == *"Checking"* ]]
}

@test "coverage: checks credential patterns" {
  grep -q "Credential\|credential\|Hardcoded\|hardcoded" "$SCRIPT"
}

@test "coverage: MODE variable defined" {
  grep -q "MODE=" "$SCRIPT"
}

# ── S03k: comportamiento de security-scan.sh sobre un árbol sintético ──
# Cada comprobación se ejercita con un fichero que la dispara y con uno
# parecido que no debe dispararla.

mk_ws() {
  FX="$TMPDIR_SS/ws"
  mkdir -p "$FX/.claude/hooks/lib" "$FX/.opencode/hooks" "$FX/tests/hooks" "$FX/src"
  # enlace simbólico: grep -r no lo sigue, así el escáner no se lee a sí mismo
  # (su propia línea con la URL de Azure DevOps contaría como aviso)
  ln -s "$REPO_ROOT/scripts" "$FX/scripts"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$FX/.claude/hooks/lib/"
  echo "# seguridad" > "$FX/SECURITY.md"
  for h in block-credential-leak block-force-push block-infra-destructive; do
    echo "#!/usr/bin/env bash" > "$FX/.opencode/hooks/$h.sh"
    echo "# test" > "$FX/tests/hooks/test-$h.bats"
  done
  printf '.env\n*.pem\n*.key\ncredentials\nsecrets\n' > "$FX/.gitignore"
  S="$FX/scripts/security-scan.sh"
}

# Los patrones sensibles se montan en tiempo de ejecución: ningún literal
# del fichero coincide con ellos.
awskey() { printf 'key=AKI%s' 'AABCDEFGHIJKLMNOP'; }
privkey() { printf -- '-----BEGIN %s%s%s\n' "${1:-RSA }" "PRIV" "ATE KEY-----"; }

scan() { (cd "$FX" && bash "$S" "$@"); }

@test "S03k scan: árbol limpio con --ci sale 0, 0 hallazgos y gate-result clean" {
  mk_ws
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Results: 0 findings, 0 warnings"* ]]
  [[ "$output" == *"PASS: No critical security findings"* ]]
  [[ "${lines[-1]}" == 'gate-result: {"result":"clean","gaps":[]}' ]]
}

@test "S03k scan: clave AWS en src/ es hallazgo y --ci sale 1" {
  mk_ws
  awskey > "$FX/src/cfg.sh"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"AWS access key pattern"* ]]
  [[ "$output" == *"FAIL: 1 security findings"* ]]
  [[ "${lines[-1]}" == *'"result":"findings"'* ]]
}

@test "S03k scan: sin --ci un hallazgo no cambia el código de salida (0)" {
  mk_ws
  awskey > "$FX/src/cfg.sh"
  run scan --summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"Results: 1 findings"* ]]
}

@test "S03k scan: clave AWS con EXAMPLE o en tests/ no cuenta" {
  mk_ws
  echo "$(awskey) # EXAMPLE" > "$FX/src/cfg.sh"
  mkdir -p "$FX/tests"
  awskey > "$FX/tests/dato.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" != *"AWS access key pattern"* ]]
}

@test "S03k scan: contraseña literal de 8+ caracteres es hallazgo" {
  mk_ws
  echo 'password="Sup3rSecreta99"' > "$FX/src/app.sh"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hardcoded password pattern found"* ]]
}

@test "S03k scan: contraseña corta o de ejemplo no es hallazgo" {
  mk_ws
  printf 'password="corta"\npassword="example-password-1"\n' > "$FX/src/app.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" != *"Hardcoded password"* ]]
}

@test "S03k scan: la contraseña en un fichero md no se mira (solo sh y json)" {
  mk_ws
  echo 'password="Sup3rSecreta99"' > "$FX/src/notas.md"
  run scan --ci
  [[ "$output" != *"Hardcoded password"* ]]
}

@test "S03k scan: clave privada en un .pem es hallazgo; bajo docs/ se ignora" {
  mk_ws
  privkey > "$FX/src/id.pem"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Private key found in repository"* ]]
  unlink "$FX/src/id.pem"
  mkdir -p "$FX/docs"
  privkey > "$FX/docs/ejemplo.sh"
  run scan --ci
  [ "$status" -eq 0 ]
}

@test "S03k scan: la variante OPENSSH de clave privada también se detecta" {
  mk_ws
  privkey "OPENSSH " > "$FX/src/k.key"
  run scan --ci
  [[ "$output" == *"Private key found"* ]]
}

@test "S03k scan: token base64 largo avisa pero no bloquea" {
  mk_ws
  echo "tok=$(printf 'Ab1/%.0s' $(seq 1 14))" > "$FX/src/t.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Potential base64 token pattern found"* ]]
  [[ "$output" == *"Results: 0 findings, 1 warnings"* ]]
}

@test "S03k scan: token largo en línea con 'mock' no avisa" {
  mk_ws
  echo "mock tok=$(printf 'Ab1/%.0s' $(seq 1 14))" > "$FX/src/t.sh"
  run scan --ci
  [[ "$output" != *"Potential base64"* ]]
}

@test "S03k scan: URL de dev.azure.com real avisa; con TU-ORGANIZACION no" {
  mk_ws
  echo 'https://dev.azure.com/acmecorp/proj' > "$FX/src/u.sh"
  run scan --ci
  [[ "$output" == *"Real Azure DevOps org URL may be present"* ]]
  echo 'https://dev.azure.com/TU-ORGANIZACION/proj' > "$FX/src/u.sh"
  run scan --ci
  [[ "$output" != *"Azure DevOps org URL"* ]]
}

@test "S03k scan: falta SECURITY.md es hallazgo" {
  mk_ws
  unlink "$FX/SECURITY.md"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing SECURITY.md"* ]]
}

@test "S03k scan: cada hook de seguridad ausente es un hallazgo propio" {
  mk_ws
  unlink "$FX/.opencode/hooks/block-force-push.sh"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing force push hook"* ]]
  [[ "$output" != *"Missing credential leak hook"* ]]
  [[ "$output" == *"Results: 1 findings"* ]]
}

@test "S03k scan: hook sin test BATS avisa y con test no" {
  mk_ws
  echo "#!/usr/bin/env bash" > "$FX/.opencode/hooks/otro-hook.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook otro-hook has no BATS tests"* ]]
  [[ "$output" != *"Hook block-force-push has no BATS tests"* ]]
}

@test "S03k scan: .gitignore sin un patrón avisa con el nombre del patrón" {
  mk_ws
  printf '.env\n*.pem\ncredentials\nsecrets\n' > "$FX/.gitignore"
  run scan --ci
  [[ "$output" == *".gitignore missing pattern: *.key"* ]]
  [[ "$output" != *"missing pattern: .env"* ]]
}

@test "S03k scan: sin .gitignore es hallazgo" {
  mk_ws
  unlink "$FX/.gitignore"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"No .gitignore file found"* ]]
}

@test "S03k scan: --verbose imprime los PASS y los demás modos no" {
  mk_ws
  run scan --verbose
  [[ "$output" == *"PASS: SECURITY.md exists"* ]]
  run scan --summary
  [[ "$output" != *"PASS: SECURITY.md exists"* ]]
}

@test "S03k scan: un directorio ilegible deja el resultado en unknown, aviso y registro" {
  [ "$(id -u)" -ne 0 ] || skip "root lee cualquier directorio"
  mk_ws
  mkdir "$FX/src/cerrado"
  chmod 000 "$FX/src/cerrado"
  run scan --ci
  chmod 755 "$FX/src/cerrado"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: scan incompleto"* ]]
  [[ "${lines[-1]}" == *'"result":"unknown"'*'"reason":"unreadable"'* ]]
  grep -q '"hook":"security-scan","reason":"unreadable"' "$FX/output/unmeasured-gates.jsonl"
}

@test "S03k scan: unknown con SAVIA_GATE_UNKNOWN=block falla con exit 1" {
  [ "$(id -u)" -ne 0 ] || skip "root lee cualquier directorio"
  mk_ws
  mkdir "$FX/src/cerrado"
  chmod 000 "$FX/src/cerrado"
  SAVIA_GATE_UNKNOWN=block run scan --ci
  chmod 755 "$FX/src/cerrado"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: scan incompleto"* ]]
}

@test "S03k scan: un hallazgo gana sobre unknown" {
  [ "$(id -u)" -ne 0 ] || skip "root lee cualquier directorio"
  mk_ws
  mkdir "$FX/src/cerrado"
  chmod 000 "$FX/src/cerrado"
  awskey > "$FX/src/cfg.sh"
  run scan --ci
  chmod 755 "$FX/src/cerrado"
  [ "$status" -eq 1 ]
  [[ "${lines[-1]}" == *'"result":"findings"'* ]]
}

@test "S03k scan: el recuento de hallazgos suma uno por problema" {
  mk_ws
  unlink "$FX/SECURITY.md"
  awskey > "$FX/src/cfg.sh"
  run scan --ci
  [[ "$output" == *"Results: 2 findings"* ]]
  [[ "$output" == *"FAIL: 2 security findings"* ]]
}

@test "S03k scan: la contraseña de exactamente 8 caracteres cuenta; la de 7 no" {
  mk_ws
  echo 'password="abcdefg"' > "$FX/src/app.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  echo 'password="abcdefgh"' > "$FX/src/app.sh"
  run scan --ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hardcoded password pattern found"* ]]
}

@test "S03k scan: una clave AWS en un fichero test-*.sh bajo src/ se tolera" {
  mk_ws
  awskey > "$FX/src/test-claves.sh"
  run scan --ci
  [ "$status" -eq 0 ]
  [[ "$output" != *"AWS access key pattern"* ]]
}
