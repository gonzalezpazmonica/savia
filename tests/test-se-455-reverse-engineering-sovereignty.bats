#!/usr/bin/env bats
# Ref: docs/specs/SE-455-reverse-engineering-sovereignty.spec.md (AC1-AC6)
# Ref: .claude/skills/reverse-engineering-sovereignty/SKILL.md
#
# Verifica el contrato de la skill: puerta de autorizacion A-D, doble
# confirmacion, cinco lineas rojas, ausencia de instalacion sin --dry-run y de
# rutas personales, plantilla con las cuatro clases de evidencia, y la
# dimension opcional de sovereignty-auditor. Los casos negativos mutan una
# copia temporal para demostrar que cada comprobacion puede fallar.
# REA_SKILL_DIR / SOV_SKILL_DIR / LEGACY_CMD permiten apuntar a otra ubicacion.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL_DIR="${REA_SKILL_DIR:-$REPO_ROOT/.claude/skills/reverse-engineering-sovereignty}"
  SKILL="$SKILL_DIR/SKILL.md"
  TEMPLATE="$SKILL_DIR/references/plantilla-informe.md"
  SOV="${SOV_SKILL_DIR:-$REPO_ROOT/.claude/skills/sovereignty-auditor}/SKILL.md"
  LEGACY="${LEGACY_CMD:-$REPO_ROOT/.claude/commands/legacy-assess.md}"
  TMP="$(mktemp -d)"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && find "$TMP" -mindepth 1 -delete && rmdir "$TMP"
}

# --- helpers: comprobaciones reutilizadas por los casos positivos y negativos ---

has_classes() {
  local f="$1" c
  for c in "Clase A" "Clase B" "Clase C" "Clase D"; do
    grep -qF "$c" "$f" || return 1
  done
}

has_double_confirmation() {
  grep -qi "doble confirmaci" "$1"
}

has_red_lines() {
  local f="$1" l
  for l in \
    "No saltar medidas de protección, licencias ni DRM" \
    "No extraer credenciales ni secretos de terceros" \
    "No redistribuir el código descompilado" \
    "No crear malware ni exploits contra terceros" \
    "No subir artefactos de nivel N3 o superior a la nube"; do
    grep -qF "$l" "$f" || return 1
  done
}

# Devuelve 0 si hay un "setup" de npx/npm exec sin --dry-run en la misma linea.
has_install_without_dry_run() {
  grep -E '(npx|npm exec)[^|]*[[:space:]]setup' "$1" | grep -qv -- '--dry-run'
}

has_personal_paths() {
  grep -qE '/home/[a-z]|/Users/[A-Za-z]|C:\\Users|~/\.savia/' "$1"
}

has_evidence_headings() {
  local f="$1" h
  for h in "## Observación" "## Derivación" "## Inferencia" "## Desconocido" "## Lo que no demuestra"; do
    grep -qF "$h" "$f" || return 1
  done
}

# --- AC1 ---

@test "AC1: SKILL.md existe con frontmatter y nombre correcto" {
  [ -f "$SKILL" ]
  grep -q '^name: reverse-engineering-sovereignty$' "$SKILL"
}

@test "AC1: descripcion <=200 caracteres y empieza por 'Usar cuando'" {
  d="$(sed -n 's/^description: //p' "$SKILL" | head -1)"
  [[ "$d" == "Usar cuando"* ]]
  [ "${#d}" -le 200 ]
}

@test "AC1: skill-catalog-auditor sin FAIL para la skill" {
  [ -f "$REPO_ROOT/scripts/skill-catalog-auditor.sh" ] || skip "auditor ausente"
  run bash "$REPO_ROOT/scripts/skill-catalog-auditor.sh"
  ! (echo "$output" | grep -i 'FAIL' | grep -q 'reverse-engineering-sovereignty')
}

# --- AC2 ---

@test "AC2: contiene las clases A, B, C y D" {
  has_classes "$SKILL"
}

@test "AC2: doble confirmacion para B y C" {
  has_double_confirmation "$SKILL"
  grep -E 'Clase B.*Doble confirmaci' "$SKILL"
  grep -E 'Clase C.*Doble confirmaci' "$SKILL"
}

@test "AC2: la clase D se rechaza" {
  grep -E 'Clase D.*Se rechaza' "$SKILL"
}

