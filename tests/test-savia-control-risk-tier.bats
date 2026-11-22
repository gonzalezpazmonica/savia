#!/usr/bin/env bats
# SE-498 F0 — hallazgo P1-1 de la refutación de #1593: el código del freno, sus suites y la del check
# de época obligatorio son tier 4 en scripts/risk-tier.py. Lo aplicó la operadora en main (#1630);
# este test impide que una PR lo revierta sin que se note. Antes estaba en tests/operator-pending/.

tier() { python3 -I "$BATS_TEST_DIRNAME/../scripts/risk-tier.py" --diff "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tier"])'; }

@test "el código del freno es tier 4" {
  [ "$(tier scripts/savia-control.py)" = 4 ]
}

@test "las suites del freno y las del check de época son tier 4" {
  for f in tests/test-savia-control-state.bats tests/test-savia-control-resume.bats \
           tests/test-savia-control-risk-tier.bats tests/test-control-epoch-monotonic.bats \
           tests/test-control-epoch-ci.bats tests/fixtures/savia-control/setup.bash; do
    echo "$f"; [ "$(tier "$f")" = 4 ]
  done
}

@test "negativo: un script o una suite vecinos fuera del freno siguen sin ser tier 4" {
  # La operadora eligió prefijos (scripts/savia-control*, tests/test-control-epoch*): el límite está fuera de ellos.
  [ "$(tier scripts/savia-status.py)" != 4 ]
  [ "$(tier tests/test-control-plane.bats)" != 4 ]
  # Justo por debajo de cada prefijo (le falta el último carácter): fuera.
  for f in scripts/savia-contro.py tests/test-savia-contro.bats tests/test-control-epoc.bats \
           tests/fixtures/savia-contro/setup.bash config/contro/x.json; do
    echo "$f"; [ "$(tier "$f")" != 4 ]
  done
}

@test "límite: los prefijos son prefijos literales; un nombre que los continúa también es tier 4" {
  # Decisión de la operadora (#1630): prefijos, no nombres exactos. Proteger de más es fail-closed.
  for f in scripts/savia-controller.py tests/test-control-epochs-x.bats tests/test-savia-control-x.bats; do
    echo "$f"; [ "$(tier "$f")" = 4 ]
  done
}
