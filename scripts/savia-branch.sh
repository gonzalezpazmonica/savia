#!/bin/bash
# savia-branch.sh — Git branch abstraction layer for Company Savia v3
# Provides cross-branch read/write/list without checkout switching.
# Uses git show, git ls-tree, and temporary worktrees for writes.
#
# Usage: bash savia-branch.sh <command> [args...]
# Commands: read, list, write, move, exists, ensure-orphan, check-permission, fetch-messages

set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# ── Commit a change on a branch through a temporary worktree ──
# _branch_commit <repo> <branch> <msg> <apply_fn> [args...]
# apply_fn runs inside the worktree and stages its own changes.
# With an origin remote the base is the freshly fetched origin/<branch>
# (a stale local branch would make the push lose other members' work)
# and the result is pushed as HEAD:<branch>; a non-fast-forward
# rejection refetches and reapplies, up to 3 attempts. Any other failure
# returns 1 with the reason on stderr: a push is never swallowed.
# Without an origin remote the commit lands on the local branch.
_branch_commit() {
  local repo_dir="$1" branch="$2" msg="$3"; shift 3
  local has_remote=0 attempt base wtdir push_err head
  git -C "$repo_dir" remote get-url origin >/dev/null 2>&1 && has_remote=1
  for attempt in 1 2 3; do
    if [ "$has_remote" -eq 1 ]; then
      # Fails when the branch is not on the remote yet: the local branch
      # is then the base and the push below creates it remotely.
      git -C "$repo_dir" fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" \
        >/dev/null 2>&1 || true
    fi
    if [ "$has_remote" -eq 1 ] \
      && git -C "$repo_dir" rev-parse -q --verify "refs/remotes/origin/${branch}" >/dev/null; then
      base="origin/${branch}"
    elif git -C "$repo_dir" rev-parse -q --verify "refs/heads/${branch}" >/dev/null; then
      base="$branch"
    else
      echo "savia-branch: branch '$branch' not found in $repo_dir" >&2
      return 1
    fi
    wtdir=$(mktemp -d)
    if ! git -C "$repo_dir" worktree add -q --detach "$wtdir" "$base" >/dev/null 2>&1; then
      echo "savia-branch: cannot create worktree for $base" >&2
      rm -rf "$wtdir"
      return 1
    fi
    if ! ( cd "$wtdir" && "$@" ); then
      _branch_cleanup "$repo_dir" "$wtdir"
      return 1
    fi
    if git -C "$wtdir" diff --cached --quiet; then
      _branch_cleanup "$repo_dir" "$wtdir"   # same content: nothing to do
      return 0
    fi
    if ! git -C "$wtdir" commit -q -m "$msg" >/dev/null; then
      echo "savia-branch: commit on $branch failed" >&2
      _branch_cleanup "$repo_dir" "$wtdir"
      return 1
    fi
    head=$(git -C "$wtdir" rev-parse HEAD)
    if [ "$has_remote" -eq 0 ]; then
      git -C "$repo_dir" update-ref "refs/heads/${branch}" "$head"
      _branch_cleanup "$repo_dir" "$wtdir"
      return 0
    fi
    if push_err=$(git -C "$wtdir" push -q origin "HEAD:refs/heads/${branch}" 2>&1); then
      _branch_cleanup "$repo_dir" "$wtdir"
      _branch_sync_local "$repo_dir" "$branch" "$head"
      return 0
    fi
    _branch_cleanup "$repo_dir" "$wtdir"
    case "$push_err" in
      *"non-fast-forward"*|*"fetch first"*|*"rejected"*|*"cannot lock ref"*) continue ;;
    esac
    echo "savia-branch: push of $branch failed: $push_err" >&2
    return 1
  done
  echo "savia-branch: push of $branch rejected 3 times (concurrent writers)" >&2
  return 1
}

