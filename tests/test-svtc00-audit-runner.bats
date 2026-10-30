#!/usr/bin/env bats
# tests/test-svtc00-audit-runner.bats — runner de la auditoría SVTC-00 (PR #1420).
# Cubre: dir-salida relativo, etiqueta de mutación inexistente y control negativo de H6.

RUN="$BATS_TEST_DIRNAME/../projects/savia-vaults/eval/audit-svtc00/run.sh"

setup() {
  [[ -f "$BATS_TEST_DIRNAME/../projects/savia-vaults/node_modules/tsx/dist/loader.mjs" ]] \
    || skip "faltan dependencias locales de savia-vaults (npm ci --ignore-scripts)"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

@test "dir-salida relativo deja los JSON en el cwd original" {
  cd "$WORK"
  run bash "$RUN" H8 salida
  [ "$status" -eq 0 ]
  [ -s "$WORK/salida/H8.json" ]
  [ -s "$WORK/salida/environment.json" ]
}

@test "dir-salida absoluto también deja los JSON" {
  cd "$WORK"
  run bash "$RUN" H8 "$WORK/abs"
  [ "$status" -eq 0 ]
  [ -s "$WORK/abs/H8.json" ]
}

@test "AUDIT_MUTATE_CHECK con etiqueta inexistente falla (no es un falso verde)" {
  cd "$WORK"
  run env AUDIT_MUTATE_CHECK=etiqueta-que-no-existe bash "$RUN" H8
  [ "$status" -eq 1 ]
  [[ "$output" == *"ninguna etiqueta coincide"* ]]
}

@test "AUDIT_MUTATE_CHECK con etiqueta real falla el caso (la aserción puede fallar)" {
  cd "$WORK"
  run env AUDIT_MUTATE_CHECK=H6-default-control bash "$RUN" H6
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutación: H6-default-control"* ]]
}

@test "control: sin mutación H6 pasa" {
  cd "$WORK"
  run bash "$RUN" H6
  [ "$status" -eq 0 ]
}
