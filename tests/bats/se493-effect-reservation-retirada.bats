#!/usr/bin/env bats
# SE-493 S4 (AC-k): effect-reservation.sh no tiene consumidores y se ha eliminado.
# Contrato de reservas de pr.merge que sigue vivo: scripts/f5-state.sh (merge-sprint, push-pr).
# Un test que no puede fallar no vale (SE-456): el detector tiene su propio caso negativo.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  NAME="effect-""reservation"   # partido: este fichero no se cita a sí mismo
}

# Lista ficheros bajo $1 que mencionan el nombre. Sin $1 sale 2 (fail-closed).
consumers() {
  [ -d "$1" ] || return 2
  grep -rlI --exclude-dir=node_modules --exclude-dir=target --exclude=se493-effect-reservation-retirada.bats \
    -e "$NAME" "$1" || true
}

@test "el script retirado ya no existe en el árbol" {
  [ ! -e "$REPO_DIR/scripts/$NAME.sh" ]
}

@test "ningún script, hook, workflow, test ni regla lo referencia" {
  for d in scripts .claude .github .opencode tests docs/rules; do
    [ -d "$REPO_DIR/$d" ] || continue
    run consumers "$REPO_DIR/$d"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "el detector funciona: una referencia en un fixture se detecta" {
  mkdir -p "$BATS_TEST_TMPDIR/fx/scripts"
  printf 'bash scripts/%s.sh reserve pr.merge 1\n' "$NAME" > "$BATS_TEST_TMPDIR/fx/scripts/llamador.sh"
  run consumers "$BATS_TEST_TMPDIR/fx"
  [[ "$output" == *"llamador.sh"* ]]
}

@test "el detector falla cerrado: directorio inexistente no da verde" {
  run consumers "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -eq 2 ]
}

@test "el contrato vivo f5-state.sh sigue ahí y rechaza una op distinta de pr.merge" {
  run bash "$REPO_DIR/scripts/f5-state.sh" reserve publish.report 7
  [ "$status" -eq 2 ]
}

@test "coherence-gates ya no lista el script retirado como cierre pendiente" {
  run grep -c "$NAME" "$REPO_DIR/scripts/coherence-gates.sh"
  [ "$output" = "0" ]
}
