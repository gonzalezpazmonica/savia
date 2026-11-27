#!/usr/bin/env bats
# SE-468 AC5: el detector de vacuidad (SE-456, scripts/test-auditor-engine.py) solo recorre
# tests/**/*.bats y no cubre workflows; el gate «Evals CI Gate» debe constar como cobertura
# no verificada (SE-444) en validate-ci-local.sh, sin afirmar que sea vacuo ni que no lo sea.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  REG="$ROOT/scripts/lib/unverified-gates.tsv"
}

@test "el registro de gates no verificados existe y lista Evals CI Gate con su spec" {
  [ -f "$REG" ]
  run awk -F'\t' '$2 == "Evals CI Gate" && $3 == "SE-468" {print $1}' "$REG"
  [ "$status" -eq 0 ]
  [ "$output" = ".github/workflows/evals-ci.yaml" ]
}

@test "cada entrada del registro apunta a un workflow que existe y se llama así (no se pudre)" {
  n=0
  while IFS=$'\t' read -r wf name spec reason; do
    [[ -z "$wf" || "$wf" == \#* ]] && continue
    n=$((n+1))
    [ -f "$ROOT/$wf" ]
    grep -qx "name: $name" "$ROOT/$wf"
    [[ "$spec" =~ ^SE-[0-9]+$ ]]
    [ -n "$reason" ]
  done < "$REG"
  [ "$n" -ge 1 ]
}

@test "el detector de vacuidad sigue sin cubrir workflows: si los cubre, el registro debe revisarse" {
  # Si esto falla, test-auditor-engine.py ya recorre workflows: aplicar la primera rama de AC5
  # (clasificar gate antiguo y nuevo) y retirar la entrada del registro.
  run grep -nE '\.github|workflows|\.ya?ml' "$ROOT/scripts/test-auditor-engine.py"
  [ "$status" -ne 0 ]
}

@test "validate-ci-local informa del gate no verificado sin cambiar el código de salida" {
  cd "$ROOT"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' bash scripts/validate-ci-local.sh --quick
  code_with=$status
  [[ "$output" == *"Evals CI Gate (.github/workflows/evals-ci.yaml, SE-468): detector de vacuidad no lo cubre"* ]]
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_AUTHORITY_REPORT=off bash scripts/validate-ci-local.sh --quick
  [[ "$output" != *"Evals CI Gate"* ]]
  [ "$status" -eq "$code_with" ]
}

@test "un registro vacío no imprime gates y tampoco cambia la salida" {
  cd "$ROOT"
  : > "$BATS_TEST_TMPDIR/empty.tsv"
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' bash scripts/validate-ci-local.sh --quick
  base=$status
  run env SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_UNVERIFIED_GATES_FOR_TESTS="$BATS_TEST_TMPDIR/empty.tsv" bash scripts/validate-ci-local.sh --quick
  [[ "$output" != *"detector de vacuidad no lo cubre"* ]]
  [ "$status" -eq "$base" ]
}
