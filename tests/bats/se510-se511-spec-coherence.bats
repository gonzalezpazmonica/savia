#!/usr/bin/env bats
# SE-510 / SE-511 — coherencia interna de las specs (revisión de la PR #1482).
# Ref: docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md
# Ref: docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md
# Comprobador: tests/se510_se511_spec_check.py. Cada regla tiene caso positivo
# (la spec real pasa) y caso negativo (una copia mutada falla con su motivo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC510="$REPO_ROOT/docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md"
SPEC511="$REPO_ROOT/docs/specs/SE-511-contexto-fijo-por-turno-a-la-mitad.spec.md"
CHECK="$REPO_ROOT/tests/se510_se511_spec_check.py"

setup() {
  set -uo pipefail
  M510="$BATS_TEST_TMPDIR/se510.md"
  M511="$BATS_TEST_TMPDIR/se511.md"
  cp "$SPEC510" "$M510"
  cp "$SPEC511" "$M511"
}

check() { python3 -I "$CHECK" "$1"; }

@test "SE-510 real: coherente" {
  run check "$SPEC510"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "SE-511 real: coherente" {
  run check "$SPEC511"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "uso: sin argumentos sale 2" {
  run python3 -I "$CHECK"
  [ "$status" -eq 2 ]
}

@test "fichero inexistente: sale 2, nunca 0" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -eq 2 ]
}

@test "spec desconocida: sale 2, nunca 0" {
  printf '# SE-999 — otra\n' > "$BATS_TEST_TMPDIR/otra.md"
  run check "$BATS_TEST_TMPDIR/otra.md"
  [ "$status" -eq 2 ]
}

@test "R-SEED (P1-1): F4 como ALLOW con la misma entrada que B4 se detecta" {
  sed -i 's/^| B4 | BLOCK | \(.*\) | — |$/| B4 | BLOCK | \1 | — |\n| F4 | ALLOW | \1 | B4 |/' "$M510"
  grep -q '^| F4 | ALLOW |' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: la misma entrada es BLOCK en B4 y ALLOW en F4"* ]]
}

@test "R-SEED (P1-1): AC-1 que exige F4 en el corpus ALLOW se detecta" {
  sed -i '/^| AC-1 |/s/F1a, F1b, F2 y F3/F1a, F1b, F2, F3 y F4/' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: AC-1 exige F4 en el corpus ALLOW, pero en D1 es inexistente"* ]]
}

@test "R-SEED: ALLOW sin par BLOCK se detecta" {
  sed -i 's/^| F2 | ALLOW | \(.*\) | B2 |$/| F2 | ALLOW | \1 | |/' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: F2 (ALLOW) sin par BLOCK existente"* ]]
}

@test "R-SEED: par que no es BLOCK se detecta" {
  sed -i 's/^| F2 | ALLOW | \(.*\) | B2 |$/| F2 | ALLOW | \1 | F3 |/' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: el par F3 de F2 no es BLOCK"* ]]
}

@test "R-SEED: sin tabla de semilla falla" {
  sed -i '/^| [FB][0-9]/d' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: no hay tabla de semilla"* ]]
}

@test "R-SLICE (P2-3): AC-6 citado en S1 y S3 se detecta" {
  sed -i '/^1\. \*\*S1\*\*/s/(AC-1, AC-3)/(AC-1, AC-3, AC-6)/' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SLICE: AC-6 en 2 slices (S1, S3)"* ]]
}

@test "R-SLICE: AC sin slice se detecta (SE-511)" {
  sed -i '/^2\. \*\*S1\*\*/s/, AC-11)/)/' "$M511"
  run check "$M511"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SLICE: AC-11 en 0 slices"* ]]
}

@test "R-TOKENS (P2-4): el rango 8.900–9.800 de la versión revisada se detecta" {
  sed -i 's/≈ 8\.660–9\.770 tokens/≈ 8.900–9.800 tokens/' "$M511"
  grep -q '8.900–9.800' "$M511"
  run check "$M511"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-TOKENS: límite inferior 8900"* ]]
}

@test "R-TOKENS: total en bytes que no es la suma se detecta" {
  sed -i 's/\*\*34\.983 B ≈/**35.000 B ≈/' "$M511"
  run check "$M511"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-TOKENS: total 35000 B ≠ 27633 + 7350"* ]]
}

@test "R-SEED: fila de semilla mal formada falla, no se ignora" {
  sed -i 's/^| F2 | ALLOW | \(.*\) | B2 |$/| F2 | ALLOW | \1 |/' "$M510"
  run check "$M510"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-SEED: fila de semilla mal formada: | F2 | ALLOW"* ]]
}
