#!/bin/bash
# savia-flow-tasks.sh — Task management via branch isolation (PBI = task)
# Uso: savia-flow-tasks.sh {create <type> <title> [@assigned] [sprint] [priority]
#                          |move <TASK-NNNN> <todo|in-progress|review|done>
#                          |assign <TASK-NNNN> <@handle> |list}
# Tareas en <proyecto "default">/backlog/pbi-NNNN.md de la rama team/<team>.
# Exit: 0 ok · 1 sin repo / tarea o sprint inexistente · 2 uso o entrada invalida
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/savia-branch.sh"
source "$SCRIPTS_DIR/savia-compat.sh"

CONFIG_DIR="$HOME/.pm-workspace"
CONFIG_FILE="$CONFIG_DIR/company-repo"
TASKS_PROJECT="default"
# Mismo layout que savia-flow-sprint.sh
TEAM_BACKLOG_PROJECT="backlog"
SPRINT_BASE="projects/${TEAM_BACKLOG_PROJECT}/sprints"

die() { echo "❌ $2" >&2; exit "$1"; }

read_config() {
  portable_read_config "$1" "$CONFIG_FILE"
}

get_repo() {
  local path; path=$(read_config "LOCAL_PATH")
  if [ -z "$path" ] || [ ! -d "$path/.git" ]; then
    echo "❌ Sin repo de empresa: define LOCAL_PATH en $CONFIG_FILE" >&2
    return 1
  fi
  echo "$path"
}

get_team() {
  echo "${SAVIA_TEAM:-$(read_config "TEAM_NAME")}"
}

norm_handle() {
  local v="${1#@}"
  [ -z "$v" ] || [[ "$v" =~ ^[A-Za-z0-9._-]+$ && "$v" != *..* ]] || die 2 "handle invalido: '$1'"
  echo "$v"
}

_backlog() { echo "projects/$1/backlog"; }

# Fichero de una tarea por su id (TASK-NNNN -> pbi-NNNN.md); cwd = worktree de do_txn
_task_file() {
  local project="$1" task_id="$2"
  [[ "$task_id" =~ ^TASK-([0-9]{4,})$ ]] || die 2 "task_id invalido: '$task_id' (TASK-NNNN)"
  local f; f="$(_backlog "$project")/pbi-${BASH_REMATCH[1]}.md"
  if [ -f "$f" ]; then echo "$f"; fi
}

_task_write_new() {  # dentro de do_txn (cwd = team/<team> fresco): id = max existente + 1
  local project="$1" content_tpl="$2" title="$3" sprint="$4"
  local max=0 f n dir; dir=$(_backlog "$project")
  if [ -n "$sprint" ] && [ ! -f "$SPRINT_BASE/$sprint/sprint.md" ]; then
    echo "❌ sprint $sprint no existe (crealo con /flow-sprint-create)" >&2; return 1
  fi
  for f in "$dir"/pbi-*.md; do
    [ -f "$f" ] || continue
    [[ "${f##*/}" =~ ^pbi-([0-9]+)\.md$ ]] || continue
    n=$((10#${BASH_REMATCH[1]}))
    if [ "$n" -gt "$max" ]; then max=$n; fi
  done
  local task_id; task_id=$(printf "TASK-%04d" $((max + 1)))
  mkdir -p "$dir"
  printf '%s\n' "${content_tpl//@@ID@@/$task_id}" > "$dir/$(printf 'pbi-%04d.md' $((max + 1)))"
  echo "✅ Created $task_id: $title"
}

task_create() {
  local repo_dir="${1:?}" team="${2:?}" project="${3:?}" type="${4:-}" title="${5:-}"
  local assigned sprint="${7:-}" priority="${8:-medium}"
  case "$type" in task|bug|spike|subtask) ;; *) die 2 "type invalido: '$type' (task|bug|spike|subtask)" ;; esac
  title=$(printf '%s' "$title" | tr '\n"' " '")
  [ -n "${title// /}" ] || die 2 "title vacio"
  [ "${#title}" -le 100 ] || die 2 "title de ${#title} caracteres (max 100)"
  assigned=$(norm_handle "${6:-}")
  [ -n "$priority" ] || priority=medium
  case "$priority" in critical|high|medium|low) ;; *) die 2 "priority invalida: '$priority'" ;; esac
  if [ -n "$sprint" ]; then
    [[ "$sprint" =~ ^SPR-[0-9]{4}-[0-9]{2,}$ ]] || die 2 "sprint invalido: '$sprint'"
  fi
  local tpl="---
