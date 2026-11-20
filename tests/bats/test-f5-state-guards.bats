#!/usr/bin/env bats
# Guards de entrada de scripts/f5-state.sh (contrato vivo de reservas de pr.merge en la puerta de fusión).
# Rescatados de las pruebas review y safety del libro de efectos (SE-493) al retirarlo (PR #1581):
# eran la única cobertura de regresión del guard de recorrido de rutas y del guard de operación.
# Cada caso negativo lleva su control positivo y aísla SAVIA_RESERVATIONS en un tmpdir.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  F5="$REPO_DIR/scripts/f5-state.sh"
  R="$BATS_TEST_TMPDIR/res"
  mkdir -p "$R/sub"
  # gh falso: ningún caso debe depender de la red ni del repo real.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\necho OPEN\n' > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "f5-state.sh rechaza claves con recorrido de rutas (2) sin crear nada fuera" {
  for k in '../7' '../fuera' 'abc' '' '07' '7/../8'; do
    SAVIA_RESERVATIONS="$R/sub" run bash "$F5" reserve pr.merge "$k"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no es un número de PR"* ]]
  done
  [ -z "$(ls -A "$R/sub")" ]
  [ -z "$(find "$R" -maxdepth 1 -type f)" ]
}

@test "f5-state.sh: el guard de clave cubre todos los subcomandos que escriben o leen la reserva" {
  for c in reserve mark_submitted close release status; do
    SAVIA_RESERVATIONS="$R/sub" run bash "$F5" "$c" pr.merge '../7'
    [ "$status" -eq 2 ]
  done
  [ -z "$(ls -A "$R/sub")" ]
}

@test "f5-state.sh: control positivo, una clave válida reserva dentro del directorio" {
  SAVIA_RESERVATIONS="$R/sub" run bash "$F5" reserve pr.merge 42
  [ "$status" -eq 0 ]
  [ -f "$R/sub/pr.merge__42.json" ]
}

@test "f5-state.sh rechaza una op distinta de pr.merge sin crear reserva" {
  SAVIA_RESERVATIONS="$R/sub" run bash "$F5" reserve publish.report 7
  [ "$status" -eq 2 ]
  [[ "$output" == *"no admitida"* ]]
  [ -z "$(ls -A "$R/sub")" ]
  # Control positivo: la misma clave con pr.merge sí reserva.
  SAVIA_RESERVATIONS="$R/sub" run bash "$F5" reserve pr.merge 7
  [ "$status" -eq 0 ]
  [ -f "$R/sub/pr.merge__7.json" ]
}
