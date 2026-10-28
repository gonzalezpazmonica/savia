#!/usr/bin/env bats
# check-readme-sync.sh mide solo los README que forman parte del cambio. Un README que ya excedía el
# límite antes del cambio es deuda previa: no debe bloquear un commit que no lo toca (con el
# compliance-gate activo bloqueaba todos los commits del repo).

CHECK=".claude/compliance/checks/check-readme-sync.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  cd "$TMP"
  seq 1 200 > README.md
  seq 1 10 > README.en.md
}

teardown() { rm -rf "$TMP"; }

@test "un README largo que no va en el cambio no bloquea" {
  run bash "$ROOT/$CHECK" "scripts/x.sh docs/y.md"
  [ "$status" -eq 0 ]
}

@test "un README largo que sí va en el cambio bloquea" {
  run bash "$ROOT/$CHECK" "README.md scripts/x.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"README.md: 200"* ]]
}

@test "README.en.md largo dentro del cambio también bloquea" {
  seq 1 160 > README.en.md
  run bash "$ROOT/$CHECK" "README.en.md"
  [ "$status" -eq 1 ]
}

@test "un README dentro de límites en el cambio pasa" {
  seq 1 100 > README.md
  run bash "$ROOT/$CHECK" "README.md README.en.md"
  [ "$status" -eq 0 ]
}

@test "una ruta que solo contiene README.md como subcadena no cuenta como el README raíz" {
  run bash "$ROOT/$CHECK" "docs/README.md.bak"
  [ "$status" -eq 0 ]
}