@test "AC2: las cinco lineas que no se cruzan estan literales" {
  has_red_lines "$SKILL"
}

@test "AC2 negativo: si falta una clase, la comprobacion falla" {
  grep -vF "Clase C" "$SKILL" > "$TMP/s.md"
  ! has_classes "$TMP/s.md"
}

@test "AC2 negativo: si falta una linea roja, la comprobacion falla" {
  grep -vF "No redistribuir el código descompilado" "$SKILL" > "$TMP/s.md"
  ! has_red_lines "$TMP/s.md"
}

@test "AC2: citas legales marcadas pendientes de verificacion" {
  grep -qF "art. 100.3 LPI" "$SKILL"
  grep -qF "art. 160 LPI" "$SKILL"
  grep -qF "pendiente de verificación con legal-compliance" "$SKILL"
  n="$(grep -cF 'pendiente de verificación con legal-compliance' "$SKILL")"
  [ "$n" -ge 3 ]
}

# --- AC3 ---

@test "AC3: ninguna orden de instalacion sin --dry-run" {
  ! has_install_without_dry_run "$SKILL"
  ! has_install_without_dry_run "$TEMPLATE"
}

@test "AC3: la skill muestra setup con --dry-run" {
  grep -qE 'rea-agents setup --dry-run' "$SKILL"
}

@test "AC3 negativo: npx setup sin --dry-run hace fallar la comprobacion" {
  printf 'ejecutar: npx rea-agents setup --yes\n' > "$TMP/s.md"
  has_install_without_dry_run "$TMP/s.md"
}

@test "AC3 negativo: npx setup con --dry-run no se marca" {
  printf 'ejecutar: npx rea-agents setup --dry-run --json\n' > "$TMP/s.md"
  ! has_install_without_dry_run "$TMP/s.md"
}

@test "AC3: sin rutas personales en skill ni plantilla" {
  ! has_personal_paths "$SKILL"
  ! has_personal_paths "$TEMPLATE"
}

@test "AC3 negativo: una ruta personal se detecta" {
  printf 'ver /home/alguien/proyecto\n' > "$TMP/s.md"
  has_personal_paths "$TMP/s.md"
}

# --- AC4 ---

@test "AC4: sovereignty-auditor documenta 'software opaco' como opcional sin peso por defecto" {
  grep -qi 'software opaco' "$SOV"
  grep -qi 'opcional' "$SOV"
  grep -qi 'sin peso por defecto' "$SOV"
}

@test "AC4: la formula del score global no cambia" {
  grep -qF 'Score = D1×0.25 + D2×0.25 + D3×0.20 + D4×0.15 + D5×0.15' "$SOV"
}

@test "AC4: sovereignty-auditor remite a la skill nueva" {
  grep -qF 'reverse-engineering-sovereignty' "$SOV"
}

@test "AC4: legacy-assess remite a la skill cuando no hay fuentes" {
  grep -qF 'reverse-engineering-sovereignty' "$LEGACY"
  grep -qi 'sin fuentes' "$LEGACY"
}

@test "AC4: el test existente de sovereignty-auditor sigue en verde" {
  command -v bats >/dev/null || skip "bats ausente"
  run bats "$REPO_ROOT/tests/test-sovereignty-auditor.bats"
  [ "$status" -eq 0 ]
}

# --- AC5 ---

@test "AC5: plantilla con encabezados de evidencia y 'Lo que no demuestra'" {
  has_evidence_headings "$TEMPLATE"
}

@test "AC5: plantilla con autorizacion/base legal y recomendaciones de salida" {
  grep -qF "## Autorización y base legal" "$TEMPLATE"
  grep -qF "## Recomendaciones de salida" "$TEMPLATE"
}

@test "AC5 negativo: sin un encabezado de evidencia la comprobacion falla" {
  grep -vF "## Inferencia" "$TEMPLATE" > "$TMP/t.md"
  ! has_evidence_headings "$TMP/t.md"
}

# --- AC6 (en el cierre de la PR; aqui solo existencia de los scripts) ---

@test "AC6: existen los scripts de cierre" {
  [ -f "$REPO_ROOT/scripts/capability-entropy.py" ]
  [ -f "$REPO_ROOT/scripts/sam.py" ]
  [ -f "$REPO_ROOT/scripts/confidentiality-scan.sh" ]
}
