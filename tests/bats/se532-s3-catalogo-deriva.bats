#!/usr/bin/env bats
# SE-532 S3 — aviso de deriva del catálogo de agentes en el ledger de Pulse (AC-10).
# La batería completa vive en projects/pulse/tests/test_catalogo.py y test_status.py (stdlib);
# aquí se ejecutan y se comprueba la CLI sobre el repositorio real con un estado temporal.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PULSE="$REPO_ROOT/projects/pulse/bin/pulse"

setup() {
  export PULSE_DATA_DIR="$BATS_TEST_TMPDIR/datos/pulse"
}

@test "batería unittest de la deriva del catálogo en verde" {
  run python3 -I "$REPO_ROOT/projects/pulse/tests/test_catalogo.py"
  [ "$status" -eq 0 ]
  run python3 -I "$REPO_ROOT/projects/pulse/tests/test_status.py"
  [ "$status" -eq 0 ]
}

@test "el repositorio real, con copias regeneradas, no emite nada" {
  run "$PULSE" catalogo --repo "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sin cambios"* ]]
  [ ! -s "$PULSE_DATA_DIR/eventos.jsonl" ]
}

@test "un repositorio sin catálogo falla y no anota nada" {
  run "$PULSE" catalogo --repo "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -ne 0 ]
  [ ! -s "$PULSE_DATA_DIR/eventos.jsonl" ]
}

@test "status sin comprobaciones dice sin datos, no sin deriva" {
  run "$PULSE" status
  [[ "$output" == *"Catálogo de agentes: sin datos"* ]]
  [[ "$output" != *"sin deriva"* ]]
}
