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

# Ficheros de motivo de una spec; falla si falta alguno (fail-closed: sin esto grep da exit 2 y un test negativo pasaría en falso).
ficheros() {
  local i="$1" f n=0
  for f in "$ROOT/docs/propuestas/planning.d/SE-$i.json" "$ROOT/docs/propuestas/LOG.d/SE-$i-DEFERRED.md" "$ROOT"/docs/specs/SE-$i-*.spec.md; do
    [ -f "$f" ] || { echo "no existe $f" >&2; return 1; }
    echo "$f"; n=$((n+1))
  done
  [ "$n" -eq 3 ] || { echo "SE-$i: $n ficheros, esperados 3" >&2; return 1; }
}

@test "ningún motivo atribuye la decisión a la operadora fuera de la frase de atribución" {
  for i in $IDS; do
    for f in $(ficheros "$i"); do
      # Se quita la frase de atribución completa; si "operadora" aún aparece en una línea de motivo, atribuye la decisión.
      resto="$(grep -iE 'deferral|deferred_reason|aparcad' "$f" | sed 's/propuesta de la orquestadora, pendiente de confirmar por la operadora//g' | grep -i 'operadora' || true)"
      [ -z "$resto" ] || { echo "atribución a la operadora en $f: $resto"; return 1; }
    done
  done
}

@test "el campo deferral y deferred_reason empiezan por la fecha y la atribución" {
  for i in $IDS; do
    grep -qE '"deferral": "2026-11-18 \(propuesta de la orquestadora, pendiente' "$ROOT/docs/propuestas/planning.d/SE-$i.json" || { echo "deferral sin formato en SE-$i"; return 1; }
    grep -qE '^deferred_reason: "?2026-11-18 \(propuesta de la orquestadora, pendiente' "$ROOT"/docs/specs/SE-$i-*.spec.md || { echo "deferred_reason sin formato en SE-$i"; return 1; }
  done
}

@test "SE-458 no afirma un límite de PRs activas que el repo no define" {
  run grep -l "ya limita las PRs activas" $(ficheros 458)
  [ "$status" -eq 1 ]
}

@test "SE-450 no afirma trabajo de rutas Windows sin PR citado" {
  run grep -l "rutas Windows ya entró" $(ficheros 450)
  [ "$status" -eq 1 ]
}

@test "ninguna referencia activa dice que SE-469 está APPROVED" {
  run grep -c "SE-469 ya APPROVED" "$ROOT/docs/propuestas/planning-state.json"
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
  run grep -c "SE-469 aparcada" "$ROOT/docs/propuestas/planning-state.json"
  [ "$output" -ge 1 ]
}

@test "la cola no presenta como trabajo vigente las specs aparcadas (planning-state y ROADMAP-CURRENT)" {
  for f in "$ROOT/docs/propuestas/planning-state.json" "$ROOT/docs/propuestas/ROADMAP-CURRENT.md"; do
    [ -f "$f" ] || { echo "no existe $f"; return 1; }
    run grep -cE 'SE-454 invariantes negativos como tests|SE-449 regla y lectura|SE-450 auditoría de instaladores|Último slice: piloto de suite de conformidad|SE-458 \(tope y lotes|SE-443, SE-447|invariantes de SE-454 llevan' "$f"
    [ "$status" -eq 1 ] || { echo "texto de cola obsoleto en $f"; return 1; }
  done
}
