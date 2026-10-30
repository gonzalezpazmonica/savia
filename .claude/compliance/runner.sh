#!/usr/bin/env bash
# runner.sh — Orquestador de verificación de reglas
#
# Ejecuta checks de compliance sobre ficheros staged o sobre todo el repo.
# Diseñado para ser llamado desde:
#   1. `.githooks/pre-commit` (--staged) y la CI (--range <base>..HEAD)
#   2. Manualmente: bash .claude/compliance/runner.sh --all
#   3. Comando /compliance-check
#
# A diferencia de los hooks (que son warnings), este runner BLOQUEA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
# Primero el repo del directorio actual: desde el pre-commit de git es el repo real del commit (también
# en un worktree), y CLAUDE_PROJECT_DIR apuntaría al de la sesión. Solo fuera de un repo se usa la variable.
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-$PWD}")"
MODE="${1:---staged}"
RANGE="${2:-}"
if [[ "$MODE" == "--range" && -z "$RANGE" ]]; then
  echo "❌ uso: runner.sh --range <rev-range>   (p. ej. origin/main...HEAD)" >&2
  exit 2
fi
VIOLATIONS=0
WARNINGS=0

cd "$PROJECT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  COMPLIANCE RUNNER — Verificación de reglas"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Obtener ficheros a verificar. core.quotePath=false: con el valor por defecto git devuelve los nombres no
# ASCII entre comillas y con escapes octales, y los filtros por extensión no los verían.
GITQ=(git -c core.quotePath=false)
READ_ROOT="$PROJECT_DIR"   # de dónde leen los checks el contenido de los ficheros
if [[ "$MODE" == "--all" ]]; then
  mapfile -t FILES < <("${GITQ[@]}" ls-files -- '*.md' '*.sh' 2>/dev/null)
elif [[ "$MODE" == "--range" ]]; then
  # CI: ficheros añadidos o modificados en el rango (los borrados no se verifican). Un rango que no se
  # resuelve falla cerrado: sin lista no hay verde.
  # Admite A..B y A...B; los dos extremos tienen que existir. Cualquier otra forma se rechaza.
  if [[ "$RANGE" == *...* ]]; then _left="${RANGE%%...*}"; _right="${RANGE#*...}"
  elif [[ "$RANGE" == *..* ]]; then _left="${RANGE%%..*}"; _right="${RANGE#*..}"
  else echo "❌ rango sin A..B ni A...B: $RANGE" >&2; exit 2
  fi
  for _e in "$_left" "$_right"; do
    if [[ -z "$_e" || "$_e" == *..* ]] || ! git rev-parse --verify --quiet "$_e^{commit}" >/dev/null; then
      echo "❌ rango no resoluble: $RANGE" >&2
      exit 2
    fi
  done
  if ! mapfile -t FILES < <("${GITQ[@]}" diff --name-only --diff-filter=AMR "$RANGE"; echo "rc=$?"); then exit 2; fi
  [[ "${FILES[-1]:-}" == "rc=0" ]] || { echo "❌ git diff falló sobre $RANGE" >&2; exit 2; }
  unset 'FILES[-1]'
else
  # --staged: lo que va en stage. Sin nada en stage (commit --allow-empty, --amend sin cambios) no hay
  # nada que verificar: antes se caía a HEAD~1 y se evaluaba el commit anterior.
  if ! mapfile -t FILES < <("${GITQ[@]}" diff --cached --name-only --diff-filter=ACMR; echo "rc=$?"); then exit 2; fi
  [[ "${FILES[-1]:-}" == "rc=0" ]] || { echo "❌ git diff --cached falló" >&2; exit 2; }
  unset 'FILES[-1]'
  # Los checks leen el contenido del índice, no el del árbol de trabajo: con `git add -p` o un fichero
  # editado tras el add, el árbol no es lo que se va a guardar.
  if [[ ${#FILES[@]} -gt 0 ]]; then
    READ_ROOT="$(mktemp -d)"
    trap 'rm -rf "$READ_ROOT"' EXIT
    if ! git checkout-index --prefix="$READ_ROOT/" -- "${FILES[@]}"; then
      echo "❌ no se pudo extraer el contenido en stage" >&2; exit 2
    fi
  fi
fi
cd "$READ_ROOT"

run_check() {
  local name="$1" script="$2"
  shift 2
  echo "📋 $name"
  if ! bash "$script" "$@"; then
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
  echo ""
}

# --- Check 1: CHANGELOG links de comparación ---
_changelog=0
for f in "${FILES[@]}"; do [[ "$f" == "CHANGELOG.md" ]] && _changelog=1; done
if [[ $_changelog -eq 1 || "$MODE" == "--all" ]]; then
  run_check "1. Links de comparación en CHANGELOG" \
    "$PROJECT_DIR/scripts/validate-changelog-links.sh" \
    "CHANGELOG.md"
else
  echo "📋 1. Links de comparación en CHANGELOG"
  echo "  ⏭️  CHANGELOG.md no modificado, skip"
  echo ""
fi

# --- Check 2: Tamaño de ficheros (commands, rules, skills ≤ 150) ---
CMD_RULE_FILES=()
for f in "${FILES[@]}"; do
  [[ "$f" =~ \.claude/(commands|rules|skills)/.+\.md$ ]] && CMD_RULE_FILES+=("$f")
done
if [[ ${#CMD_RULE_FILES[@]} -gt 0 ]]; then
  run_check "2. Límite de líneas (≤150)" \
    "$CHECKS_DIR/check-file-size.sh" "${CMD_RULE_FILES[@]}"
else
  echo "📋 2. Límite de líneas (≤150)"
  echo "  ⏭️  Sin comandos/reglas/skills modificados"
  echo ""
fi

# --- Check 3: Frontmatter de comandos ---
CMD_FILES=()
for f in "${FILES[@]}"; do
  # git da la ruta real (.claude/commands); .opencode/commands es un enlace a ella.
  [[ "$f" =~ ^(\.claude|\.opencode)/commands/.+\.md$ && "$f" != */references/* ]] && CMD_FILES+=("$f")
done
if [[ ${#CMD_FILES[@]} -gt 0 ]]; then
  run_check "3. Frontmatter YAML en comandos" \
    "$CHECKS_DIR/check-command-frontmatter.sh" "${CMD_FILES[@]}"
else
  echo "📋 3. Frontmatter YAML en comandos"
  echo "  ⏭️  Sin comandos modificados"
  echo ""
fi

# --- Check 4: README sync ---
run_check "4. READMEs (tamaño + sincronización)" \
  "$CHECKS_DIR/check-readme-sync.sh" "${FILES[@]}"

# --- Resumen ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $VIOLATIONS -eq 0 ]]; then
  echo "  ✅ Todas las verificaciones pasaron"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  ❌ $VIOLATIONS verificación(es) fallida(s)"
  echo ""
  echo "  Corrige las violaciones antes de hacer commit."
  echo "  Las reglas verificadas están en: docs/rules/domain/"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 2
fi
