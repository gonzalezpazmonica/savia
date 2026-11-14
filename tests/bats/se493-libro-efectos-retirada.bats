#!/usr/bin/env bats
# SE-493 retirada (decisión de la operadora, 2026-11-14, «conectar antes de construir»):
# el libro de efectos (effect-ledger.py, effect-ops.json) no tenía consumidor y se ha retirado.
# El contrato vivo de reservas de pr.merge es scripts/f5-state.sh (merge-sprint, push-pr) y no se toca.
# Un test que no puede fallar no vale (SE-456): el detector tiene casos negativos propios.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Nombres partidos: este fichero no se cita a sí mismo.
  LEDGER="effect-""ledger"
  OPS="effect-""ops"
  HELPERS="se493-""helpers"
}

# Lista ficheros bajo $1 que referencian el libro retirado (script, mapa de operaciones, ayudas de prueba
# o ficheros de prueba del libro). Sin directorio válido sale 2 (fail-closed).
# Este fichero queda excluido por nombre; .claude/context-cache es caché de sesión gitignored.
# Las menciones al libro en el texto de un prototipo (docs/specs/assets, fuera de estos directorios) son historia.
consumers() {
  [ -d "$1" ] || return 2
  grep -rlIP --exclude-dir=node_modules --exclude-dir=target --exclude-dir=context-cache \
    --exclude=se493-libro-efectos-retirada.bats \
    -e "scripts/${LEDGER}|scripts/${OPS}|${HELPERS}|se493-${LEDGER}" "$1" || true
}

@test "los ficheros del libro ya no existen en el árbol" {
  [ ! -e "$REPO_DIR/scripts/$LEDGER.py" ]
  [ ! -e "$REPO_DIR/scripts/$OPS.json" ]
  [ ! -e "$REPO_DIR/tests/bats/$HELPERS.bash" ]
  run ls "$REPO_DIR"/tests/bats/se493-"$LEDGER"*.bats
  [ "$status" -ne 0 ]
}

@test "ningún script, hook, workflow, test ni regla referencia el libro retirado" {
  for d in scripts .claude .github .opencode tests docs/rules; do
    [ -d "$REPO_DIR/$d" ] || continue
    run consumers "$REPO_DIR/$d"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "el detector funciona: una llamada al script en un fixture se detecta" {
  mkdir -p "$BATS_TEST_TMPDIR/fx/scripts"
  printf 'python3 scripts/%s.py reconcile --all\n' "$LEDGER" > "$BATS_TEST_TMPDIR/fx/scripts/llamador.sh"
  run consumers "$BATS_TEST_TMPDIR/fx"
  [[ "$output" == *"llamador.sh"* ]]
}

@test "el detector funciona: el mapa de operaciones y las ayudas de prueba se detectan" {
  mkdir -p "$BATS_TEST_TMPDIR/fx2/tests"
  printf 'load %s\n' "$HELPERS" > "$BATS_TEST_TMPDIR/fx2/tests/uno.bats"
  printf '{"ops": "scripts/%s.json"}\n' "$OPS" > "$BATS_TEST_TMPDIR/fx2/tests/dos.json"
  run consumers "$BATS_TEST_TMPDIR/fx2"
  [[ "$output" == *"uno.bats"* ]]
  [[ "$output" == *"dos.json"* ]]
}

@test "el detector falla cerrado: directorio inexistente no da verde" {
  run consumers "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -eq 2 ]
}

@test "el contrato vivo f5-state.sh sigue ahí y rechaza una op distinta de pr.merge" {
  run bash "$REPO_DIR/scripts/f5-state.sh" reserve publish.report 7
  [ "$status" -eq 2 ]
}

@test "merge-sprint y push-pr siguen usando f5-state.sh" {
  run grep -c 'f5-state.sh' "$REPO_DIR/scripts/merge-sprint.sh"
  [ "$output" -ge 1 ]
  run grep -c 'f5-state.sh' "$REPO_DIR/scripts/push-pr.sh"
  [ "$output" -ge 1 ]
}

@test "la spec SE-493 consta RETIRED y conserva su texto" {
  run grep -m1 '^status:' "$REPO_DIR/docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md"
  [ "$output" = "status: RETIRED" ]
  run grep -c 'Effect Ledger' "$REPO_DIR/docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md"
  [ "$output" -ge 1 ]
}
