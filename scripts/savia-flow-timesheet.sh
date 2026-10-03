#!/bin/bash
# savia-flow-timesheet.sh — Time tracking via user branch
# Uso: savia-flow-timesheet.sh {log <handle> <task_id> <horas> [notas]
#                              |day <handle> [YYYY-MM-DD]
#                              |report <handle> <desde> <hasta>}
# Fichero: flow/timesheet/YYYY-MM.md en la rama user/<handle>, una linea por entrada:
#   YYYY-MM-DD HH:MM | <task_id> | <horas>h | <notas>
# Exit: 0 ok · 1 sin repo/datos · 2 uso o entrada invalida
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/savia-branch.sh"
source "$SCRIPTS_DIR/savia-compat.sh"

CONFIG_DIR="$HOME/.pm-workspace"
CONFIG_FILE="$CONFIG_DIR/company-repo"
MAX_HOURS=24

die() { echo "❌ $2" >&2; exit "$1"; }

read_config() {
  portable_read_config "$1" "$CONFIG_FILE"
}

get_repo() {
  local path; path=$(read_config "LOCAL_PATH")
  if [ -z "$path" ] || [ ! -d "$path/.git" ]; then
    echo "❌ Sin repo de empresa: define LOCAL_PATH en $CONFIG_FILE (/company-repo connect)" >&2
    return 1
  fi
  echo "$path"
}

# Valida y normaliza: quita la @ inicial; solo [A-Za-z0-9._-] (sin '..')
norm_id() {
  local kind="$1" v="${2#@}"
  [[ "$v" =~ ^[A-Za-z0-9._-]+$ && "$v" != *..* ]] || die 2 "$kind invalido: '$2'"
  echo "$v"
}

# Horas > 0 y <= MAX_HOURS; acepta coma decimal (es_ES) y la guarda con punto
norm_hours() {
  local h="${1/,/.}"
  [[ "$h" =~ ^[0-9]+(\.[0-9]{1,2})?$ ]] || die 2 "horas invalidas: '$1' (numero > 0, max 2 decimales)"
  LC_ALL=C awk -v h="$h" -v m="$MAX_HOURS" 'BEGIN { exit !(h > 0 && h <= m) }' \
    || die 2 "horas fuera de rango: '$1' (debe ser > 0 y <= $MAX_HOURS)"
  echo "$h"
}

_append_entry() {  # dentro de do_txn: cwd = worktree de user/<handle> recien traido
  local handle="$1" ts_path="$2" line="$3"
  mkdir -p "$(dirname "$ts_path")"
  local ym="${ts_path##*/}"
  [ -f "$ts_path" ] || echo "# Timesheet — @${handle} — ${ym%.md}" > "$ts_path"
  printf '%s\n' "$line" >> "$ts_path"
}

timesheet_log() {
  local repo_dir="$1"
  [ $# -ge 4 ] || die 2 "Uso: log <handle> <task_id> <horas> [notas]"
  local handle task_id hours notes
  handle=$(norm_id handle "$2")
  task_id=$(norm_id task_id "$3")
  hours=$(norm_hours "$4")
  notes=$(printf '%s' "${5:-}" | tr '\n|' ' /')
  local now; now=$(date '+%Y-%m-%d %H:%M')  # una sola lectura del reloj: fichero y linea coinciden
  local ts_path="flow/timesheet/${now:0:7}.md"
  local line="${now} | ${task_id} | ${hours}h | ${notes}"
  do_with_lock "$repo_dir" "user/$handle" do_txn "$repo_dir" "user/$handle" \
    "[flow: log-time] ${task_id}: ${hours}h" _append_entry "$handle" "$ts_path" "$line" \
    || die 1 "NO registrado: ${hours} h en $task_id (sin push confirmado a origin)"
  echo "✅ Logged ${hours} h for $task_id by @$handle"
}

timesheet_day() {
  local repo_dir="$1"
  [ $# -ge 2 ] || die 2 "Uso: day <handle> [YYYY-MM-DD]"
  local handle; handle=$(norm_id handle "$2")
  local date="${3:-$(date +%Y-%m-%d)}"
  portable_valid_date "$date" || die 2 "fecha invalida: '$date' (YYYY-MM-DD)"
  do_fetch_branch "$repo_dir" "user/$handle"
  local content
  content=$(do_read "$repo_dir" "user/$handle" "flow/timesheet/${date:0:7}.md") \
    || die 1 "No timesheet for @$handle in ${date:0:7}"
  echo "📋 Timesheet for @$handle on $date"
  echo "$content" | grep "^$date " || echo "(no entries for $date)"
}

timesheet_report() {
  local repo_dir="$1"
  [ $# -ge 4 ] || die 2 "Uso: report <handle> <desde YYYY-MM-DD> <hasta YYYY-MM-DD>"
  local handle; handle=$(norm_id handle "$2")
  local from="$3" to="$4"
  portable_valid_date "$from" || die 2 "fecha invalida: '$from'"
  portable_valid_date "$to" || die 2 "fecha invalida: '$to'"
  [[ ! "$from" > "$to" ]] || die 2 "rango invalido: $from > $to"
  do_fetch_branch "$repo_dir" "user/$handle"
  echo "📊 Timesheet Report: @$handle ($from to $to)"
  local y=$((10#${from:0:4})) m=$((10#${from:5:2})) ym all=""
  local end_ym="${to:0:7}"
  while :; do
    ym=$(printf '%04d-%02d' "$y" "$m")
    all+="$(do_read "$repo_dir" "user/$handle" "flow/timesheet/${ym}.md" 2>/dev/null || true)"$'\n'
    [ "$ym" = "$end_ym" ] && break
    m=$((m + 1)); [ "$m" -gt 12 ] && { m=1; y=$((y + 1)); }
  done
  printf '%s' "$all" | LC_ALL=C awk -F' [|] ' -v from="$from" -v to="$to" '
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / {
      d = substr($1, 1, 10)
      if (d < from || d > to) next
      h = $3; sub(/h$/, "", h)
      if (h !~ /^[0-9]+(\.[0-9]+)?$/) { bad++; next }
      print "  " $0
      if (!(($2) in sum)) order[++n] = $2
      sum[$2] += h; total += h
    }
    END {
      for (i = 1; i <= n; i++) printf "  %s: %.2f h\n", order[i], sum[order[i]]
      printf "Total: %.2f h\n", total
      if (bad) printf "Entradas ignoradas: %d (horas no numericas)\n", bad
    }'
}

cmd="${1:-help}"
case "$cmd" in
  log|day|report)
    shift
    repo=$(get_repo) || exit 1
    "timesheet_$cmd" "$repo" "$@" ;;
  help|-h|--help)
    echo "Usage: savia-flow-timesheet.sh <log|day|report>" ;;
  *)
    echo "Usage: savia-flow-timesheet.sh <log|day|report>" >&2; exit 2 ;;
esac
