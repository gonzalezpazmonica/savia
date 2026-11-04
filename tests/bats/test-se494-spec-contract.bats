#!/usr/bin/env bats
# SE-494 — Contrato de la spec tras la revisión independiente de la PR #1453.
# La spec aún no tiene implementación (S1–S3). Este test fija las decisiones de
# diseño que corrigen los hallazgos de las revisoras, para que una edición
# posterior de la spec no las quite en silencio. Vive en tests/bats/ y usa
# REPO_ROOT para que ci-select-bats lo elija cuando cambia la spec. Cada
# comprobación se aplica a la spec real (pasa) y a una copia mutada (falla),
# así que ninguna puede pasar por vacío (SE-456). Los tests de comportamiento
# llegan con cada slice.
# Ref: docs/specs/SE-494-trace-hermetic-regressions.spec.md

set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SPEC="$REPO_ROOT/docs/specs/SE-494-trace-hermetic-regressions.spec.md"
  [ -f "$SPEC" ]
  TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf -- "$TMP_DIR"
}

# Extrae una sección «### …» o «## …» de $1 hasta el siguiente encabezado de nivel ≤ 3.
section() {
  awk -v h="$2" '
    index($0, h) == 1 { on = 1; print; next }
    on && /^##+ / && !/^#### / { exit }
    on { print }
  ' "$1"
}

# Copia de la spec sin las líneas que contienen el literal $1.
mutate_drop() {
  local out="$TMP_DIR/spec-mut.md"
  grep -vF -- "$1" "$SPEC" > "$out"
  echo "$out"
}

check_hermeticity() {
  local s
  s="$(section "$1" "### 3. Casos congelados herméticos")"
  [[ "$s" == *"espacio de nombres de red vacío"* ]] || return 1
  [[ "$s" == *"unshare"* ]] || return 1
  [[ "$s" == *"heredado por"*"subprocesos"* ]] || return 1
  [[ "$s" == *"no ejecuta el caso: el veredicto"*"es \`INCOMPLETE\`"* ]] || return 1
  [[ "$s" == *"setpriv --reuid"* ]] || return 1
}

check_ac9() {
  local l
  l="$(grep -E '^- \*\*AC-9\*\*' "$1")" || return 1
  [[ "$l" == *"componente **bash**"* && "$l" == *"curl"* && "$l" == *"/dev/tcp"* ]] || return 1
  [[ "$l" == *"aislamiento de red no disponible"*"INCOMPLETE"* ]] || return 1
}

check_gate() {
  local s l
  s="$(section "$1" "### 4. Gate en CI")"
  [[ "$s" == *"git show origin/main:tests/evals/trace-regressions/manifest.json"* ]] || return 1
  [[ "$s" == *"sin filtro de \`paths\`"* ]] || return 1
  [[ "$s" == *"permissions: contents: read"* ]] || return 1
  [[ "$s" == *"nunca con"*"pull_request_target"* ]] || return 1
  [[ "$s" == *"persist-credentials: false"* ]] || return 1
  [[ "$s" == *"el conjunto de la base es vacío"* ]] || return 1
  l="$(grep -E '^- \*\*AC-11\*\*' "$1")" || return 1
  [[ "$l" == *"su entrada del manifiesto a la vez"* ]] || return 1
}

check_closure() {
  local s l
  l="$(grep -E '^- \*\*AC-1 \(H1\)\*\*' "$1")" || return 1
  [[ "$l" == *"sin \`verification\` o sin \`f2p\`"* ]] || return 1
  s="$(section "$1" "### 2. Ciclo de vida del caso")"
  [[ "$s" == *"recalcula \`--verify-f2p\`"* ]] || return 1
  [[ "$s" == *'^ev-[0-9a-f]{16}$'* ]] || return 1
}

check_id() {
  grep -qF 'sha256(source + \x1f + canon(registro_fuente_completo))' "$1" || return 1
  ! grep -qF 'sha256(source + ts + action + session_id)' "$1"
}

check_digests() {
  local s
  s="$(section "$1" "### 1. Esquema")"
  [[ "$s" == *"de forma recursiva"* ]] || return 1
  [[ "$s" == *"sin distinguir mayúsculas y por subcadena"* ]] || return 1
  [[ "$s" == *"GITHUB_TOKEN"* ]] || return 1
  [[ "$s" == *"solo admiten eventos N1"* ]] || return 1
  [[ "$s" == *"lista de permitidos"* ]] || return 1
}

check_refs() {
  grep -qF 'git merge-base --is-ancestor <ref> origin/main' "$1" || return 1
  grep -qF '^[0-9a-f]{40}$' "$1" || return 1
  grep -qF -- '--end-of-options' "$1" || return 1
}

check_level_allowlist() {
  local l
  l="$(grep -E '^- \*\*AC-2 \(H2\)\*\*' "$1")" || return 1
  [[ "$l" == *"\`N4\` tampoco entra"* && "$l" == *"lista de permitidos"* ]] || return 1
}

