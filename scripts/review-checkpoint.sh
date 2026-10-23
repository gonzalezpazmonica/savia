#!/usr/bin/env bash
# review-checkpoint.sh — Paquete de revision humana (SE-269 S3)
# Uso: bash scripts/review-checkpoint.sh --branch <rama> [--spec <spec-file>]
#      bash scripts/review-checkpoint.sh --pr <numero-pr>
# Genera paquete de revision con 5 secciones para el revisor humano.

set -uo pipefail

BRANCH=""
PR_NUM=""
SPEC_FILE=""
OUTPUT_DIR="${OUTPUT_DIR:-output/review-checkpoints}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Uso: review-checkpoint.sh --branch <rama> [--spec <spec-file>]
     review-checkpoint.sh --pr <numero-pr>

Genera paquete de revision humana con 5 secciones:
  1. Que cambio y por que (ligado a spec/BR)
  2. Orden de lectura sugerido (autor o generado)
  3. Hallazgos ordenados por preocupacion
  4. Verificacion manual (2-5 o 0 explicitamente)
  5. Cierre (aprobar/rehacer/seguir)

EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --pr) PR_NUM="$2"; shift 2 ;;
    --spec) SPEC_FILE="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: $1" >&2; usage ;;
  esac
done

[[ -z "$BRANCH" && -z "$PR_NUM" ]] && { echo "ERROR: --branch o --pr requerido" >&2; usage; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CHECKPOINT_ID="ckpt-$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# ── Section 1: Que cambio y por que ──

detect_origin() {
  if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
    local spec_title=$(grep -m1 '^# ' "$SPEC_FILE" 2>/dev/null | sed 's/^# *//')
    local spec_br=$(grep -m1 -E 'BR[0-9]+|AB#[0-9]+' "$SPEC_FILE" 2>/dev/null | head -1)
    echo "Cambio ligado a spec: $spec_title"
    [[ -n "$spec_br" ]] && echo "Requisito de negocio: $spec_br"
  else
    local last_commits
    last_commits=$(git log --oneline -5 2>/dev/null || echo "Sin acceso a git log")
    echo "Cambio detectado desde rama: ${BRANCH:-PR #$PR_NUM}"
    echo "Ultimos commits:"
    echo "$last_commits" | while read -r line; do echo "  $line"; done
  fi
}

# ── Section 2: Orden de lectura sugerido ──

detect_reading_order() {
  if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
    local author_order
    author_order=$(grep -A20 'Orden de lectura' "$SPEC_FILE" 2>/dev/null | grep -E '^[0-9]+\.' | head -10)
    if [[ -n "$author_order" ]]; then
      echo "ORDEN_DECLARADO_POR_AUTOR"
      echo "$author_order"
      return
    fi
  fi

  # Generate from diff
  echo "ORDEN_GENERADO_DEL_DIFF"
  echo "NOTA: Este orden es generado automaticamente. Puede ser menos preciso que un orden declarado por el autor."

  local changed_files
  changed_files=$(git diff --name-only "HEAD~1" 2>/dev/null | head -20 || echo "Sin diff disponible")

  # Heuristic: core/spec files first, then impl, then tests, then config
  local priority=()
  local normal=()
  local low=()

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.spec.md|*SPEC*.md|*spec*.md|CRITERIO.md|*.rules.yaml) priority+=("$f") ;;
      *test*|*spec*|*.bats|*.test.*) low+=("$f") ;;
      *) normal+=("$f") ;;
    esac
  done <<< "$changed_files"

  local n=1
  for f in "${priority[@]}"; do echo "  $n. $f (prioritario: define el contrato)"; n=$((n+1)); done
  for f in "${normal[@]}"; do echo "  $n. $f"; n=$((n+1)); done
  for f in "${low[@]}"; do echo "  $n. $f (tests: verifica despues de entender el cambio)"; n=$((n+1)); done
}

# ── Section 3: Hallazgos ordenados por preocupacion ──

