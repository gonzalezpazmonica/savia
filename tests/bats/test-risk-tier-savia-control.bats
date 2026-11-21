#!/usr/bin/env bats
# SE-498 F0 / hallazgo P1-1 de #1593: las suites del freno de emergencia son gobernanza (tier 4).
# Sin esto, una PR podía debilitar los tests del freno (tier 2) sin revisión humana, aunque
# scripts/savia-control* ya fuese tier 4 (#1614).
# Vive en tests/bats/ como test-se362-risk-tier.bats: ci-select-bats lo elige en CI.
# TIER_SCRIPT permite apuntar a otra copia del clasificador (p. ej. la de main) para comprobar que el test falla.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TIER_SCRIPT="${TIER_SCRIPT:-$REPO_ROOT/scripts/risk-tier.py}"
  export TIER_SCRIPT
}

tier() { python3 -I "$TIER_SCRIPT" --diff "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tier"])'; }

@test "el código del freno es tier 4" {
  [ "$(tier scripts/savia-control.py)" = 4 ]
}

@test "las suites del freno son tier 4" {
  for f in tests/test-savia-control-state.bats tests/test-savia-control-resume.bats \
           tests/test-savia-control-epoch.bats tests/test-savia-control-reconcile.bats \
           tests/test-savia-control-refutacion.bats tests/test-savia-control-scopes.bats \
           tests/test-control-epoch-monotonic.bats tests/test-control-epoch-ci.bats; do
    run tier "$f"
    [ "$output" = 4 ] || { echo "$f -> tier $output"; return 1; }
  done
}

@test "los fixtures del freno son tier 4" {
  for f in tests/fixtures/savia-control/setup.bash tests/fixtures/savia-control/gh-stub.py; do
    run tier "$f"
    [ "$output" = 4 ] || { echo "$f -> tier $output"; return 1; }
  done
}

@test "un cambio mixto que toca una suite del freno es tier 4" {
  [ "$(tier "docs/foo.md tests/test-savia-control-resume.bats")" = 4 ]
}

@test "negativo: suites y fixtures vecinos no suben a tier 4" {
  for f in tests/test-savia-status.bats tests/test-l13-meta-control.bats tests/fixtures/other/setup.bash; do
    run tier "$f"
    [ "$output" != 4 ] || { echo "$f -> tier 4"; return 1; }
  done
}
