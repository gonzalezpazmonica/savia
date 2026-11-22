#!/usr/bin/env bats
# SE-498 F0 — PENDIENTE DE LA OPERADORA (hallazgo P1-1 de la refutación de #1593).
# Fuera de la suite normal a propósito: scripts/risk-tier.py no lo pueden editar los agentes.
# Activar tras aplicar el cambio propuesto en el comentario de la PR #1593:
#   bats tests/operator-pending/test-risk-tier-savia-control.bats
# Después de aplicarlo, mover este fichero a tests/ y añadirlo al paso "Plano de control" de ci.yml.
# Falla mientras el código y las suites del freno sigan en tier 2.

tier() { python3 -I "$BATS_TEST_DIRNAME/../../scripts/risk-tier.py" --diff "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tier"])'; }

@test "el código del freno es tier 4" {
  [ "$(tier scripts/savia-control.py)" = 4 ]
}

@test "las suites del freno son tier 4" {
  for f in tests/test-savia-control-state.bats tests/test-savia-control-resume.bats tests/test-control-epoch-monotonic.bats \
           tests/fixtures/savia-control/setup.bash; do
    [ "$(tier "$f")" = 4 ]
  done
}

@test "negativo: un script vecino sigue sin ser tier 4" {
  [ "$(tier scripts/savia-control-notes.py)" != 4 ]
}
