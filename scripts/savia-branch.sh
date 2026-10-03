#!/bin/bash
# savia-branch.sh — Git branch abstraction layer for Company Savia v3
# Provides cross-branch read/write/list without checkout switching.
# Uses git show, git ls-tree, and temporary worktrees for writes.
#
# Usage: bash savia-branch.sh <command> [args...]
# Commands: read, list, write, exists, ensure-orphan, check-permission, fetch-messages

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS_DIR/savia-compat.sh"

# ── Read file from branch without checkout ─────────────────────
do_read() {
  local repo_dir="$1" branch="$2" filepath="$3"
  git -C "$repo_dir" show "origin/${branch}:${filepath}" 2>/dev/null \
    || git -C "$repo_dir" show "${branch}:${filepath}" 2>/dev/null \
    || { echo ""; return 1; }
}

# ── List directory contents on branch ──────────────────────────
do_list() {
  local repo_dir="$1" branch="$2" dir="$3"
  git -C "$repo_dir" ls-tree --name-only \
    "origin/${branch}" -- "${dir}/" 2>/dev/null \
    || git -C "$repo_dir" ls-tree --name-only \
    "${branch}" -- "${dir}/" 2>/dev/null \
    || echo ""
}

# ── Write file to specific branch via worktree ─────────────────
do_write() {
  local repo_dir="$1" branch="$2" filepath="$3" content="$4"
  local msg="${5:-"auto: update $filepath"}"
  local wtdir
  wtdir=$(mktemp -d)
  trap "rm -rf '$wtdir'" RETURN
  git -C "$repo_dir" worktree add -f "$wtdir" "$branch" 2>/dev/null \
    || git -C "$repo_dir" worktree add -f "$wtdir" "origin/$branch" 2>/dev/null
  local dir
  dir=$(dirname "$wtdir/$filepath")
  mkdir -p "$dir"
  echo "$content" > "$wtdir/$filepath"
  git -C "$wtdir" add "$filepath"
  git -C "$wtdir" commit -m "$msg" 2>/dev/null || true
  git -C "$wtdir" push origin "$branch" 2>/dev/null || true
  git -C "$repo_dir" worktree remove "$wtdir" 2>/dev/null || rm -rf "$wtdir"
}

# ── Check if branch exists (local or remote) ──────────────────
do_exists() {
  local repo_dir="$1" branch="$2"
  git -C "$repo_dir" rev-parse --verify "origin/${branch}" >/dev/null 2>&1 \
    || git -C "$repo_dir" rev-parse --verify "${branch}" >/dev/null 2>&1
}

# ── Create orphan branch if it doesn't exist (idempotent) ─────
do_ensure_orphan() {
  local repo_dir="$1" branch="$2" msg="${3:-"init: $2 branch"}"
  if do_exists "$repo_dir" "$branch"; then
    return 0
  fi
  local wtdir
  wtdir=$(mktemp -d)
  trap "rm -rf '$wtdir'" RETURN
  git -C "$repo_dir" worktree add --detach "$wtdir" 2>/dev/null || {
    # Fallback: if no commits yet, init in place
    cd "$wtdir"
    git init && git remote add origin "$(git -C "$repo_dir" remote get-url origin)"
  }
  cd "$wtdir"
  git checkout --orphan "$branch"
  git rm -rf . 2>/dev/null || true
  echo "# $branch" > README.md
  mkdir -p .gitkeep 2>/dev/null || true
  git add README.md
  git commit -m "$msg"
  git push origin "$branch" 2>/dev/null || true
  cd "$repo_dir"
  git -C "$repo_dir" worktree remove "$wtdir" 2>/dev/null || rm -rf "$wtdir"
  git -C "$repo_dir" fetch origin "$branch" 2>/dev/null || true
}

