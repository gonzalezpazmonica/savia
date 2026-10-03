#!/bin/bash
# savia-flow-sprint.sh — Sprint lifecycle via branch isolation
# Uso: savia-flow-sprint.sh {create <goal> <inicio> <fin> [capacity_h]
#                           |close <SPR-YYYY-NN> |board <SPR-YYYY-NN> |velocity}
# Sprints del equipo en <proyecto backlog>/sprints/<id>/sprint.md de la rama team/<team>.
# Exit: 0 ok · 1 sin repo / sprint inexistente · 2 uso o entrada invalida
# Al hacer source (savia-flow.sh) solo define funciones: no ejecuta el CLI.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/savia-branch.sh"
source "$SCRIPTS_DIR/savia-compat.sh"

# Proyecto contenedor de los sprints de equipo (layout historico del repo de empresa)
TEAM_BACKLOG_PROJECT="backlog"
SPRINTS_DIR="projects/${TEAM_BACKLOG_PROJECT}/sprints"

_sprint_err() { echo "❌ $2" >&2; return "$1"; }

_sprint_field() {  # _sprint_field <campo> <contenido>
  echo "$2" | grep -m1 "^$1:" | cut -d: -f2- | sed 's/^ *//; s/^"\(.*\)"$/\1/' || true
}

