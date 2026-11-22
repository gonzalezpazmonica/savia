#!/usr/bin/env bats
# Contrato coherence-block-tests (2026-11-21): check_coherence falla cerrado.
# Ref: scripts/validate-ci-local.sh y scripts/coherence-gates.sh
# Estrategia: ejecutar la CLI completa en un repositorio temporal; copiar el script
# real y sustituir solo sus dependencias. BLOCK/error => FAIL, WARN => advisory,
# salida 0 sin marcadores => PASS (la CLI lo presenta como OK).
# TDD cruzado: los casos BLOCK/error deben fallar antes de la corrección externa.
set -uo pipefail

SCRIPT="scripts/validate-ci-local.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$(mktemp -d "$BATS_TEST_TMPDIR/coherence.XXXXXX")"
  FIXTURE="$T/repo"
  mkdir -p "$FIXTURE/scripts/lib" "$FIXTURE/.claude/hooks/lib" "$T/no-lockfiles"
  cp "$REPO_ROOT/$SCRIPT" "$FIXTURE/$SCRIPT"
  cp "$REPO_ROOT/scripts/lib/mock-env.sh" "$FIXTURE/scripts/lib/"

  # Aislar Git antes de crear el repositorio: nunca heredar el índice del agente.
  source "$FIXTURE/scripts/lib/mock-env.sh"
  git_env_clean --isolate-config
  git -C "$FIXTURE" init -q -b agent/coherence-tests
  git -C "$FIXTURE" commit -q --allow-empty -m fixture

  # Las otras puertas están sanas; un FAIL solo puede proceder de coherencia.
  printf '{}\n' > "$FIXTURE/.claude/settings.json"
  printf '# Changelog\n\n## [1.0.0]\n' > "$FIXTURE/CHANGELOG.md"
  touch "$FIXTURE/LICENSE" "$FIXTURE/README.md" "$FIXTURE/CONTRIBUTING.md" \
    "$FIXTURE/CODE_OF_CONDUCT.md" "$FIXTURE/SECURITY.md"
  printf 'raise SystemExit(0)\n' > "$FIXTURE/scripts/validate-agent-catalog.py"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/.claude/hooks/lib/gate-result.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/scripts/vaults-freshness.sh"
  cat > "$FIXTURE/scripts/coherence-gates.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
cat "$COHERENCE_STDOUT"
cat "$COHERENCE_STDERR" >&2
exit "$COHERENCE_EXIT"
SH
  export COHERENCE_STDOUT="$T/stdout" COHERENCE_STDERR="$T/stderr" COHERENCE_EXIT=0
  : > "$COHERENCE_STDOUT"
  : > "$COHERENCE_STDERR"
  export BATS_VERSION
  export SAVIA_FRESH_CHECKS_FOR_TESTS='fixture|true|sin regeneración'
  export SAVIA_LOCK_DIRS_FOR_TESTS="$T/no-lockfiles" SAVIA_AUTHORITY_REPORT=off
  cd "$FIXTURE"
}

teardown() {
  rm -rf "$T"
}

run_validation() {
  run bash "$FIXTURE/$SCRIPT" "$@"
}

assert_coherence_result() {
  local label="$1"
  # Una única fila: evita aceptar FAIL junto a un falso PASS/WARN de coherencia.
  [ "$(grep -cE '^[[:space:]]*(OK|FAIL|WARN) Coherence([[:space:]:]|$)' <<< "$output")" -eq 1 ]
  grep -qE "^[[:space:]]*$label Coherence([[:space:]:]|$)" <<< "$output"
}

@test "BLOCK coherence con exit zero produce FAIL y bloquea la CLI" {
  printf 'BLOCK coherence/entropy: límite superado\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "BLOCK al principio de línea sin la palabra coherence también produce FAIL" {
  printf 'BLOCK negative-safety: aserción incumplida\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "BLOCK coherence dentro de una línea produce FAIL aunque no sea un prefijo" {
  printf 'diagnóstico: BLOCK coherence/debt-budget: presupuesto agotado\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "BLOCK con exit no cero produce FAIL también sin quick" {
  printf 'BLOCK coherence/negative-safety: gate bloqueante\n' > "$COHERENCE_STDOUT"
  COHERENCE_EXIT=7
  run_validation
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "FAIL prevalece cuando WARN precede a BLOCK" {
  printf 'WARN coherence/chaos-suite\nBLOCK coherence/entropy: límite\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "FAIL prevalece cuando BLOCK precede a WARN" {
  printf 'BLOCK coherence/entropy: límite\nWARN coherence/chaos-suite\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "error con salida empty y exit no cero falla cerrado" {
  COHERENCE_EXIT=23
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "error no reconocible por stderr y exit no cero produce FAIL" {
  printf 'no se pudo leer la política\n' > "$COHERENCE_STDERR"
  COHERENCE_EXIT=2
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "error de ejecución no se degrada a WARN aunque haya aviso reconocible" {
  printf 'WARN coherence/chaos-suite: advisory\n' > "$COHERENCE_STDOUT"
  COHERENCE_EXIT=9
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "error de ejecución no se convierte en PASS aunque la salida diga PASS" {
  printf 'PASS coherence/entropy\n' > "$COHERENCE_STDOUT"
  COHERENCE_EXIT=1
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
}

@test "solo WARN con salida cero sigue siendo advisory y permite terminar" {
  printf 'WARN coherence/chaos-suite: advisory\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -eq 0 ]
  assert_coherence_result WARN
}

@test "varios avisos con salida cero conservan WARN sin bloquear" {
  printf 'WARN coherence/chaos-suite\nWARN coherence/debt-budget\n' > "$COHERENCE_STDOUT"
  run_validation
  [ "$status" -eq 0 ]
  assert_coherence_result WARN
}

@test "todo correcto con salida cero produce PASS presentado como OK" {
  printf 'PASS coherence/negative-safety\nPASS coherence/entropy\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -eq 0 ]
  assert_coherence_result OK
}

@test "salida empty con exit zero y sin WARN ni BLOCK produce PASS" {
  run_validation --quick
  [ "$status" -eq 0 ]
  assert_coherence_result OK
}

@test "texto informativo sin marcadores y salida cero permite PASS" {
  printf 'comprobación terminada\n' > "$COHERENCE_STDOUT"
  run_validation
  [ "$status" -eq 0 ]
  assert_coherence_result OK
}

@test "el mensaje FAIL contiene la línea BLOCK y nombra la puerta bloqueante" {
  local block='BLOCK coherence/eval-coverage-L4: capability L4 perdió cobertura (0/3)'
  printf 'PASS coherence/entropy\n%s\nWARN coherence/chaos-suite\n' "$block" > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  local failure
  failure="$(grep -E '^[[:space:]]*FAIL Coherence([[:space:]:]|$)' <<< "$output")"
  [[ "$failure" == *"$block"* ]]
}

@test "BLOCK enviado por stderr también produce FAIL con el nombre de la puerta" {
  local block='BLOCK coherence/constitutional-contracts: contrato inválido'
  printf '%s\n' "$block" > "$COHERENCE_STDERR"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  local failure
  failure="$(grep -E '^[[:space:]]*FAIL Coherence([[:space:]:]|$)' <<< "$output")"
  [[ "$failure" == *"$block"* ]]
}