# Fast-forward the local branch to what was pushed, unless it is checked
# out somewhere (moving it would leave that working tree out of sync) or
# has diverged (then origin/<branch> stays the source of truth).
_branch_sync_local() {
  local repo_dir="$1" branch="$2" head="$3" old
  old=$(git -C "$repo_dir" rev-parse -q --verify "refs/heads/${branch}") || return 0
  git -C "$repo_dir" worktree list --porcelain \
    | grep -qx "branch refs/heads/${branch}" && return 0
  git -C "$repo_dir" merge-base --is-ancestor "$old" "$head" || return 0
  git -C "$repo_dir" update-ref "refs/heads/${branch}" "$head" "$old"
}

_branch_cleanup() {
  git -C "$1" worktree remove --force "$2" >/dev/null 2>&1 || rm -rf "$2"
  git -C "$1" worktree prune >/dev/null 2>&1 || true   # best effort
}

_apply_write() {
  local filepath="$1" content="$2"
  mkdir -p "$(dirname "$filepath")"
  printf '%s\n' "$content" > "$filepath"
  git add -- "$filepath"
}

_apply_move() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "savia-branch: $src does not exist" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  git mv -f -- "$src" "$dst"
}

# ── Write file to specific branch via worktree ─────────────────
do_write() {
  local repo_dir="$1" branch="$2" filepath="$3" content="$4"
  local msg="${5:-"auto: update $filepath"}"
  _branch_commit "$repo_dir" "$branch" "$msg" _apply_write "$filepath" "$content"
}

# ── Move file within a branch (one commit) ─────────────────────
do_move() {
  local repo_dir="$1" branch="$2" src="$3" dst="$4"
  local msg="${5:-"auto: move $src to $dst"}"
  _branch_commit "$repo_dir" "$branch" "$msg" _apply_move "$src" "$dst"
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
  local has_remote=0
  git -C "$repo_dir" remote get-url origin >/dev/null 2>&1 && has_remote=1
  if [ "$has_remote" -eq 1 ]; then
    # Not on the remote yet is the normal case for a new branch.
    git -C "$repo_dir" fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" \
      >/dev/null 2>&1 || true
  fi
  if do_exists "$repo_dir" "$branch"; then
    # A local branch whose first push failed must still reach the remote.
    if [ "$has_remote" -eq 1 ] \
      && ! git -C "$repo_dir" rev-parse -q --verify "refs/remotes/origin/${branch}" >/dev/null; then
      git -C "$repo_dir" push -q origin "refs/heads/${branch}:refs/heads/${branch}" \
        || { echo "savia-branch: push of $branch failed" >&2; return 1; }
    fi
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
  git commit -q -m "$msg"
  if [ "$has_remote" -eq 1 ] && ! git push -q origin "$branch"; then
    echo "savia-branch: push of $branch failed" >&2
    cd "$repo_dir"
    git -C "$repo_dir" worktree remove --force "$wtdir" 2>/dev/null || rm -rf "$wtdir"
    return 1
  fi
  cd "$repo_dir"
  git -C "$repo_dir" worktree remove "$wtdir" 2>/dev/null || rm -rf "$wtdir"
  git -C "$repo_dir" fetch origin "$branch" 2>/dev/null || true
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
  # Fresh view of the inbox: a message already delivered (unread or read)
  # is not delivered again, so reading it really empties the unread count.
  git -C "$repo_dir" fetch -q origin "+refs/heads/user/${handle}:refs/remotes/origin/user/${handle}" \
    >/dev/null 2>&1 || true   # user branch may only exist locally
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
    if do_read "$repo_dir" "user/$handle" "inbox/unread/$fname" >/dev/null 2>&1 \
      || do_read "$repo_dir" "user/$handle" "inbox/read/$fname" >/dev/null 2>&1; then
      continue
    fi
    # Deliver to user branch
    do_write "$repo_dir" "user/$handle" "inbox/unread/$fname" "$content" \
      "[user/$handle] inbox: received $fname" || return 1
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
  move)             do_move "$@" ;;
  exists)           do_exists "$@" ;;
  ensure-orphan)    do_ensure_orphan "$@" ;;
  check-permission) do_check_permission "$@" ;;
  fetch-messages)   do_fetch_messages "$@" ;;
  *) echo "Usage: savia-branch.sh {read|list|write|move|exists|ensure-orphan|check-permission|fetch-messages}" ;;
esac