_sprint_write_new() {  # dentro de do_txn (cwd = team/<team> fresco): siguiente ID del anio
  local goal="$1" start_date="$2" end_date="$3" capacity_h="$4"
  local year="${start_date:0:4}" max=0 n f
  for f in "$SPRINTS_DIR"/SPR-"$year"-*; do
    [ -d "$f" ] || continue
    [[ "${f##*/}" =~ ^SPR-${year}-([0-9]+)$ ]] || continue
    n=$((10#${BASH_REMATCH[1]}))
    if [ "$n" -gt "$max" ]; then max=$n; fi
  done
  local sprint_id; sprint_id="SPR-${year}-$(printf '%02d' $((max + 1)))"
  local sprint_content="---
id: $sprint_id
goal: $goal
start_date: $start_date
end_date: $end_date
capacity_h: $capacity_h
status: active
created: $(date +%Y-%m-%d)
closed: null
velocity: 0
---

## Sprint Goal

$goal

## Key Results

- [ ] Result 1"
  mkdir -p "$SPRINTS_DIR/$sprint_id"
  printf '%s\n' "$sprint_content" > "$SPRINTS_DIR/$sprint_id/sprint.md"
  echo "✅ Created $sprint_id: $goal"
}

sprint_create() {
  local repo_dir="${1:?}" team="${2:?}" goal="${3:-}" start_date="${4:-}" end_date="${5:-}"
  local capacity_h="${6:-120}"
  goal=$(printf '%s' "$goal" | tr '\n' ' ')
  [ -n "${goal// /}" ] || { _sprint_err 2 "goal vacio"; return; }
  portable_valid_date "$start_date" || { _sprint_err 2 "fecha de inicio invalida: '$start_date'"; return; }
  portable_valid_date "$end_date" || { _sprint_err 2 "fecha de fin invalida: '$end_date'"; return; }
  [[ ! "$start_date" > "$end_date" ]] || { _sprint_err 2 "fin ($end_date) anterior al inicio ($start_date)"; return; }
  [[ "$capacity_h" =~ ^[0-9]+$ ]] && [ "$((10#$capacity_h))" -gt 0 ] \
    || { _sprint_err 2 "capacity_h invalida: '$capacity_h' (entero > 0)"; return; }
  do_with_lock "$repo_dir" "team/$team" do_txn "$repo_dir" "team/$team" "[flow: sprint-create] $goal" \
    _sprint_write_new "$goal" "$start_date" "$end_date" "$((10#$capacity_h))" \
    || { _sprint_err 1 "sprint NO creado (sin push confirmado a origin)"; return; }
}

_sprint_check_id() {
  [[ "${1:-}" =~ ^SPR-[0-9]{4}-[0-9]{2,}$ ]] || { _sprint_err 2 "sprint_id invalido: '${1:-}' (SPR-YYYY-NN)"; return; }
}

_sprint_write_close() {  # dentro de do_txn (cwd = team/<team> fresco)
  local sprint_id="$1" f="$SPRINTS_DIR/$1/sprint.md" content
  [ -f "$f" ] || { _sprint_err 1 "Sprint $sprint_id not found"; return; }
  content=$(cat "$f")
  if [ "$(_sprint_field status "$content")" = "closed" ]; then
    echo "ℹ️  $sprint_id ya estaba cerrado ($(_sprint_field closed "$content")); sin cambios"
    return 0
  fi
  echo "$content" | sed "s/^status: .*/status: closed/; s/^closed: .*/closed: $(date +%Y-%m-%d)/" > "$f"
  echo "✅ Closed $sprint_id"
}

sprint_close() {
  local repo_dir="${1:?}" team="${2:?}" sprint_id="${3:-}"
  _sprint_check_id "$sprint_id" || return
  do_with_lock "$repo_dir" "team/$team" do_txn "$repo_dir" "team/$team" \
    "[flow: sprint-close] $sprint_id" _sprint_write_close "$sprint_id"
}

sprint_board() {
  local repo_dir="${1:?}" team="${2:?}" sprint_id="${3:-}"
  _sprint_check_id "$sprint_id" || return
  do_fetch_branch "$repo_dir" "team/$team"
  local content
  content=$(do_read "$repo_dir" "team/$team" "$SPRINTS_DIR/${sprint_id}/sprint.md") \
    || { _sprint_err 1 "Sprint $sprint_id not found"; return; }
  echo "📊 Sprint Board: $sprint_id (via team/$team)"
  local k
  for k in goal status start_date end_date capacity_h closed; do
    printf '  %-11s %s\n' "$k:" "$(_sprint_field "$k" "$content")"
  done
}

sprint_velocity() {
  local repo_dir="${1:?}" team="${2:?}" f id content
  do_fetch_branch "$repo_dir" "team/$team"
  echo "📈 Historical Velocity (via team/$team)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    id=$(basename "$f")
    content=$(do_read "$repo_dir" "team/$team" "$SPRINTS_DIR/$id/sprint.md") || continue
    printf '  %-12s %-7s velocity=%s capacity_h=%s\n' "$id" "$(_sprint_field status "$content")" \
      "$(_sprint_field velocity "$content")" "$(_sprint_field capacity_h "$content")"
  done < <(do_list "$repo_dir" "team/$team" "$SPRINTS_DIR")
}

# ── CLI (solo si se ejecuta directamente) ──────────────────────────
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

CONFIG_FILE="$HOME/.pm-workspace/company-repo"
repo=$(portable_read_config LOCAL_PATH "$CONFIG_FILE")
team="${SAVIA_TEAM:-$(portable_read_config TEAM_NAME "$CONFIG_FILE")}"
cmd="${1:-help}"; shift || true
case "$cmd" in
  create|close|board|velocity)
    [ -n "$repo" ] && [ -d "$repo/.git" ] || { echo "❌ Sin repo de empresa: define LOCAL_PATH en $CONFIG_FILE" >&2; exit 1; }
    [[ "$team" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "❌ TEAM_NAME invalido o vacio en $CONFIG_FILE" >&2; exit 1; }
    "sprint_$cmd" "$repo" "$team" "$@" ;;
  burndown)
    echo "❌ burndown no implementado: las tareas no registran horas restantes por dia" >&2; exit 2 ;;
  help|-h|--help)
    echo "Usage: savia-flow-sprint.sh <create|close|board|velocity>" ;;
  *)
    echo "Usage: savia-flow-sprint.sh <create|close|board|velocity>" >&2; exit 2 ;;
esac
