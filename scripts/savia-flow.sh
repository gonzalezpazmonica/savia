#!/bin/bash
# savia-flow.sh — Git-based project management: PBIs, sprints, boards via branch isolation
# Uso: bash scripts/savia-flow.sh {create-pbi|assign|move|log-time|sprint-start|sprint-close|board|metrics|init|help} [args]
# Team data on team/{name} branches, user data on user/{handle} branches, indexes on main

set -euo pipefail

CONFIG_DIR="$HOME/.pm-workspace"
CONFIG_FILE="$CONFIG_DIR/company-repo"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/savia-compat.sh"
source "$SCRIPTS_DIR/savia-branch.sh"

# ── Colores ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}i${NC}  $1"; }
log_ok()    { echo -e "${GREEN}OK${NC} $1"; }
log_warn()  { echo -e "${YELLOW}!!${NC}  $1"; }
log_error() { echo -e "${RED}ERR${NC} $1"; }

# ── Config helpers ──────────────────────────────────────────────────
read_config() {
  portable_read_config "$1" "$CONFIG_FILE"
}

get_repo() {
  local path
  path=$(read_config "LOCAL_PATH")
  if [ -z "$path" ] || [ ! -d "$path/.git" ]; then
    log_error "No company repo. Run /company-repo connect first."
    exit 1
  fi
  echo "$path"
}

get_handle() {
  read_config "USER_HANDLE"
}

get_team() {
  echo "${SAVIA_TEAM:-$(read_config "TEAM_NAME")}"
}

# ── Validate project exists ────────────────────────────────────────
validate_project() {
  local repo_dir="$1" project="$2"
  if [ ! -d "$repo_dir/projects/$project" ]; then
    log_error "Project '$project' not found in company repo."
    log_info "Available projects:"
    ls -1 "$repo_dir/projects/" 2>/dev/null || echo "  (none)"
    return 1
  fi
}

# ── Source operation modules ────────────────────────────────────────
source "$SCRIPTS_DIR/savia-flow-ops.sh"
source "$SCRIPTS_DIR/savia-flow-sprint.sh"
source "$SCRIPTS_DIR/savia-flow-board.sh"
source "$SCRIPTS_DIR/savia-flow-templates.sh"

# ── Adapter functions for sprint/metrics ────────────────────────────
do_sprint_start() {
  local project="${1:?}" name="${2:?}" goal="${3:?}" start="${4:?}" end="${5:?}"
  local repo_dir; repo_dir=$(get_repo)
  local team; team=$(get_team)
  validate_project "$repo_dir" "$project"
  do_ensure_orphan "$repo_dir" "team/$team" "init: team/$team" >/dev/null 2>&1
  local sprint_path="projects/$project/sprints/${name}/sprint.md"
  local sprint_content="---
id: $name
goal: $goal
start_date: $start
end_date: $end
status: \"active\"
created: $(date +%Y-%m-%d)
---
## Sprint Goal
$goal"
  do_write "$repo_dir" "team/$team" "$sprint_path" "$sprint_content" "[flow: sprint-start] $project/$name"
  echo "✅ Sprint $name started for $project on team/$team"
}

do_sprint_close() {
  local project="${1:?}"
  local repo_dir; repo_dir=$(get_repo)
  local team; team=$(get_team)
  local sprints_list; sprints_list=$(do_list "$repo_dir" "team/$team" "projects/$project/sprints")
  [ -z "$sprints_list" ] && { echo "❌ No sprints found"; return 1; }
  # El sprint activo, no el primero del listado (orden alfabetico = el mas antiguo)
  local current="" s content=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    s=$(basename "$s")
    content=$(do_read "$repo_dir" "team/$team" "projects/$project/sprints/$s/sprint.md") || continue
    if echo "$content" | grep -qE '^status: *"?active"?$'; then current="$s"; break; fi
  done <<< "$sprints_list"
  [ -n "$current" ] || { echo "❌ No active sprint"; return 1; }
  local sprint_path="projects/$project/sprints/${current}/sprint.md"
  content=$(echo "$content" | sed -E 's/^status: *"?active"?$/status: "closed"/')
  do_write "$repo_dir" "team/$team" "$sprint_path" "$content" "[flow: sprint-close] $project/$current"
  echo "✅ Sprint $current closed"
}

do_metrics() {
  local project="${1:?}"
  local repo_dir; repo_dir=$(get_repo)
  local team; team=$(get_team)
  validate_project "$repo_dir" "$project"
  do_fetch_branch "$repo_dir" "team/$team"
  local pbis; pbis=$(do_list "$repo_dir" "team/$team" "projects/$project/backlog")
  [ -z "$pbis" ] && { echo "📊 Metrics: $project (no PBIs)"; return 0; }
  # Sin pipe: el bucle corre en este shell y los contadores sobreviven
  local total=0 done_count=0 pbi content status
  while IFS= read -r pbi; do
    [ -n "$pbi" ] || continue
    content=$(do_read "$repo_dir" "team/$team" "projects/$project/backlog/$(basename "$pbi")") || continue
    total=$((total + 1))
    status=$(echo "$content" | grep -m1 "^status:" | cut -d: -f2 | tr -d ' "')
    if [ "$status" = "done" ]; then done_count=$((done_count + 1)); fi
  done <<< "$pbis"
  echo "📊 Metrics: $project | Total: $total | Done: $done_count"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    create-pbi)    do_create_pbi "$@" ;;
    assign)        do_assign "$@" ;;
    move)          do_move "$@" ;;
    log-time)      do_log_time "$@" ;;
    sprint-start)  do_sprint_start "$@" ;;
    sprint-close)  do_sprint_close "$@" ;;
    board)         do_board "$@" ;;
    metrics)       do_metrics "$@" ;;
    init-project)  do_init_project "$(get_repo)" "$@" ;;
    init-team)     do_init_team "$(get_repo)" "$@" ;;
    init-member)   do_init_member_flow "$(get_repo)" "$@" ;;
    help|*) echo "Usage: savia-flow.sh {create-pbi|assign|move|log-time|sprint-start|sprint-close|board|metrics|init-project|init-team|init-member}" ;;
  esac
}
main "$@"