# ── Run a read-modify-write under an exclusive per-branch lock ──
# Serializa escrituras concurrentes sobre la misma rama: sin lock, dos
# procesos leen la misma version y el ultimo do_write pisa al primero.
do_with_lock() {
  local repo_dir="$1" name="$2"; shift 2
  local common; common=$(git -C "$repo_dir" rev-parse --git-common-dir) || return 1
  case "$common" in /*) ;; *) common="$repo_dir/$common" ;; esac
  local lock="$common/savia-lock-${name//\//_}"
  if command -v flock >/dev/null 2>&1; then
    ( flock -w 60 9 || { echo "ERR lock timeout: $name" >&2; exit 75; }; "$@" ) 9>"$lock"
    return
  fi
  # Sin flock (macOS): lock por mkdir con PID; un dueño muerto libera el lock
  local tries=0 owner
  until mkdir "$lock.d" 2>/dev/null; do
    owner=$(cat "$lock.d/pid" 2>/dev/null || true)
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      echo "!! lock huerfano de PID $owner liberado: $name" >&2
      mv "$lock.d" "$lock.stale.$$" 2>/dev/null && rm -rf "$lock.stale.$$"
      continue
    fi
    tries=$((tries + 1))
    [ "$tries" -ge 600 ] && { echo "ERR lock timeout: $name" >&2; return 75; }
    sleep 0.1
  done
  echo "$$" > "$lock.d/pid"
  local rc=0
  # En segundo plano + wait: el subshell conserva set -e (con `|| rc=` se desactivaria)
  ( "$@" ) &
  wait "$!" || rc=$?
  rm -rf "$lock.d"
  return "$rc"
}

# ── Transaccion contra origin: fetch, editar, commit y push verificado ──
# do_txn <repo> <rama> <mensaje> <fn> [args...]
# Ejecuta <fn> con cwd en un worktree temporal sobre origin/<rama> recien
# traida (o vacio si la rama aun no existe). Si el push se rechaza porque
# otro clon escribio antes, repite sobre la version nueva. Nunca informa
# exito sin push confirmado: remoto inaccesible o push fallido -> rc 1.
# La salida de <fn> solo se emite si la transaccion se publica.
SAVIA_TXN_ATTEMPTS="${SAVIA_TXN_ATTEMPTS:-6}"

_txn_once() {  # 0 publicado · 10 reintentar · otro = fallo
  local repo_dir="$1" branch="$2" msg="$3" outf="$4"; shift 4
  local lr=0 wt parent="" rc=0 tree commit out
  git -C "$repo_dir" ls-remote --exit-code origin "refs/heads/$branch" >/dev/null 2>&1 || lr=$?
  case "$lr" in
    0) git -C "$repo_dir" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null \
         || { echo "ERR no se pudo traer origin/$branch" >&2; return 1; }
       parent=$(git -C "$repo_dir" rev-parse "refs/remotes/origin/$branch") ;;
    2) ;;
    *) echo "ERR remoto origin inaccesible: no se escribe nada en $branch" >&2; return 1 ;;
  esac
  wt=$(mktemp -d)
  if ! git -C "$repo_dir" worktree add -q --detach "$wt" ${parent:+"$parent"} >/dev/null 2>&1; then
    rm -rf "$wt"; echo "ERR no se pudo crear el worktree temporal" >&2; return 1
  fi
  if [ -z "$parent" ]; then
    git -C "$wt" rm -rqf --ignore-unmatch . >/dev/null 2>&1 || true  # rama nueva: arbol vacio
    find "$wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    echo "# $branch" > "$wt/README.md"
  fi
  ( cd "$wt" && "$@" ) > "$outf" &
  wait "$!" || rc=$?  # segundo plano + wait: <fn> conserva set -e
  if [ "$rc" -eq 0 ]; then
    git -C "$wt" add -A
    if [ -n "$parent" ] && git -C "$wt" diff --cached --quiet "$parent"; then
      rc=0  # sin cambios: nada que publicar
    else
      tree=$(git -C "$wt" write-tree) \
        && commit=$(git -C "$wt" commit-tree "$tree" ${parent:+-p "$parent"} -m "$msg") \
        || { echo "ERR commit fallido en $branch" >&2; rc=1; }
      if [ "$rc" -eq 0 ]; then
        out=$(git -C "$repo_dir" push --porcelain origin "$commit:refs/heads/$branch" 2>&1) || {
          if echo "$out" | grep -qE '^!.*(fetch first|non-fast-forward|stale info|failed to update ref|cannot lock ref|already exists)'; then rc=10
          else  # rechazo del servidor (hook, permisos) o red: reintentar no sirve
            echo "ERR push a origin/$branch fallido: $(echo "$out" | grep -m1 '^!' || echo "$out" | tail -1)" >&2; rc=1
          fi
        }
      fi
    fi
  fi
  git -C "$repo_dir" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git -C "$repo_dir" worktree prune >/dev/null 2>&1 || true
  [ "$rc" -eq 0 ] && git -C "$repo_dir" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null || true
  return "$rc"
}

do_txn() {
  local repo_dir="$1" branch="$2" msg="$3"; shift 3
  local outf attempt rc
  outf=$(mktemp)
  for ((attempt = 1; attempt <= SAVIA_TXN_ATTEMPTS; attempt++)); do
    rc=0
    _txn_once "$repo_dir" "$branch" "$msg" "$outf" "$@" || rc=$?
    if [ "$rc" -eq 0 ]; then cat "$outf"; rm -f "$outf"; return 0; fi
    [ "$rc" -eq 10 ] || { rm -f "$outf"; return "$rc"; }
    sleep "0.$((RANDOM % 5 + 1))"  # otro clon publico antes: reintentar sobre su version
  done
  rm -f "$outf"
  echo "ERR $branch: push rechazado $SAVIA_TXN_ATTEMPTS veces por escrituras concurrentes" >&2
  return 1
}

# ── Lectura fresca: fetch de la rama antes de do_read/do_list ──
do_fetch_branch() {
  local repo_dir="$1" branch="$2"
  git -C "$repo_dir" fetch -q origin "+refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null && return 0
  git -C "$repo_dir" ls-remote origin >/dev/null 2>&1 \
    || echo "!! origin inaccesible: se leen datos locales de $branch, posiblemente desfasados" >&2
  return 0
}

# ── Validate write permission for handle on branch ─────────────
do_check_permission() {
  local branch="$1" handle="$2" role="${3:-member}"
  case "$branch" in
    main)
      [ "$role" = "admin" ] && return 0 || return 1
      ;;
    user/*)
      local owner="${branch#user/}"
      [ "$handle" = "$owner" ] && return 0 || return 1
      ;;
    team/*)
      # Team members can push — caller verifies membership
      return 0
      ;;
    exchange)
      # Anyone can push to exchange
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ── Fetch pending messages for handle from exchange ─────────────
do_fetch_messages() {
  local repo_dir="$1" handle="$2"
  git -C "$repo_dir" fetch origin exchange 2>/dev/null || return 0
  local files
  files=$(do_list "$repo_dir" exchange "pending") || return 0
  [ -z "$files" ] && return 0
  local count=0
  while IFS= read -r fpath; do
    [ -z "$fpath" ] && continue
    local fname
    fname=$(basename "$fpath")
    local content
    content=$(do_read "$repo_dir" exchange "$fpath") || continue
    local to_field
    to_field=$(echo "$content" | grep '^to:' | head -1 \
      | sed 's/to:[[:space:]]*"\{0,1\}@\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    [ "$to_field" = "$handle" ] || continue
    # Deliver to user branch
    do_write "$repo_dir" "user/$handle" "inbox/unread/$fname" "$content" \
      "[user/$handle] inbox: received $fname"
    count=$((count + 1))
  done <<< "$files"
  echo "$count"
}

# ── Dispatcher ─────────────────────────────────────────────────
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0
cmd="${1:-help}"; shift
case "$cmd" in
  read)             do_read "$@" ;;
  list)             do_list "$@" ;;
  write)            do_write "$@" ;;
  exists)           do_exists "$@" ;;
  ensure-orphan)    do_ensure_orphan "$@" ;;
  check-permission) do_check_permission "$@" ;;
  fetch-messages)   do_fetch_messages "$@" ;;
  *) echo "Usage: savia-branch.sh {read|list|write|exists|ensure-orphan|check-permission|fetch-messages}" ;;
esac
