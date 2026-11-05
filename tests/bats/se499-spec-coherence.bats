#!/usr/bin/env bats
# SE-499 — coherencia interna de la spec (hallazgos de la revisión de la PR #1461).
# Ref: docs/specs/SE-499-external-anchoring-evidence-chains.spec.md
# Comprobador: tests/se499_spec_check.py. Cada regla tiene caso positivo
# (la spec real pasa) y caso negativo (una copia mutada falla con su motivo).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-499-external-anchoring-evidence-chains.spec.md"
CHECK="$REPO_ROOT/tests/se499_spec_check.py"

setup() {
  set -uo pipefail
  MUT="$BATS_TEST_TMPDIR/spec.md"
  cp "$SPEC" "$MUT"
}

check() { python3 -I "$CHECK" "$1"; }

@test "spec real: coherente" {
  run check "$SPEC"
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

@test "R-STICKY (P1-1): sin R6 falla" {
  sed -i 's/^### R6 /### RX /' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-STICKY: falta la sección R6"* ]]
}

@test "R-STICKY (P1-1): AC-7 con UNANCHORED sin red y sin acotar a «sin alta» falla" {
  sed -i 's/^- \*\*AC-7 — A2b sin red\.\*\*.*$/- **AC-7 — A2b sin red.** Con el remoto inaccesible, `verify` da `UNANCHORED` con el motivo./' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"permite UNANCHORED por ocultación"* ]]
}

@test "R-STICKY (P1-1): R2.3 con UNANCHORED incondicional falla" {
  sed -i 's/ \*\*y la cadena no está dada de alta\*\* (R6)//' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R2.3 no limita UNANCHORED"* ]]
}

@test "R-STICKY-AC (P1-1): quitar la variante (c) install_id falla" {
  sed -i 's/ (c) `install_id` local cambiado,//' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"falta la variante (c)"* ]]
}

@test "R-A3 (P1-1): garantía «alta» sin distinguir ocultación falla" {
  sed -i '/^### A3/,/^### Descartadas/s/^- \*\*Garantía:\*\*.*$/- **Garantía:** alta. Ningún agente puede fabricar la firma./' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-A3"* ]]
}

@test "R-EXIT (P2-2): R5 sin traducción del exit 3 falla" {
  sed -i 's/Exit 3 (`UNANCHORED`)/El 3/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-EXIT: R5 no define «Exit 3»"* ]]
}

@test "R-PENDING (P2-3): pr-comment sin pending falla" {
  sed -i 's/^- `pr-comment`: publica .*$/- `pr-comment`: publica con `gh issue comment`./' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PENDING"* ]]
}

@test "R-HEAD (P2-4): «prev_hash siguiente» falla" {
  printf '\nNota: `prev_hash` siguiente.\n' >> "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-HEAD"* ]]
}

@test "R-PRIVATE (seguridad P2-2): seudónimo sin restricción de transporte falla" {
  sed -i 's/^- `chain`:.*$/- `chain`: `yema\/<h>` con <h> = sha256 truncado./' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PRIVATE"* ]]
}

@test "R-PLAN: un AC fuera del plan falla" {
  sed -i 's/, AC-13\././' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PLAN: AC-13"* ]]
}
