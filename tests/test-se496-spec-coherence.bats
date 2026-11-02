#!/usr/bin/env bats
# SE-496 — coherencia interna de la spec (hallazgos de la revisión de la PR #1452).
# Ref: docs/specs/SE-496-governed-operational-ontology-authority.spec.md
# Comprobador: tests/se496_spec_check.py. Cada regla tiene caso positivo
# (la spec real pasa) y caso negativo (una copia mutada falla con su motivo).

SPEC="docs/specs/SE-496-governed-operational-ontology-authority.spec.md"
CHECK="tests/se496_spec_check.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
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

@test "R-PHASE (P1-1): F0 sin recheck deja AC-5 (D04) sin componente" {
  sed -i '/^| F0 |/s/`recheck`, //' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-5 usa recheck pero F0 no lo entrega"* ]]
}

@test "R-PHASE: AC-5 movido a F0 y F2 a la vez se detecta" {
  sed -i '/^| F2 |/s/(AC-11)/(AC-11, AC-5)/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-5 en 2 fases"* ]]
}

@test "R-PHASE: AC sin fase se detecta" {
  sed -i '/^| F0 |/s/, AC-13)/)/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-PHASE: AC-13 en 0 fases"* ]]
}

@test "R-USES (P1-2): sin ledger de usos falla" {
  sed -i 's/^\*\*Ledger de usos/**Contador/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: max_uses sin ledger definido"* ]]
}

@test "R-USES (P1-2): ledger sin creación exclusiva falla" {
  sed -i 's/O_CREAT|O_EXCL/creación normal/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: el ledger no fija creación exclusiva"* ]]
}

@test "R-USES (P1-2): ledger que no dice que evaluate no consume falla" {
  sed -i '/^- `evaluate` cuenta los ficheros/s/\*\*no consume\*\*/consume/' "$MUT"
  sed -i '/^\*\*Ledger de usos/,/^En F2/s/no consume/consume/g' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-USES: el ledger no fija evaluate no consume"* ]]
}

@test "R-CODES (P2-2): código usado en la batería y ausente del orden de R3 falla" {
  sed -i '/^| 11 | Los usos registrados/d' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-CODES: MAX_USES_EXHAUSTED"* ]]
}

@test "R-BATTERY (P2-1): una fila D.. con REQUIRES_APPROVAL falla" {
  sed -i '/^| D01 |/s/`NO_CONTRACT`/`REQUIRES_APPROVAL`/' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-BATTERY: fila con REQUIRES_APPROVAL"* ]]
}

@test "R-DIGEST (P2-3): state_digest sin lista de campos falla" {
  sed -i '/^\*\*`state_digest`\.\*\*/,/^El estado que ninguna/{/^- /d}' "$MUT"
  run check "$MUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R-DIGEST"* ]]
}