id: \"@@ID@@\"
type: \"${type}\"
title: \"${title}\"
assigned: \"${assigned}\"
sprint: \"${sprint}\"
status: \"todo\"
priority: \"${priority}\"
created: \"$(date +%Y-%m-%d)\"
---

## Description

## Acceptance Criteria

- [ ] Criterion 1"
  do_with_lock "$repo_dir" "team/$team" do_txn "$repo_dir" "team/$team" "[flow: task-create] $title" \
    _task_write_new "$project" "$tpl" "$title" "$sprint" \
    || die 1 "tarea NO creada (sprint inexistente o sin push confirmado a origin)"
}

_task_set_field() {  # dentro de do_txn: cambia un campo del frontmatter
  local project="$1" task_id="$2" field="$3" value="$4" f
  f=$(_task_file "$project" "$task_id")
  [ -n "$f" ] || { echo "❌ tarea $task_id no encontrada" >&2; return 1; }
  sed "s/^${field}: .*/${field}: \"${value}\"/" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

task_move() {
  local repo_dir="${1:?}" team="${2:?}" project="${3:?}" task_id="${4:-}" new_status="${5:-}"
  case "$new_status" in todo|in-progress|review|done) ;;
    *) die 2 "estado invalido: '$new_status' (todo|in-progress|review|done)" ;; esac
  [[ "$task_id" =~ ^TASK-[0-9]{4,}$ ]] || die 2 "task_id invalido: '$task_id' (TASK-NNNN)"
  do_with_lock "$repo_dir" "team/$team" do_txn "$repo_dir" "team/$team" "[flow: task-status] $task_id → $new_status" \
    _task_set_field "$project" "$task_id" status "$new_status" \
    || die 1 "$task_id NO actualizada (inexistente o sin push confirmado a origin)"
  echo "✅ $task_id → $new_status"
}

task_assign() {
  local repo_dir="${1:?}" team="${2:?}" project="${3:?}" task_id="${4:-}" handle
  handle=$(norm_handle "${5:-}")
  [ -n "$handle" ] || die 2 "Uso: assign <TASK-NNNN> <@handle>"
  [[ "$task_id" =~ ^TASK-[0-9]{4,}$ ]] || die 2 "task_id invalido: '$task_id' (TASK-NNNN)"
  do_with_lock "$repo_dir" "team/$team" do_txn "$repo_dir" "team/$team" "[flow: task-assigned] $task_id → $handle" \
    _task_set_field "$project" "$task_id" assigned "$handle" \
    || die 1 "$task_id NO actualizada (inexistente o sin push confirmado a origin)"
  echo "✅ $task_id → @$handle"
}

task_list() {
  local repo_dir="${1:?}" team="${2:?}" project="${3:?}" f c
  do_fetch_branch "$repo_dir" "team/$team"
  echo "📋 Tasks in $project via team/$team"
  while IFS= read -r f; do
    [[ "$(basename "$f")" =~ ^pbi-[0-9]+\.md$ ]] || continue
    c=$(do_read "$repo_dir" "team/$team" "$(_backlog "$project")/$(basename "$f")") || continue
    printf '  %s\n' "$(echo "$c" | awk -F': ' '/^(id|status|assigned|title):/ { gsub(/"/, "", $2); v[$1] = $2 }
      END { printf "%s  %-11s @%-10s %s", v["id"], v["status"], v["assigned"], v["title"] }')"
  done < <(do_list "$repo_dir" "team/$team" "$(_backlog "$project")")
}

cmd="${1:-help}"
case "$cmd" in
  create|move|assign|list)
    shift
    repo=$(get_repo) || exit 1
    team=$(get_team)
    [[ "$team" =~ ^[A-Za-z0-9._-]+$ ]] || die 1 "TEAM_NAME invalido o vacio en $CONFIG_FILE"
    "task_$cmd" "$repo" "$team" "$TASKS_PROJECT" "$@" ;;
  help|-h|--help)
    echo "Usage: savia-flow-tasks.sh <create|move|assign|list>" ;;
  *)
    echo "Usage: savia-flow-tasks.sh <create|move|assign|list>" >&2; exit 2 ;;
esac
