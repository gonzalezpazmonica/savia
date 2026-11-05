#!/usr/bin/env bats
# SE-509 — coherencia de la spec del programa de deuda de revisión.
# Ref: docs/specs/SE-509-review-debt-program.spec.md
# Origen: revisión independiente de la PR #1481 (P1: el gate nuevo de SE-509d
# usaba el id G20, que ya es de SE-501; P2: recuento de AC).
#
# Invariante: el id del gate que introduce SE-509d no lo usa ninguna otra spec.
# La comprobación es fail-closed: sin encabezado de gate o sin id, falla.

SPEC="docs/specs/SE-509-review-debt-program.spec.md"
SPECS_DIR="docs/specs"

setup() {
  set -uo pipefail
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
  cd /
}

# Imprime el id del gate de SE-509d (G<n>) leído del encabezado del gate.
gate_id() {
  grep -oE '^### Gate contra la reacumulación \(G[0-9]+' "$1" \
    | grep -oE 'G[0-9]+$' | head -1
}

# Sale 0 si ninguna otra spec del directorio menciona el id; 1 si alguna lo
# menciona (las lista) o si no hay id que comprobar.
gate_id_unique() {
  local spec="$1" dir="$2" id others
  id="$(gate_id "$spec")"
  [[ -n "$id" ]] || { echo "sin id de gate en $spec"; return 1; }
  others="$(grep -lwE "$id" "$dir"/*.md | grep -vxF "$spec")"
  [[ -z "$others" ]] || { echo "colisión $id: $others"; return 1; }
  echo "ok $id"
}

@test "SE-509: la spec existe y declara un id de gate" {
  [[ -f "$SPEC" ]]
  run gate_id "$SPEC"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ ^G[0-9]+$ ]]
}

@test "SE-509: el id del gate de SE-509d no lo usa ninguna otra spec" {
  run gate_id_unique "$SPEC" "$SPECS_DIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == ok\ G* ]]
}

@test "SE-509: el gate no reutiliza G20, que es de SE-501" {
  grep -qwE 'G20' "$SPECS_DIR"/SE-501-*.spec.md
  run gate_id "$SPEC"
  [[ "$output" != "G20" ]]
}

@test "negativo (fail): otra spec con el mismo id de gate hace fallar la comprobación" {
  local d="$BATS_TEST_TMPDIR/specs"
  mkdir -p "$d"
  printf '### Gate contra la reacumulación (G7 en pr-plan)\n' > "$d/SE-A.md"
  printf 'Un gate nuevo, G7 Otra cosa.\n' > "$d/SE-B.md"
  run gate_id_unique "$d/SE-A.md" "$d"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"colisión G7"* ]]
}

@test "negativo (missing): sin encabezado de gate la comprobación falla (fail-closed)" {
  local d="$BATS_TEST_TMPDIR/specs2"
  mkdir -p "$d"
  printf '# Spec sin gate\n' > "$d/SE-A.md"
  run gate_id_unique "$d/SE-A.md" "$d"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"sin id de gate"* ]]
}

@test "límite (boundary): un id que solo aparece dentro de otro (G70, G17) no es colisión" {
  local d="$BATS_TEST_TMPDIR/specs3"
  mkdir -p "$d"
  printf '### Gate contra la reacumulación (G7 en pr-plan)\n' > "$d/SE-A.md"
  printf 'Gate G70 y G17, distintos.\n' > "$d/SE-B.md"
  run gate_id_unique "$d/SE-A.md" "$d"
  [[ "$status" -eq 0 ]]
}


@test "negativo (nonexistent): una spec inexistente hace fallar la comprobación" {
  local d="$BATS_TEST_TMPDIR/specs4"
  mkdir -p "$d"
  run gate_id_unique "$d/no-existe.md" "$d"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"sin id de gate"* ]]
}

@test "límite (empty): un directorio sin otras specs no es colisión" {
  local d="$BATS_TEST_TMPDIR/specs5"
  mkdir -p "$d"
  printf '### Gate contra la reacumulación (G7 en pr-plan)\nG7 se cita aquí también.\n' > "$d/SE-A.md"
  run gate_id_unique "$d/SE-A.md" "$d"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ok G7" ]]
}

@test "negativo (bad): la misma colisión se detecta en mitad de una línea larga" {
  local d="$BATS_TEST_TMPDIR/specs6"
  mkdir -p "$d"
  printf '### Gate contra la reacumulación (G7 en pr-plan)\n' > "$d/SE-A.md"
  printf 'pr-plan: G4 deja de resolver la firma; G7 es nuevo; G10 sigue.\n' > "$d/SE-B.md"
  run gate_id_unique "$d/SE-A.md" "$d"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"SE-B.md"* ]]
}
