#!/usr/bin/env bats
# SE-494 — Contrato de la spec tras la revisión independiente de la PR #1453.
# La spec aún no tiene implementación (S1–S3). Este test fija las decisiones de
# diseño que corrigen los hallazgos de las revisoras, para que una edición
# posterior de la spec no las quite en silencio. Los tests de comportamiento
# llegan con cada slice.
# Ref: docs/specs/SE-494-trace-hermetic-regressions.spec.md

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SPEC="$ROOT/docs/specs/SE-494-trace-hermetic-regressions.spec.md"
  [ -f "$SPEC" ]
}

# Extrae una sección «### …» o «## …» hasta el siguiente encabezado de nivel ≤ 3.
section() {
  awk -v h="$1" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^##+ / && !/^#### / { exit }
    on { print }
  ' "$SPEC"
}

# P1: la hermeticidad debe alcanzar a los subprocesos bash, no solo a Python.
@test "hermeticidad: aislamiento de red a nivel de SO heredado por subprocesos" {
  run section "### 3. Casos congelados herméticos"
  [ "$status" -eq 0 ]
  [[ "$output" == *"espacio de nombres de red vacío"* ]]
  [[ "$output" == *"unshare"* ]]
  [[ "$output" == *"heredado por"*"subprocesos"* ]]
}

@test "hermeticidad: sin aislamiento el veredicto es INCOMPLETE, nunca PASS" {
  run section "### 3. Casos congelados herméticos"
  [[ "$output" == *"no ejecuta el caso: el veredicto"*"es \`INCOMPLETE\`"* ]]
}

@test "hermeticidad: la frase antigua que daba por hecho el INCOMPLETE en bash ya no está" {
  run grep -c "Si un componente bash intenta usar la red, su error se convierte en" "$SPEC"
  [ "$output" = "0" ]
}

@test "AC-9 exige un componente bash con curl y /dev/tcp" {
  run grep -E '^- \*\*AC-9\*\*' "$SPEC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"componente **bash**"* ]]
  [[ "$output" == *"curl"* ]]
  [[ "$output" == *"/dev/tcp"* ]]
  [[ "$output" == *"aislamiento de red no disponible"*"INCOMPLETE"* ]]
}

# P2: NO_COVERAGE contra el manifiesto de la rama base, no el de la PR.
@test "NO_COVERAGE se compara con el manifiesto de origin/main" {
  run section "### 4. Gate en CI"
  [[ "$output" == *"git show origin/main:tests/evals/trace-regressions/manifest.json"* ]]
  run grep -E '^- \*\*AC-11\*\*' "$SPEC"
  [[ "$output" == *"su entrada del manifiesto a la vez"* ]]
}

# P2: el gate no puede quedarse sin ejecutar por un filtro de paths.
@test "gate: workflow propio sin filtro de paths, solo contents: read, sin pull_request_target" {
  run section "### 4. Gate en CI"
  [[ "$output" == *"sin filtro de \`paths\`"* ]]
  [[ "$output" == *"permissions: contents: read"* ]]
  [[ "$output" == *"nunca con"*"pull_request_target"* ]]
}

# P2: un caso closed sin verificación ni f2p no produce evals.
@test "closed exige verification y f2p, y CI recalcula el f2p" {
  run grep -E '^- \*\*AC-1 \(H1\)\*\*' "$SPEC"
  [[ "$output" == *"sin \`verification\` o sin \`f2p\`"* ]]
  run section "### 2. Ciclo de vida del caso"
  [[ "$output" == *"recalcula \`--verify-f2p\`"* ]]
}

# P2: ID por hash del registro completo, no por concatenación sin separador.
@test "ID del caso: hash canónico del registro completo; ya no source+ts+action+session_id" {
  run grep -c 'sha256(source + ts + action + session_id)' "$SPEC"
  [ "$output" = "0" ]
  run grep -c 'registro_fuente_completo' "$SPEC"
  [ "$output" -ge 1 ]
}

# P2: saneado recursivo, por subcadena y sin distinguir mayúsculas.
@test "huellas: lista de denegación recursiva, por subcadena y sin mayúsculas" {
  run section "### 1. Esquema"
  [[ "$output" == *"de forma recursiva"* ]]
  [[ "$output" == *"sin distinguir mayúsculas y por subcadena"* ]]
  [[ "$output" == *"GITHUB_TOKEN"* ]]
}

# P2: refs del f2p ancestros de origin/main antes de ejecutar nada.
@test "f2p: failing_ref y fixed_ref deben ser ancestros de origin/main" {
  run grep -c 'git merge-base --is-ancestor <ref> origin/main' "$SPEC"
  [ "$output" -ge 1 ]
}

# P2: enlace del recibo con el efecto definido por idempotency_key.
@test "receipt_for_effect enlaza por idempotency_key" {
  run grep -E '^\| `receipt_for_effect`' "$SPEC"
  [[ "$output" == *"idempotency_key"* ]]
  run grep -E '^\| `receipt` ' "$SPEC"
  [[ "$output" == *"idempotency_key"* ]]
}
