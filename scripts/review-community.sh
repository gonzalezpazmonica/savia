#!/bin/bash
# review-community.sh — Revisión de PRs/issues de la comunidad (LOCAL ONLY)
# Uso: bash scripts/review-community.sh {pending|review|merge|release|summary}
#
# Protocolo privado de la usuaria para gestionar contribuciones comunitarias.
# Este fichero NO se sube a GitHub (debe estar en .gitignore o CLAUDE.local.md).

set -euo pipefail

# ── Constantes ──────────────────────────────────────────────────────
REPO_OWNER="gonzalezpazmonica"
REPO_NAME="pm-workspace"
REPO_FULL="$REPO_OWNER/$REPO_NAME"
WORKSPACE_DIR="${PM_WORKSPACE_ROOT:-$HOME/claude}"

# ── Colores ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Utilidades ──────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}ℹ${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✅${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

check_gh() {
  if ! command -v gh &>/dev/null; then
    log_error "gh CLI no instalado"
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    log_error "gh CLI no autenticado"
    exit 1
  fi
}

# ── Listar PRs/issues pendientes ───────────────────────────────────
do_pending() {
  check_gh
  echo -e "${CYAN}━━━ PRs pendientes de revisión ━━━${NC}"
  gh pr list --repo "$REPO_FULL" --state open --label "community" --json number,title,author,createdAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{.author.login}}, {{timeago .createdAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"

  echo ""
  echo -e "${CYAN}━━━ Issues pendientes ━━━${NC}"
  gh issue list --repo "$REPO_FULL" --state open --label "community" --json number,title,author,createdAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{.author.login}}, {{timeago .createdAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"

  echo ""
  echo -e "${CYAN}━━━ Issues sin label community ━━━${NC}"
  gh issue list --repo "$REPO_FULL" --state open --json number,title,labels,createdAt \
    --template '{{range .}}#{{.number}} {{.title}} [{{range .labels}}{{.name}} {{end}}] ({{timeago .createdAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"
}

# ── Revisar un PR ───────────────────────────────────────────────────
do_review() {
  local pr_number="${1:?Uso: review-community.sh review {número_pr}}"
  check_gh

  echo -e "${CYAN}━━━ Revisión del PR #$pr_number ━━━${NC}"
  echo ""

  # Info del PR
  log_info "Información del PR:"
  gh pr view "$pr_number" --repo "$REPO_FULL" 2>&1

  echo ""
  log_info "Diff del PR:"
  gh pr diff "$pr_number" --repo "$REPO_FULL" 2>&1

  echo ""
  log_info "Ficheros cambiados:"
  CHANGED_FILES=$(gh pr diff "$pr_number" --repo "$REPO_FULL" --name-only 2>&1)
  echo "$CHANGED_FILES"

  # Validar comandos si hay cambios en commands/
  if echo "$CHANGED_FILES" | grep -q "commands/"; then
    echo ""
    log_info "Ejecutando validate-commands.sh..."
    bash "$WORKSPACE_DIR/scripts/validate-commands.sh" 2>&1 || log_warn "Validación con errores"
  fi

  # Buscar patterns de secrets en el diff
  echo ""
  log_info "Buscando secrets en el diff..."
  local diff_content
  diff_content=$(gh pr diff "$pr_number" --repo "$REPO_FULL" 2>&1)
  if echo "$diff_content" | grep -qEi '(AKIA|ghp_|sk-|eyJ[a-zA-Z0-9]|password\s*=|api_key\s*=)'; then
    log_error "¡POSIBLES SECRETS DETECTADOS EN EL DIFF!"
    echo "$diff_content" | grep -nEi '(AKIA|ghp_|sk-|eyJ[a-zA-Z0-9]|password\s*=|api_key\s*=)'
  else
    log_ok "Sin secrets detectados en el diff"
  fi
}

# ── Merge de un PR ──────────────────────────────────────────────────
# Retirado: este subcomando fusionaba sin permiso firmado de la persona, sin
# comprobar la revisión y sin atar la fusión al commit revisado (ruta A09 del
# inventario de rutas de efecto). Las fusiones van solo por el camino con
# permiso. No llama a ninguna API: rehúsa y sale con 3.
do_merge() {
  log_error "review-community.sh merge está retirado: fusionaba sin permiso firmado."
  log_info "Para fusionar una PR usa scripts/merge-sprint.sh (revisión registrada y permiso de la persona)."
  exit 3
}

# ── Crear release ───────────────────────────────────────────────────
do_release() {
  local version="${1:?Uso: review-community.sh release {versión}}"
  check_gh

  log_info "Preparando release $version..."

  # Verificar que estamos en main
  local current_branch
  current_branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null)
  if [ "$current_branch" != "main" ]; then
    log_warn "No estás en main (actual: $current_branch)"
    log_info "Cambia a main antes de hacer release"
    return 1
  fi

  # Tag
  log_info "Creando tag v$version..."
  git -C "$WORKSPACE_DIR" tag -a "v$version" -m "v$version"
  git -C "$WORKSPACE_DIR" push origin "v$version"

  # Release
  log_info "Creando GitHub release..."
  gh release create "v$version" \
    --repo "$REPO_FULL" \
    --title "v$version" \
    --generate-notes 2>&1

  log_ok "Release v$version creada"
}

# ── Resumen semanal ─────────────────────────────────────────────────
do_summary() {
  check_gh

  echo -e "${CYAN}━━━ Resumen semanal de actividad ━━━${NC}"
  local since_date
  since_date=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null || echo "")

  echo ""
  echo -e "${GREEN}PRs mergeados (última semana):${NC}"
  gh pr list --repo "$REPO_FULL" --state merged --json number,title,mergedAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{timeago .mergedAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"

  echo ""
  echo -e "${RED}Issues cerrados (última semana):${NC}"
  gh issue list --repo "$REPO_FULL" --state closed --json number,title,closedAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{timeago .closedAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"

  echo ""
  echo -e "${YELLOW}Issues nuevos (abiertos):${NC}"
  gh issue list --repo "$REPO_FULL" --state open --json number,title,createdAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{timeago .createdAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"

  echo ""
  echo -e "${BLUE}PRs abiertos pendientes:${NC}"
  gh pr list --repo "$REPO_FULL" --state open --json number,title,createdAt \
    --template '{{range .}}#{{.number}} {{.title}} ({{timeago .createdAt}}){{"\n"}}{{end}}' 2>&1 || echo "  (ninguno)"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    pending) do_pending ;;
    review)  do_review "$@" ;;
    merge)   do_merge "$@" ;;
    release) do_release "$@" ;;
    summary) do_summary ;;
    help|*)
      echo "review-community.sh — Revisión de contribuciones comunitarias"
      echo ""
      echo "Uso: bash scripts/review-community.sh {comando} [args]"
      echo ""
      echo "Comandos:"
      echo "  pending              — Listar PRs/issues pendientes"
      echo "  review {pr_number}   — Revisar un PR (diff, validate, secrets)"
      echo "  merge {pr_number}    — Merge squash de un PR"
      echo "  release {version}    — Crear tag y GitHub release"
      echo "  summary              — Resumen semanal de actividad"
      echo "  help                 — Esta ayuda"
      ;;
  esac
}

main "$@"