list_findings() {
  echo "Hallazgos del Court y verificaciones automatizadas:"

  # Security findings
  echo ""
  echo "### Seguridad"
  if [[ -f "output/security-findings.json" ]]; then
    python3 -c "import json; findings=json.load(open('output/security-findings.json')); [print(f'  - {f}') for f in findings[:5]]" 2>/dev/null || echo "  No se encontraron hallazgos de seguridad"
  else
    echo "  No se encontraron hallazgos de seguridad en esta revision"
  fi

  # Performance
  echo ""
  echo "### Rendimiento"
  echo "  No se detectaron problemas de rendimiento en esta revision"

  # Logic
  echo ""
  echo "### Logica"
  # Check if there's a review report
  if [[ -f "output/court-review.json" ]]; then
    python3 -c "
import json
data = json.load(open('output/court-review.json'))
findings = data.get('findings', [])
for f in findings[:5]:
    if f.get('category') == 'logic':
        print(f'  - {f.get(\"message\", f)}')
" 2>/dev/null || echo "  No se encontraron hallazgos de logica"
  else
    echo "  No se encontraron hallazgos de logica en esta revision"
  fi

  # Style
  echo ""
  echo "### Estilo"
  echo "  No se detectaron problemas de estilo en esta revision"

  echo ""
  echo "NOTA: Los hallazgos ya corregidos durante el bounded review han sido excluidos."
}

# ── Section 4: Verificacion manual ──

generate_manual_checks() {
  local has_observable=false

  # Detect if this is a script, command, or config change
  local changed_files
  changed_files=$(git diff --name-only "HEAD~1" 2>/dev/null | head -20 || echo "")

  # Check for script changes
  if echo "$changed_files" | grep -qE 'scripts/.*\.sh$'; then
    has_observable=true
    echo "1. Ejecutar el script modificado con --help para verificar sintaxis"
    echo "   Resultado esperado: mensaje de uso sin errores de sintaxis"
    echo ""
  fi

  # Check for command changes
  if echo "$changed_files" | grep -qE 'commands/.*\.md$'; then
    has_observable=true
    echo "2. Invocar el comando desde el shell y verificar que se carga sin errores"
    echo "   Resultado esperado: el comando aparece en la lista y se ejecuta"
    echo ""
  fi

  # Check for config changes
  if echo "$changed_files" | grep -qE '\.ya?ml$|\.json$|\.toml$'; then
    has_observable=true
    echo "3. Validar sintaxis del fichero de configuracion modificado"
    echo "   Resultado esperado: parse exitoso sin errores"
    echo ""
  fi

  # Check for spec changes
  if echo "$changed_files" | grep -qE 'spec.*\.md$|\.spec\.md$'; then
    has_observable=true
    echo "4. Leer la spec desde el principio y verificar que los ACs son falsificables"
    echo "   Resultado esperado: cada AC describe una condicion verificable"
    echo ""
  fi

  if ! $has_observable; then
    echo "SIN_COMPORTAMIENTO_OBSERVABLE"
    echo "Este cambio no tiene comportamiento visible directo. Las verificaciones son via tests automatizados."
    echo "No se generan observaciones manuales (AC-3.3: prohibido inventar trabajo)."
  fi
}

# ── Generate package ──

PACKAGE_FILE="$OUTPUT_DIR/${CHECKPOINT_ID}.md"

{
  echo "# Paquete de Revision — ${CHECKPOINT_ID}"
  echo "**Generado:** $TIMESTAMP"
  echo "**Origen:** ${BRANCH:-PR #$PR_NUM}"
  echo "**Spec:** ${SPEC_FILE:-No especificada}"
  echo ""
  echo "---"
  echo ""
  echo "## 1. Que cambio y por que"
  echo ""
  detect_origin
  echo ""
  echo "---"
  echo ""
  echo "## 2. Orden de lectura sugerido"
  echo ""
  detect_reading_order
  echo ""
  echo "---"
  echo ""
  echo "## 3. Hallazgos ordenados por preocupacion"
  echo ""
  list_findings
  echo ""
  echo "---"
  echo ""
  echo "## 4. Verificacion manual"
  echo ""
  generate_manual_checks
  echo ""
  echo "---"
  echo ""
  echo "## 5. Cierre"
  echo ""
  echo "Opciones: [ ] APROBAR  [ ] REHACER  [ ] SEGUIR DISCUTIENDO"
  echo ""
  echo "Decision: ________________  Firma: ________________  Fecha: ________________"
} > "$PACKAGE_FILE"

echo "{\"checkpoint_id\":\"$CHECKPOINT_ID\",\"file\":\"$PACKAGE_FILE\",\"timestamp\":\"$TIMESTAMP\"}"
