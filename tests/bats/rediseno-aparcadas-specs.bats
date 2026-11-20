#!/usr/bin/env bats
# Coherencia de los rediseños propuestos (SE-498 F3, SE-514 S2, SE-515 S3-S4), PR #1620.
# Cada comprobación se ejecuta sobre el texto real (debe pasar) y, donde procede, sobre
# una copia mutada con la contradicción que halló la revisión (debe fallar).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
S514="$REPO_ROOT/docs/specs/SE-514-atencion-humana-cola-unica.spec.md"
S498="$REPO_ROOT/docs/specs/SE-498-global-stop-cross-executor-revocation.spec.md"
S515="$REPO_ROOT/docs/specs/SE-515-aprendizaje-aplicado-obligacion-comprobada.spec.md"
CHG="$REPO_ROOT/CHANGELOG.d/rediseno-fases-aparcadas.md"

# ac14_ok <spec>: AC-14 no puede exigir un «id nuevo» si el id es determinista.
ac14_ok() {
  if grep -q 'un `id` nuevo sí crea otra' "$1"; then return 1; fi
  grep -q 'reemplaza la entrada caducada' "$1"
}

@test "SE-514 AC-14: el id determinista reemplaza la entrada caducada" {
  run ac14_ok "$S514"
  [ "$status" -eq 0 ]
}

@test "SE-514 AC-14 negativo: la redacción contradictoria se detecta" {
  m="$BATS_TEST_TMPDIR/s.md"
  sed 's/la misma pregunta (mismo `id`) reemplaza la entrada caducada/un `id` nuevo sí crea otra; reemplaza la entrada caducada/' "$S514" > "$m"
  run cmp -s "$S514" "$m"
  [ "$status" -ne 0 ]
  run ac14_ok "$m"
  [ "$status" -ne 0 ]
}

@test "SE-514: el hash del id es completo y se compara el asunto normalizado" {
  grep -q 'hash completo (sha256)' "$S514"
  grep -q 'asunto normalizado completo' "$S514"
  run grep -q 'hash corto de `asunto`' "$S514"
  [ "$status" -ne 0 ]
}

@test "SE-514: AC-3 no figura como «sin cambios»" {
  run grep -q 'AC-3 a AC-8 sin cambios' "$S514"
  [ "$status" -ne 0 ]
}

@test "SE-498 AC-1': variante (c) sin «siguiente PR» y primera check antes de reservar" {
  grep -q 'En (c) no hay «siguiente PR»' "$S498"
  grep -q 'si corta, la reserva no llega a existir' "$S498"
  run grep -q 'la reserva aún no existe o ya está `submitted`' "$S498"
  [ "$status" -ne 0 ]
}

@test "SE-498 R5: release con contexto del digest y digest comparado por prefijo y completo" {
  grep -q 'SAVIA_GH_REPO' "$S498"
  grep -q 'por prefijo de 12 caracteres \*\*y\*\*' "$S498"
}

@test "SE-498: F3b declara su dependencia de F3a por AC-4" {
  grep -q 'F3b depende de F3a porque AC-4' "$S498"
}

@test "SE-515 S4: declara el límite del recibo sin firma y la enmienda pendiente a S2" {
  grep -q 'sha256 sin clave' "$S515"
  grep -q 'Enmienda a S2 pendiente' "$S515"
  grep -q 'NOT_GUARANTEED' "$S515"
}

@test "changelog: solo viñetas, sin cabecera de sección en el cuerpo" {
  run grep -q '^### ' "$CHG"
  [ "$status" -ne 0 ]
  grep -q '^version_bump: patch' "$CHG"
}

@test "changelog negativo: una cabecera en el cuerpo se detecta" {
  m="$BATS_TEST_TMPDIR/c.md"
  { cat "$CHG"; printf '\n### Changed\n'; } > "$m"
  run grep -q '^### ' "$m"
  [ "$status" -eq 0 ]
}
