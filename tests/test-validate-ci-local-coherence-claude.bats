#!/usr/bin/env bats
# Tests de Claude (segundo proveedor, TDD cruzado): check_coherence falla cerrado.
# Complementan los de Codex (test-validate-ci-local-coherence.bats): varias líneas
# BLOCK, puerta ausente, código de salida en el mensaje, falsos positivos y
# regresión del contador WARN.
# Ref: scripts/validate-ci-local.sh (check_coherence) y scripts/coherence-gates.sh
set -uo pipefail

SCRIPT="scripts/validate-ci-local.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$(mktemp -d "$BATS_TEST_TMPDIR/coherence-claude.XXXXXX")"
  FIXTURE="$T/repo"
  mkdir -p "$FIXTURE/scripts/lib" "$FIXTURE/.claude/hooks/lib" "$T/no-lockfiles"
  cp "$REPO_ROOT/$SCRIPT" "$FIXTURE/$SCRIPT"
  cp "$REPO_ROOT/scripts/lib/mock-env.sh" "$FIXTURE/scripts/lib/"

  source "$FIXTURE/scripts/lib/mock-env.sh"
  git_env_clean --isolate-config
  git -C "$FIXTURE" init -q -b agent/coherence-tests
  git -C "$FIXTURE" commit -q --allow-empty -m fixture

  # Las demás puertas están sanas: un FAIL solo puede venir de coherencia.
  printf '{}\n' > "$FIXTURE/.claude/settings.json"
  printf '# Changelog\n\n## [1.0.0]\n' > "$FIXTURE/CHANGELOG.md"
  touch "$FIXTURE/LICENSE" "$FIXTURE/README.md" "$FIXTURE/CONTRIBUTING.md" \
    "$FIXTURE/CODE_OF_CONDUCT.md" "$FIXTURE/SECURITY.md"
  printf 'raise SystemExit(0)\n' > "$FIXTURE/scripts/validate-agent-catalog.py"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/.claude/hooks/lib/gate-result.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE/scripts/vaults-freshness.sh"
  cat > "$FIXTURE/scripts/coherence-gates.sh" <<'SH'
#!/usr/bin/env bash
cat "$COHERENCE_STDOUT"
exit "$COHERENCE_EXIT"
SH
  export COHERENCE_STDOUT="$T/stdout" COHERENCE_EXIT=0
  : > "$COHERENCE_STDOUT"
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

# Una única fila de coherencia, con el veredicto esperado.
assert_coherence_result() {
  local label="$1"
  [ "$(grep -cE '^[[:space:]]*(OK|FAIL|WARN) Coherence([[:space:]:]|$)' <<< "$output")" -eq 1 ]
  grep -qE "^[[:space:]]*$label Coherence([[:space:]:]|$)" <<< "$output"
}

fail_line() { grep -E '^[[:space:]]*FAIL Coherence([[:space:]:]|$)' <<< "$output"; }

@test "varios BLOCK: el mensaje FAIL nombra todas las puertas en una sola línea" {
  printf 'BLOCK coherence/entropy: a\nPASS coherence/x\nBLOCK coherence/debt-budget: b\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  [ "$(fail_line | wc -l)" -eq 1 ]
  [[ "$(fail_line)" == *"coherence/entropy: a"* ]]
  [[ "$(fail_line)" == *"coherence/debt-budget: b"* ]]
}

@test "coherence-gates.sh ausente falla cerrado (127), no PASS" {
  mv "$FIXTURE/scripts/coherence-gates.sh" "$T/apartado.sh"
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  [[ "$(fail_line)" == *"127"* ]]
}

@test "solo la línea resumen BLOCK con exit 1 falla y menciona el código" {
  printf -- '-- coherence gates: BLOCK (L4 graduado)\n' > "$COHERENCE_STDOUT"
  COHERENCE_EXIT=1
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  [[ "$(fail_line)" == *"código 1"* ]]
  [[ "$(fail_line)" == *"coherence gates: BLOCK"* ]]
}

@test "exit no cero con solo líneas en blanco falla cerrado" {
  printf '\n\n' > "$COHERENCE_STDOUT"
  COHERENCE_EXIT=3
  run_validation --quick
  [ "$status" -ne 0 ]
  assert_coherence_result FAIL
  [[ "$(fail_line)" == *"código 3"* ]]
}

@test "la palabra BLOCK en mitad de un texto sin 'coherence' ni prefijo no bloquea" {
  printf 'PASS coherence/x: el modo BLOCK está documentado\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -eq 0 ]
  assert_coherence_result OK
}

@test "el contador de WARN se conserva en el mensaje advisory" {
  printf 'WARN coherence/a\nWARN coherence/b\nWARN coherence/c\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -eq 0 ]
  assert_coherence_result WARN
  [[ "$output" == *"3 gate(s) en advisory"* ]]
}

@test "un FAIL de coherencia sale en el bloque BLOCKED y no dice safe to push" {
  printf 'BLOCK coherence/entropy: límite\n' > "$COHERENCE_STDOUT"
  run_validation --quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"BLOCKED:"* ]]
  [[ "$output" != *"safe to push"* ]]
}
