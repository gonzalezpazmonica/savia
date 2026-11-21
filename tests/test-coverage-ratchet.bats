#!/usr/bin/env bats
# nightly: serial (compara el estado del árbol antes y después; otra suite escribiendo a la vez lo falsea)
# Ref: SE-339 — test-coverage-ratchet.sh (AC-4: conteo, umbral, detección)
# Spec: docs/specs/SE-339-test-coverage-ratchet.spec.md

SCRIPT="scripts/test-coverage-ratchet.sh"

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RATCHET="$ROOT_DIR/scripts/test-coverage-ratchet.sh"
  TMPD="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPD" 2>/dev/null || true
}

@test "SE-339: cuenta los hooks críticos de la allowlist" {
  n=$(grep -vcE '^\s*#|^\s*$' "$ROOT_DIR/tests/hooks/critical-hooks.txt")
  run bash "$RATCHET"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$n/$n hooks críticos"
}

@test "SE-339: --ci falla si el umbral supera la cobertura (no-decreciente)" {
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 101 --ci
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "FAIL"
}

@test "SE-339: detecta hook sin test con allowlist custom" {
  echo "hook-inexistente-xyz" > "$TMPD/crit.txt"
  SAVIA_CRITICAL_HOOKS_FILE="$TMPD/crit.txt" run bash "$RATCHET" --conf "$TMPD/conf" --ci --threshold 100
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "hook-inexistente-xyz"
}

@test "SE-339: RN-01 — el umbral persistido no baja por flag" {
  echo "THRESHOLD=90" > "$TMPD/conf"
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 80 --ci
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "RN-01"
  grep -qx "THRESHOLD=90" "$TMPD/conf"
}

@test "SE-339: los tests no tocan el conf versionado" {
  before=$(cat "$ROOT_DIR/config/test-coverage.conf")
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 100
  [ "$status" -eq 0 ]
  [ "$(cat "$ROOT_DIR/config/test-coverage.conf")" = "$before" ]
  grep -qx "THRESHOLD=100" "$TMPD/conf"
}

@test "SE-339: PURE_BASH y sin red (CRIT-001)" {
  bash -n "$RATCHET"
  ! grep -rniE 'http://|https://|curl |wget |requests\.' "$RATCHET"
}

@test "SE-339: el script declara set -uo pipefail" {
  head -20 "$RATCHET" | grep -q 'set -uo pipefail'
}

@test "SE-339: allowlist missing → exit 2" {
  SAVIA_CRITICAL_HOOKS_FILE="$TMPD/no-existe.txt" run bash "$RATCHET" --conf "$TMPD/conf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no existe"* ]]
}

@test "SE-339: empty allowlist fails closed (exit 2, sin división por cero)" {
  printf '# solo comentarios\n\n' > "$TMPD/crit.txt"
  SAVIA_CRITICAL_HOOKS_FILE="$TMPD/crit.txt" run bash "$RATCHET" --conf "$TMPD/conf" --ci
  [ "$status" -eq 2 ]
  [[ "$output" == *"ningún hook crítico"* ]]
  [[ "$output" != *"división"* ]]
}

@test "SE-339: invalid --threshold rejected and not persisted" {
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 12abc
  [ "$status" -eq 2 ]
  [ ! -e "$TMPD/conf" ]
}

@test "SE-339: boundary — umbral igual a la cobertura pasa" {
  echo "hook-inexistente-xyz" > "$TMPD/crit.txt"
  grep -m1 -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/tests/hooks/critical-hooks.txt" >> "$TMPD/crit.txt"
  SAVIA_CRITICAL_HOOKS_FILE="$TMPD/crit.txt" run bash "$RATCHET" --conf "$TMPD/conf" --ci --threshold 50
  [ "$status" -eq 0 ]
  [[ "$output" == *"(50%)"* ]]
}

@test "SE-339: zero threshold en un conf nuevo se persiste; después no baja" {
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 0
  [ "$status" -eq 0 ]
  grep -qx "THRESHOLD=0" "$TMPD/conf"
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 40
  [ "$status" -eq 0 ]
  run bash "$RATCHET" --conf "$TMPD/conf" --threshold 0
  [ "$status" -eq 2 ]
  grep -qx "THRESHOLD=40" "$TMPD/conf"
}

@test "SE-339: --help exit 0 y argumento desconocido exit 2" {
  run bash "$RATCHET" --help
  [ "$status" -eq 0 ]
  run bash "$RATCHET" --bogus
  [ "$status" -eq 2 ]
}

@test "SE-339: --threshold y --conf sin valor → exit 2 (no arg)" {
  run bash "$RATCHET" --threshold
  [ "$status" -eq 2 ]
  run bash "$RATCHET" --conf
  [ "$status" -eq 2 ]
}

@test "SE-339: invalid conf is data, never executed (exit 2)" {
  echo 'THRESHOLD=$(touch "'"$TMPD"'/pwned")' > "$TMPD/conf"
  run bash "$RATCHET" --conf "$TMPD/conf"
  [ "$status" -eq 2 ]
  [ ! -e "$TMPD/pwned" ]
}

@test "SE-339: sin --threshold no escribe nada en el repo (read-only)" {
  before=$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)
  run bash "$RATCHET" --ci
  [ "$status" -eq 0 ]
  [ "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null)" = "$before" ]
}