check_receipt_link() {
  local l
  l="$(grep -E '^\| `receipt_for_effect`' "$1")" || return 1
  [[ "$l" == *"idempotency_key"* ]] || return 1
  l="$(grep -E '^\| `receipt` ' "$1")" || return 1
  [[ "$l" == *"idempotency_key"* ]] || return 1
}

# --- Positivos: la spec real cumple cada contrato ---

@test "hermeticidad: aislamiento de red a nivel de SO, heredado por subprocesos y sin root" {
  run check_hermeticity "$SPEC"
  [ "$status" -eq 0 ]
}

@test "AC-9 exige un componente bash con curl y /dev/tcp" {
  run check_ac9 "$SPEC"
  [ "$status" -eq 0 ]
}

@test "gate: manifiesto de origin/main, sin paths, contents: read, sin token en .git/config" {
  run check_gate "$SPEC"
  [ "$status" -eq 0 ]
}

@test "closed exige verification y f2p, CI recalcula el f2p y el ID se valida" {
  run check_closure "$SPEC"
  [ "$status" -eq 0 ]
}

@test "ID del caso: source, separador y hash canónico del registro completo" {
  run check_id "$SPEC"
  [ "$status" -eq 0 ]
}

@test "huellas: saneado recursivo y solo eventos N1 en ficheros del repo" {
  run check_digests "$SPEC"
  [ "$status" -eq 0 ]
}

@test "f2p: refs como SHA de 40 hex, tras --end-of-options y ancestros de origin/main" {
  run check_refs "$SPEC"
  [ "$status" -eq 0 ]
}

@test "AC-2: N4 tampoco entra; filtro de nivel como lista de permitidos" {
  run check_level_allowlist "$SPEC"
  [ "$status" -eq 0 ]
}

@test "receipt_for_effect enlaza por idempotency_key" {
  run check_receipt_link "$SPEC"
  [ "$status" -eq 0 ]
}

# --- Negativos: cada contrato falla si se quita la decisión (SE-456) ---

@test "fail: hermeticidad sin el INCOMPLETE por falta de aislamiento" {
  run check_hermeticity "$(mutate_drop 'no ejecuta el caso: el veredicto')"
  [ "$status" -ne 0 ]
}

@test "fail: AC-9 sin el componente bash" {
  local m="$TMP_DIR/ac9.md"
  sed 's/componente \*\*bash\*\*/componente/' "$SPEC" > "$m"
  run check_ac9 "$m"
  [ "$status" -ne 0 ]
}

@test "fail: gate que compara con el manifiesto de la propia PR" {
  run check_gate "$(mutate_drop 'git show origin/main:tests/evals/trace-regressions/manifest.json')"
  [ "$status" -ne 0 ]
}

@test "fail: gate sin persist-credentials: false" {
  local m="$TMP_DIR/cred.md"
  sed 's/persist-credentials: false/persist-credentials: true/g' "$SPEC" > "$m"
  run check_gate "$m"
  [ "$status" -ne 0 ]
}

@test "reject: vuelve la fórmula antigua del ID sin separador" {
  local m="$TMP_DIR/id.md"
  cp "$SPEC" "$m"
  echo 'ID: sha256(source + ts + action + session_id)' >> "$m"
  run check_id "$m"
  [ "$status" -ne 0 ]
}

@test "fail: huellas que vuelven a admitir N2 en el repo" {
  run check_digests "$(mutate_drop 'solo admiten eventos N1')"
  [ "$status" -ne 0 ]
}

@test "fail: refs sin validar como SHA de 40 hex" {
  local m="$TMP_DIR/refs.md"
  sed 's/\^\[0-9a-f\]{40}\$/<ref>/g' "$SPEC" > "$m"
  run check_refs "$m"
  [ "$status" -ne 0 ]
}

@test "fail: AC-2 sin el caso N4" {
  local m="$TMP_DIR/ac2.md"
  sed 's/`N4` tampoco entra/N4 se ignora/' "$SPEC" > "$m"
  run check_level_allowlist "$m"
  [ "$status" -ne 0 ]
}

# --- Casos límite del helper: una sección inexistente no da falso verde ---

@test "edge: sección nonexistent devuelve salida empty" {
  run section "$SPEC" "### 99. No existe"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edge: spec empty no cumple ningún contrato" {
  local e="$TMP_DIR/empty.md"
  : > "$e"
  run check_hermeticity "$e"
  [ "$status" -ne 0 ]
  run check_gate "$e"
  [ "$status" -ne 0 ]
  run check_closure "$e"
  [ "$status" -ne 0 ]
}

@test "edge: null — receipt sin idempotency_key en la tabla falla" {
  local m="$TMP_DIR/rcpt.md"
  sed '/^| `receipt` /s/idempotency_key/null_key/g' "$SPEC" > "$m"
  run check_receipt_link "$m"
  [ "$status" -ne 0 ]
}
