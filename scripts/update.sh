#!/bin/bash
# update.sh — Sistema de actualización de pm-workspace
# Uso: bash scripts/update.sh {check|install|status|config}
#
# Compara HEAD local con origin/main, aplica actualizaciones preservando
# datos del usuario (profiles, projects, output, config local).

set -euo pipefail

# ── Constantes ──────────────────────────────────────────────────────
WORKSPACE_DIR="${PM_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_DIR="$HOME/.pm-workspace"
CONFIG_FILE="$CONFIG_DIR/update-config"
DEFAULT_INTERVAL=604800  # 7 dias en segundos

# ── Colores ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Utilidades ──────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}i${NC}  $1"; }
log_ok()    { echo -e "${GREEN}OK${NC} $1"; }
log_warn()  { echo -e "${YELLOW}!!${NC}  $1"; }
log_error() { echo -e "${RED}ERR${NC} $1"; }

ensure_config() {
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
auto_check=true
last_check=0
check_interval=$DEFAULT_INTERVAL
EOF
  fi
}

read_config() {
  local key="$1"
  local default="${2:-}"
  if [ -f "$CONFIG_FILE" ]; then
    local val
    val=$(grep -oP "${key}=\K.*" "$CONFIG_FILE" 2>/dev/null || echo "")
    echo "${val:-$default}"
  else
    echo "$default"
  fi
}

write_config() {
  local key="$1"
  local value="$2"
  ensure_config
  if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
    SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPTS_DIR/savia-compat.sh" || true
    if command -v portable_sed_i &>/dev/null; then
      portable_sed_i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    fi
  else
    echo "${key}=${value}" >> "$CONFIG_FILE"
  fi
}

get_local_version() {
  # Read version from CHANGELOG.md first heading (authoritative)
  local changelog_ver
  changelog_ver=$(grep -oP '^\#\# \[\K[0-9]+\.[0-9]+\.[0-9]+' "$WORKSPACE_DIR/CHANGELOG.md" 2>/dev/null | head -1)
  if [ -n "$changelog_ver" ]; then
    echo "v$changelog_ver"
    return
  fi
  git -C "$WORKSPACE_DIR" describe --tags 2>/dev/null || echo "unknown"
}

