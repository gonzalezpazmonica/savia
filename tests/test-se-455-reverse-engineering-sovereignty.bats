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

# Un override fuera del repo validaria otros ficheros y daria un falso verde.
# Devuelve 1 si la ruta (fichero o directorio) no cae dentro de REPO_ROOT.
check_inside_repo() {
  local p="$1" d
  [ -d "$p" ] && d="$p" || d="$(dirname "$p")"
  d="$(cd "$d" 2>/dev/null && pwd -P)" || { echo "ruta inexistente: $1" >&2; return 1; }
  case "$d/" in
    "$REPO_ROOT"/*) ;;
    *) echo "override debe estar dentro del repo: $1" >&2; return 1 ;;
  esac
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SKILL_DIR="${REA_SKILL_DIR:-$REPO_ROOT/.claude/skills/reverse-engineering-sovereignty}"
  SOV="${SOV_SKILL_DIR:-$REPO_ROOT/.claude/skills/sovereignty-auditor}/SKILL.md"
  LEGACY="${LEGACY_CMD:-$REPO_ROOT/.claude/commands/legacy-assess.md}"
  check_inside_repo "$SKILL_DIR" && check_inside_repo "$SOV" && check_inside_repo "$LEGACY" || return 1
  SKILL="$SKILL_DIR/SKILL.md"
  TEMPLATE="$SKILL_DIR/references/plantilla-informe.md"
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

# Une las lineas continuadas con "\" para que una orden partida se evalue entera.
joined() {
  sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' "$1"
}

# Devuelve 0 si hay una orden de instalacion: un "setup" del instalador de REA
# (npx, npm exec, pnpm dlx, bunx, yarn dlx o el binario) que no lleve
# "setup --dry-run" contiguo (un "--dry-run" en un comentario no cuenta) o que
# lleve --yes/--force, o un instalador que nunca se permite (npm -g, pip, curl|sh).
has_install_without_dry_run() {
  local setup_re='(npx|npm exec|pnpm dlx|bunx|yarn dlx|rea-agents[^[:space:]]*|(^|[[:space:]])rea).*[[:space:]]setup'
  local line
  # Cada "setup" de la linea debe ir seguido de --dry-run: "setup --dry-run && ... setup" no vale.
  while IFS= read -r line; do
    [ "$(grep -oE '(^|[[:space:]])setup([[:space:]]|$)' <<<"$line" | wc -l)" -gt \
      "$(grep -oE '(^|[[:space:]])setup[[:space:]]+--dry-run' <<<"$line" | wc -l)" ] && return 0
  done < <(joined "$1" | grep -E "$setup_re")
  joined "$1" | grep -E "$setup_re" | grep -qE 'setup.*--(yes|force)' && return 0
  grep -qE 'npm (i|install) (-g|--global)|pip3? install|(curl|wget)[^|]*\|[[:space:]]*(ba|z)?sh' "$1"
}

# Devuelve 0 si alguna invocacion de rea-agents con npx no lleva version exacta
# (X.Y.Z sin sufijo). -o separa cada invocacion, tambien dentro de una misma linea.
has_unpinned_npx() {
  joined "$1" | grep -oE 'npx([[:space:]]+-[-a-z]+)*[[:space:]]+rea-agents[^[:space:]`'"'"'"),;]*' \
    | grep -qvE 'rea-agents@[0-9]+\.[0-9]+\.[0-9]+$'
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
  # Sin auditor no hay comprobacion: falla en vez de saltar (un skip seria un verde vacio).
  [ -f "$REPO_ROOT/scripts/skill-catalog-auditor.sh" ]
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

# Un registro por bullet de lista (une las lineas de continuacion).
bullets() {
  awk '/^- /{if(r)print r; r=$0; next} /^[[:space:]]+[^[:space:]]/ && r{r=r" "$0; next} {if(r)print r; r=""} END{if(r)print r}' "$1" | tr -s ' '
}

# La cita debe aparecer en algun bullet y todos los bullets que la contienen
# deben llevar su propia marca (la del encabezado o la de otro bullet no vale).
cita_pendiente() {
  local rec
  rec="$(bullets "$2" | grep -F -- "$1")" || return 1
  if grep -qvF "pendiente de verificación con legal-compliance" <<<"$rec"; then
    return 1
  fi
}

@test "AC2: cada cita legal lleva su marca de pendiente de verificacion" {
  local c
  for c in "art. 100.3 LPI" "art. 5.3 de la" "art. 100.5" "art. 6 de la" "art. 160 LPI"; do
    cita_pendiente "$c" "$SKILL" || { echo "cita sin marca: $c" >&2; return 1; }
  done
}

@test "AC2 (negativo): quitar la marca solo a una cita hace fallar esa cita y no las demas" {
  local c
  # Quita la primera marca que sigue a cada cita, dentro de su propio bullet.
  for c in "art. 100.3 LPI" "art. 100.5" "art. 160 LPI"; do
    C="$c" perl -CSD -Mutf8 -0pe 's/(\Q$ENV{C}\E[^\n]*(?:\n[ \t]+[^\n]*)*?)pendiente\s+de\s+verificación\s+con\s+legal-compliance/$1revisada/' "$SKILL" > "$TMP/s.md"
    run cita_pendiente "$c" "$TMP/s.md"
    [ "$status" -eq 1 ] || { echo "no falla sin marca: $c" >&2; return 1; }
    # las demas citas siguen intactas
    for o in "art. 100.3 LPI" "art. 100.5" "art. 160 LPI"; do
      [ "$o" = "$c" ] && continue
      cita_pendiente "$o" "$TMP/s.md" || { echo "falso rojo en $o al quitar $c" >&2; return 1; }
    done
  done
}

marcas() {
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -o '(pendiente de verificación con legal-compliance)' | wc -l
}

# Borrar la marca entera (sin dejar parentesis) es el caso que un helper sobre el
# texto unido no veia: la regex cruzaba al bullet siguiente y tomaba su marca.
@test "AC2 (negativo): borrar la marca entera de una cita no la valida con la del bullet siguiente" {
  local c
  for c in "art. 100.3 LPI" "art. 100.5"; do
    C="$c" perl -CSD -Mutf8 -0pe 's/(\Q$ENV{C}\E[^\n]*(?:\n[ \t]+[^\n]*)*?)\s*\(pendiente\s+de\s+verificación\s+con\s+legal-compliance\)/$1/' "$SKILL" > "$TMP/s.md"
    # La mutacion quita exactamente una marca.
    [ "$(marcas "$TMP/s.md")" -eq "$(( $(marcas "$SKILL") - 1 ))" ] || {
      echo "la mutacion no quito una sola marca para $c" >&2; return 1; }
    run cita_pendiente "$c" "$TMP/s.md"
    [ "$status" -eq 1 ] || { echo "no falla sin marca: $c" >&2; return 1; }
  done
}

@test "AC2 (negativo): sin ninguna marca todas las citas fallan" {
  perl -CSD -Mutf8 -0pe 's/pendiente\s+de\s+verificación\s+con\s+legal-compliance/revisada/g' "$SKILL" > "$TMP/s.md"
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

@test "override fuera del repo se rechaza con mensaje y dentro se acepta" {
  run check_inside_repo "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"debe estar dentro del repo"* ]]
  run check_inside_repo "$TMP/no-existe.md"
  [ "$status" -eq 1 ]
  run check_inside_repo "$SKILL_DIR"
  [ "$status" -eq 0 ]
  run check_inside_repo "$SOV"
  [ "$status" -eq 0 ]
}

@test "AC3 negativo: version con sufijo, comentario con --dry-run y orden partida se detectan" {
  printf 'npx rea-agents@6.7.0-beta setup --dry-run\n' > "$TMP/a.md"
  run has_unpinned_npx "$TMP/a.md"
  [ "$status" -eq 0 ]
  printf 'npx rea-agents@6.7.0 setup --dry-run; npx rea-agents setup --dry-run\n' > "$TMP/b.md"
  run has_unpinned_npx "$TMP/b.md"
  [ "$status" -eq 0 ]
  printf 'npx rea-agents@6.7.0 setup --yes # no usar --dry-run\n' > "$TMP/c.md"
  run has_install_without_dry_run "$TMP/c.md"
  [ "$status" -eq 0 ]
  printf 'npx rea-agents@6.7.0 \\\n  setup --yes\n' > "$TMP/d.md"
  run has_install_without_dry_run "$TMP/d.md"
  [ "$status" -eq 0 ]
  printf 'npx rea-agents@6.7.0 setup --dry-run && npx rea-agents@6.7.0 setup\n' > "$TMP/e.md"
  run has_install_without_dry_run "$TMP/e.md"
  [ "$status" -eq 0 ]
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
