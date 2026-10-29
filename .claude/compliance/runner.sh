#!/usr/bin/env bash
# runner.sh — Orquestador de verificación de reglas
#
# Ejecuta checks de compliance sobre ficheros staged o sobre todo el repo.
# Diseñado para ser llamado desde:
#   1. Hook PreToolUse (antes de git commit)
#   2. Manualmente: bash .claude/compliance/runner.sh --all
#   3. Comando /compliance-check
#
# A diferencia de los hooks (que son warnings), este runner BLOQUEA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# Repo evaluado: COMPLIANCE_TARGET_DIR (el que fija el gate a partir de la orden de commit); sin él, el
# de PROJECT_DIR. Los checks se ejecutan siempre desde este runner, sobre los ficheros del objetivo.
TARGET_DIR="${COMPLIANCE_TARGET_DIR:-$PROJECT_DIR}"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "❌ COMPLIANCE_TARGET_DIR no es un directorio: $TARGET_DIR" >&2
  exit 2
fi
MODE="${1:---staged}"
VIOLATIONS=0
WARNINGS=0

cd "$TARGET_DIR"
# El objetivo lo elige el texto de la orden y el gate corre antes de que la persona la apruebe: git no
# debe ejecutar nada configurado por ese repo (fsmonitor, hooks). Las consultas son de índice o de árbol
# contra árbol, nunca contra el árbol de trabajo, así que tampoco corren filtros clean/smudge.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null GIT_OPTIONAL_LOCKS=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  COMPLIANCE RUNNER — Verificación de reglas"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Obtener ficheros a verificar
if [[ "$MODE" == "--all" ]]; then
  mapfile -t FILES < <(git ls-files -- '*.md' '*.sh' 2>/dev/null)
else
  mapfile -t FILES < <(git diff --cached --name-only 2>/dev/null)
  if [[ ${#FILES[@]} -eq 0 ]]; then
    mapfile -t FILES < <(git diff --no-ext-diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
  fi
fi

run_check() {
  local name="$1" script="$2"
  shift 2
  echo "📋 $name"
  if ! bash "$script" "$@"; then
    ((VIOLATIONS++))
  fi
  echo ""
}

# --- Check 1: CHANGELOG links de comparación ---
if echo "${FILES[*]}" | grep -q "CHANGELOG.md" || [[ "$MODE" == "--all" ]]; then
  run_check "1. Links de comparación en CHANGELOG" \
    "$PROJECT_DIR/scripts/validate-changelog-links.sh" \
    "$TARGET_DIR/CHANGELOG.md"
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
  [[ "$f" =~ \.opencode/commands/.+\.md$ ]] && CMD_FILES+=("$f")
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
  "$CHECKS_DIR/check-readme-sync.sh" "${FILES[*]}"

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
