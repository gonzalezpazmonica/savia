#!/usr/bin/env bats
# Motivos de las 10 specs aparcadas (PR #1606): atribución honesta y sin premisas sin comprobar.

IDS="408 447 449 450 452 454 458 463 467 469"

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "cada motivo declara quién propone y que falta confirmar" {
  for i in $IDS; do
    for f in "$ROOT/docs/propuestas/planning.d/SE-$i.json" "$ROOT/docs/propuestas/LOG.d/SE-$i-DEFERRED.md" "$ROOT"/docs/specs/SE-$i-*.spec.md; do
      grep -q "propuesta de la orquestadora, pendiente de confirmar por la operadora" "$f" || { echo "falta atribución en $f"; return 1; }
    done
  done
}

@test "ningún motivo atribuye la decisión a la operadora sin cita" {
  for i in $IDS; do
    run grep -l "(operadora): aparcada" "$ROOT/docs/propuestas/planning.d/SE-$i.json" "$ROOT/docs/propuestas/LOG.d/SE-$i-DEFERRED.md" "$ROOT"/docs/specs/SE-$i-*.spec.md
    [ "$status" -ne 0 ] || { echo "atribución sin cita: $output"; return 1; }
  done
}

@test "SE-458 no afirma un límite de PRs activas que el repo no define" {
  run grep -l "ya limita las PRs activas" "$ROOT/docs/propuestas/planning.d/SE-458.json" "$ROOT/docs/propuestas/LOG.d/SE-458-DEFERRED.md" "$ROOT"/docs/specs/SE-458-*.spec.md
  [ "$status" -ne 0 ]
}

@test "SE-450 no afirma trabajo de rutas Windows sin PR citado" {
  run grep -l "rutas Windows ya entró" "$ROOT/docs/propuestas/planning.d/SE-450.json" "$ROOT/docs/propuestas/LOG.d/SE-450-DEFERRED.md" "$ROOT"/docs/specs/SE-450-*.spec.md
  [ "$status" -ne 0 ]
}

@test "ninguna referencia activa dice que SE-469 está APPROVED" {
  run grep -c "SE-469 ya APPROVED" "$ROOT/docs/propuestas/planning-state.json"
  [ "$output" = "0" ]
  run grep -c "SE-469 aparcada" "$ROOT/docs/propuestas/planning-state.json"
  [ "$output" -ge 1 ]
}
