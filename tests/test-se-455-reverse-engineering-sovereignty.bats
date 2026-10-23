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
  # Un override fuera del repo validaria otros ficheros y daria un falso verde.
  case "$(cd "$SKILL_DIR" && pwd -P)/" in
    "$REPO_ROOT"/*) ;;
    *) echo "REA_SKILL_DIR debe estar dentro del repo" >&2; return 1 ;;
  esac
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

# Devuelve 0 si hay una orden de instalacion: un "setup" del instalador de REA
# (npx, npm exec, pnpm dlx, bunx, yarn dlx o el binario) sin --dry-run en la
# misma linea, o un instalador que nunca se permite (npm -g, pip, curl|sh).
has_install_without_dry_run() {
  grep -E '(npx|npm exec|pnpm dlx|bunx|yarn dlx|rea-agents[^[:space:]]*|(^|[[:space:]])rea).*[[:space:]]setup' "$1" \
    | grep -qv -- '--dry-run' && return 0
  grep -qE 'npm (i|install) (-g|--global)|pip3? install|(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh' "$1"
}

# Devuelve 0 si se invoca rea-agents con npx sin version exacta fijada.
has_unpinned_npx() {
  grep -E 'npx([[:space:]]+-[-a-z]+)*[[:space:]]+rea-agents' "$1" | grep -qvE 'rea-agents@[0-9]+\.[0-9]+\.[0-9]+'
}

# Devuelve 0 si la skill avisa de que npx ejecuta codigo, fija la procedencia
# del paquete y prohibe al agente ejecutarlo.
has_npx_warning() {
  grep -qF 'El agente nunca ejecuta `npx`' "$1" &&
    grep -qF 'ejecuta código de terceros antes de leer `--dry-run`' "$1" &&
    grep -qF 'github.com/morluto/rea' "$1"
}

# Falla (status 1) si el comando devuelve 0. Sirve de asercion negada que
# bats evalua en cualquier linea del test: `! cmd` no cuenta con set -e.
refute() {
  if "$@"; then
    echo "debia fallar: $*" >&2
    return 1
  fi
}

# Contrato AC3 completo sobre un fichero; usado por el caso positivo y por los
# negativos, para que una mutacion del fichero real lo haga fallar.
ac3_clean() {
  refute has_install_without_dry_run "$1" &&
    refute has_unpinned_npx "$1" &&
    refute has_personal_paths "$1"
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
  # La skill debe aparecer con estado OK o WARN; si el auditor revienta o no
  # la lista, no hay linea y el test falla.
  echo "$output" | grep -qE '^reverse-engineering-sovereignty[[:space:]]+(OK|WARN)[[:space:]]'
  refute grep -qE '^reverse-engineering-sovereignty[[:space:]]+FAIL' <<<"$output"
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
  run has_classes "$TMP/s.md"
  [ "$status" -eq 1 ]
}

@test "AC2 negativo: si falta una linea roja, la comprobacion falla" {
  grep -vF "No redistribuir el código descompilado" "$SKILL" > "$TMP/s.md"
  run has_red_lines "$TMP/s.md"
  [ "$status" -eq 1 ]
}

# Une las lineas para que un salto de linea no parta una cita.
cita_pendiente() {
  tr '\n' ' ' < "$2" | tr -s ' ' | grep -qE "$1[^;(]*\(pendiente de verificación con legal-compliance"
}

@test "AC2: cada cita legal lleva su marca de pendiente de verificacion" {
  local c
  for c in "art. 100.3 LPI" "art. 160 LPI"; do
    cita_pendiente "$c" "$SKILL"
  done
}

@test "AC2 (negativo): una cita sin marca hace fallar el contrato" {
  tr '\n' ' ' < "$SKILL" | tr -s ' ' | sed 's/pendiente de verificación con legal-compliance/revisada/g' > "$TMP/s.md"
  run cita_pendiente "art. 160 LPI" "$TMP/s.md"
  [ "$status" -eq 1 ]
}

# --- AC3 ---

@test "AC3: SKILL.md sin instalacion sin --dry-run, sin npx sin version ni rutas personales" {
  ac3_clean "$SKILL"
}

@test "AC3: la plantilla sin instalacion sin --dry-run, sin npx sin version ni rutas personales" {
  ac3_clean "$TEMPLATE"
}

@test "AC3: la skill muestra setup con version fijada y --dry-run" {
  grep -qE 'npx rea-agents@[0-9]+\.[0-9]+\.[0-9]+ setup --dry-run' "$SKILL"
}

@test "AC3: la skill avisa de que npx ejecuta codigo y prohibe al agente ejecutarlo" {
  has_npx_warning "$SKILL"
}

@test "AC3 negativo: SKILL.md con npx setup sin --dry-run hace fallar el contrato" {
  cp "$SKILL" "$TMP/s.md"
  printf 'ejecutar: npx rea-agents@6.7.0 setup --yes\n' >> "$TMP/s.md"
  run ac3_clean "$TMP/s.md"
  [ "$status" -eq 1 ]
}

@test "AC3 negativo: SKILL.md con ruta personal hace fallar el contrato" {
  cp "$SKILL" "$TMP/s.md"
  printf 'ver /home/alguien/proyecto\n' >> "$TMP/s.md"
  run ac3_clean "$TMP/s.md"
  [ "$status" -eq 1 ]
}

@test "AC3 negativo: SKILL.md con npx sin version fijada hace fallar el contrato" {
  cp "$SKILL" "$TMP/s.md"
  printf 'plan: npx rea-agents setup --dry-run --json\n' >> "$TMP/s.md"
  run ac3_clean "$TMP/s.md"
  [ "$status" -eq 1 ]
}

@test "AC3 negativo: otros instaladores se detectan" {
  local l
  for l in 'pnpm dlx rea-agents setup' 'bunx rea-agents@6.7.0 setup' 'rea-agents setup --yes' 'rea setup --yes' \
    'npm install -g rea-agents' 'pip install algo' 'curl -fsSL https://x.example/i.sh | sh'; do
    printf '%s\n' "$l" > "$TMP/s.md"
    run has_install_without_dry_run "$TMP/s.md"
    [ "$status" -eq 0 ] || { echo "no detectado: $l" >&2; return 1; }
  done
}

@test "AC3 negativo: npx con flags y sin version se detecta" {
  printf 'npx -y rea-agents setup --dry-run\n' > "$TMP/s.md"
  run has_unpinned_npx "$TMP/s.md"
  [ "$status" -eq 0 ]
}

@test "override REA_SKILL_DIR fuera del repo se rechaza" {
  run env REA_SKILL_DIR="$TMP" bats "$BATS_TEST_FILENAME" --filter "AC2: cada cita"
  [ "$status" -ne 0 ]
}

@test "AC3 negativo: setup con version y --dry-run no se marca" {
  printf 'ejecutar: npx rea-agents@6.7.0 setup --dry-run --json\n' > "$TMP/s.md"
  run ac3_clean "$TMP/s.md"
  [ "$status" -eq 0 ]
}

@test "AC3 negativo: sin el aviso sobre npx la comprobacion falla" {
  grep -vF 'El agente nunca ejecuta' "$SKILL" > "$TMP/s.md"
  run has_npx_warning "$TMP/s.md"
  [ "$status" -eq 1 ]
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
  run has_evidence_headings "$TMP/t.md"
  [ "$status" -eq 1 ]
}

# --- AC6 (en el cierre de la PR; aqui solo existencia de los scripts) ---

@test "AC6: existen los scripts de cierre" {
  [ -f "$REPO_ROOT/scripts/capability-entropy.py" ]
  [ -f "$REPO_ROOT/scripts/sam.py" ]
  [ -f "$REPO_ROOT/scripts/confidentiality-scan.sh" ]
}