get_pending_commits() {
  # Fetch first, then count commits behind origin/main
  git -C "$WORKSPACE_DIR" fetch --tags origin 2>/dev/null || {
    log_error "Error al hacer fetch. Verifica tu conexion."
    return 1
  }
  local count
  count=$(git -C "$WORKSPACE_DIR" rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
  echo "$count"
}

get_remote_version() {
  # Read version from origin/main CHANGELOG.md (no gh dependency)
  local remote_ver
  remote_ver=$(git -C "$WORKSPACE_DIR" show origin/main:CHANGELOG.md 2>/dev/null \
    | grep -oP '^\#\# \[\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ -n "$remote_ver" ]; then
    echo "v$remote_ver"
    return
  fi
  # Fallback: latest remote tag
  git -C "$WORKSPACE_DIR" ls-remote --tags origin 2>/dev/null \
    | grep -oE 'refs/tags/v[0-9.]+$' | sed 's|refs/tags/||' | sort -V | tail -1
}

# ── Datos protegidos (verificacion) ─────────────────────────────────
PROTECTED_PATHS=(
  ".claude/profiles/users"
  "projects"
  "output"
  "CLAUDE.local.md"
  "decision-log.md"
  ".claude/rules/pm-config.local.md"
)

verify_protected_data() {
  log_info "Verificando datos protegidos..."
  local all_safe=true
  for path in "${PROTECTED_PATHS[@]}"; do
    local full_path="$WORKSPACE_DIR/$path"
    if [ -e "$full_path" ]; then
      if git -C "$WORKSPACE_DIR" check-ignore -q "$full_path" 2>/dev/null; then
        log_ok "$path — protegido por .gitignore"
      else
        if [ -d "$full_path" ]; then
          log_ok "$path — directorio existente"
        else
          log_warn "$path — NO esta en .gitignore, podria verse afectado"
          all_safe=false
        fi
      fi
    fi
  done
  $all_safe
}

# ── Subcomandos ─────────────────────────────────────────────────────

do_check() {
  ensure_config
  local current
  current=$(get_local_version)
  log_info "Version local: ${CYAN}$current${NC}"

  log_info "Consultando origin/main..."
  local pending
  pending=$(get_pending_commits) || return 1

  local latest
  latest=$(get_remote_version)
  write_config "last_check" "$(date +%s)"

  if [ "$pending" = "0" ]; then
    log_ok "pm-workspace esta actualizado ($current)"
    return 0
  else
    echo ""
    echo -e "${GREEN}Nueva version disponible: ${CYAN}$current${NC} -> ${CYAN}${latest:-desconocida}${NC} (${pending} commits)${NC}"
    echo ""
    # Show recent commit subjects from origin/main
    log_info "Cambios recientes:"
    git -C "$WORKSPACE_DIR" log HEAD..origin/main --oneline --no-decorate 2>/dev/null | head -10
    echo ""
    echo -e "Ejecuta ${CYAN}/update install${NC} para actualizar."
    return 2  # 2 = update available
  fi
}

do_install() {
  ensure_config
  local current
  current=$(get_local_version)
  log_info "Version actual: $current"

  log_info "Consultando origin/main..."
  local pending
  pending=$(get_pending_commits) || return 1

  if [ "$pending" = "0" ]; then
    log_ok "Ya estas en la ultima version ($current)"
    return 0
  fi

  local latest
  latest=$(get_remote_version)
  echo ""
  echo -e "Actualizacion: ${CYAN}$current${NC} -> ${CYAN}${latest:-origin/main}${NC} (${pending} commits)"
  echo ""

  # Paso 1: Verificar datos protegidos
  verify_protected_data || {
    log_warn "Algunos datos locales podrian no estar protegidos."
  }

  # Paso 2: Verificar rama actual
  local branch
  branch=$(git -C "$WORKSPACE_DIR" branch --show-current 2>/dev/null || echo "")
  if [ "$branch" != "main" ]; then
    log_warn "Estas en rama '$branch', no en 'main'"
    log_info "Cambiando a main para actualizar..."
    git -C "$WORKSPACE_DIR" checkout main 2>/dev/null || {
      log_error "No se pudo cambiar a main. Haz checkout manualmente."
      return 1
    }
  fi

  # Paso 3: Stash cambios locales si los hay
  local had_stash=false
  local stash_output
  stash_output=$(git -C "$WORKSPACE_DIR" stash push -m "pm-workspace-update-$(date +%Y%m%d)" 2>&1)
  if echo "$stash_output" | grep -q "Saved working directory"; then
    had_stash=true
    log_info "Cambios locales guardados en stash"
  fi

  # Paso 3b: Save Savia Shield state before pull
  local prev_profile="standard"
  prev_profile=$(bash "$WORKSPACE_DIR/scripts/hook-profile.sh" get 2>/dev/null | awk '{print $1}') || prev_profile="standard"

  # Paso 4: Pull from origin/main (not a tag)
  log_info "Aplicando cambios de origin/main..."
  if ! git -C "$WORKSPACE_DIR" pull --ff-only origin main 2>/dev/null; then
    if ! git -C "$WORKSPACE_DIR" pull --no-edit origin main 2>/dev/null; then
      log_error "Conflicto de merge. Abortando actualizacion..."
      git -C "$WORKSPACE_DIR" merge --abort 2>/dev/null || true
      [ "$had_stash" = true ] && git -C "$WORKSPACE_DIR" stash pop 2>/dev/null
      log_error "La actualizacion no se pudo aplicar automaticamente."
      log_info "Puedes intentar manualmente: git pull origin main"
      return 1
    fi
  fi

  # Paso 5: Restaurar stash
  if [ "$had_stash" = true ]; then
    log_info "Restaurando cambios locales..."
    git -C "$WORKSPACE_DIR" stash pop 2>/dev/null || {
      log_warn "No se pudieron restaurar los cambios del stash automaticamente."
      log_info "Revisa con: git stash list / git stash pop"
    }
  fi

  # Paso 5a: Windows — rematerializar enlaces que el pull haya devuelto a texto
  bash "$WORKSPACE_DIR/scripts/windows-links.sh" repair --quiet 2>/dev/null \
    || log_warn "Enlaces del repositorio pendientes: bash scripts/windows-links.sh check"

  # Paso 5b: Restore Savia Shield state
  bash "$WORKSPACE_DIR/scripts/hook-profile.sh" set "$prev_profile" 2>/dev/null || true
  log_ok "Savia Shield profile restored: $prev_profile"

  # Paso 5c: Verify Responsibility Judge
  local rj_path="$WORKSPACE_DIR/.opencode/hooks/responsibility-judge.sh"
  if [[ -f "$rj_path" && -x "$rj_path" ]] && grep -q "responsibility-judge" "$WORKSPACE_DIR/.claude/settings.json" 2>/dev/null; then
    log_ok "Responsibility Judge: active"
  else
    log_warn "Responsibility Judge not found — run readiness check"
  fi

  # Paso 6: Validacion post-update
  local new_version
  new_version=$(get_local_version)

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Actualizacion completada: $current -> $new_version${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  log_ok "Tus perfiles, proyectos y configuracion local estan intactos"
  write_config "last_check" "$(date +%s)"

  # Run readiness check post-update (auto-adaptation)
  local readiness_script="$WORKSPACE_DIR/scripts/readiness-check.sh"
  if [ -f "$readiness_script" ]; then
    echo ""
    echo -e "${CYAN}Ejecutando readiness check post-update...${NC}"
    bash "$readiness_script" || log_warn "Readiness check reporto problemas. Revisa arriba."
  fi

  return 0
}

do_status() {
  ensure_config
  local current
  current=$(get_local_version)
  local auto_check
  auto_check=$(read_config "auto_check" "true")
  local last_check
  last_check=$(read_config "last_check" "0")
  local interval
  interval=$(read_config "check_interval" "$DEFAULT_INTERVAL")

  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Savia — Estado de actualizaciones${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Version actual:          ${CYAN}$current${NC}"
  echo -e "  Auto-check semanal:      $([ "$auto_check" = "true" ] && echo "${GREEN}activado${NC}" || echo "${YELLOW}desactivado${NC}")"

  if [ "$last_check" != "0" ]; then
    local last_date
    last_date=$(date -d "@$last_check" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$last_check" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "desconocida")
    local now
    now=$(date +%s)
    local days_ago=$(( (now - last_check) / 86400 ))
    echo -e "  Ultima comprobacion:     $last_date (hace ${days_ago}d)"
  else
    echo -e "  Ultima comprobacion:     ${YELLOW}nunca${NC}"
  fi

  echo -e "  Intervalo:               $((interval / 86400)) dias"
  echo -e "  Config:                  $CONFIG_FILE"
  echo ""
}

do_config() {
  local key="${1:-}"
  local value="${2:-}"
  if [ -z "$key" ] || [ -z "$value" ]; then
    echo "Uso: update.sh config <clave> <valor>"
    echo "Claves: auto_check (true|false), check_interval (segundos)"
    return 1
  fi
  ensure_config
  write_config "$key" "$value"
  log_ok "Configuracion actualizada: $key=$value"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-check}"
  shift 2>/dev/null || true

  case "$cmd" in
    check)   do_check ;;
    install) do_install ;;
    status)  do_status ;;
    config)  do_config "$@" ;;
    *)
      echo "Uso: update.sh {check|install|status|config}"
      echo ""
      echo "  check    Comprobar si hay actualizaciones disponibles"
      echo "  install  Descargar e instalar la ultima version"
      echo "  status   Mostrar estado del sistema de actualizaciones"
      echo "  config   Modificar configuracion (auto_check, check_interval)"
      return 1
      ;;
  esac
}

main "$@"
