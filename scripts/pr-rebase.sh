#!/usr/bin/env bash
# pr-rebase.sh — Rebase current PR branch onto origin/main.
#
# Use case: PR B is queued behind PR A. When A merges, B needs to rebase onto
# new main. SE-501: the confidentiality signature and the other derived files
# (scripts/derived-paths.txt) are no longer versioned, so there is no re-sign.
# A conflict limited to derived paths (a branch from before the cut) is
# resolved by removing them from the index, like scripts/derived.sh drop.
#
# Usage:
#   bash scripts/pr-rebase.sh              # rebase onto origin/main
#   bash scripts/pr-rebase.sh --no-push    # local only, don't push
#
# Exit codes:
#   0 — rebase + push successful
#   1 — working tree dirty (commit or stash first)
#   2 — rebase had conflicts outside derived paths (manual intervention needed)
#   3 — fetch or push failed
set -uo pipefail

# Opera sobre el repo del directorio actual, nunca sobre el repo donde vive el
# script: invocado desde otro directorio (p.ej. un fixture de test) hacía rebase,
# commit y push --force-with-lease de la rama activa del repo real.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
SCRIPT_DIR="${ROOT:+$ROOT/scripts}"
DO_PUSH=true
# La lista D sale del código de este script (no de la rama que se rebasa).
SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
only_derived() {  # only_derived <rutas> → 0 si todas son D (SE-501)
  local f
  # shellcheck source=derived.sh
  source "$SELF_ROOT/scripts/derived.sh" 2>/dev/null && derived_paths_load "$SELF_ROOT" || return 1
  while IFS= read -r f; do [[ -z "$f" ]] || is_derived_path "$f" || return 1; done <<<"$1"
}

for arg in "$@"; do
  case "$arg" in
    --no-push) DO_PUSH=false ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0 ;;
  esac
done

[[ -n "$ROOT" ]] || { echo "ERROR: not inside a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2

# ── Pre-flight checks ──────────────────────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  echo "ERROR: cannot rebase while on $BRANCH" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

echo "─────────────────────────────────────────────────────────────"
echo "  pr-rebase — $BRANCH onto origin/main"
echo "─────────────────────────────────────────────────────────────"

# ── Fetch latest main ──────────────────────────────────────────────────────
echo "  Fetching origin/main..."
git fetch origin main --quiet || {
  echo "ERROR: fetch failed" >&2
  exit 3
}

# ── Rebase ──────────────────────────────────────────────────────────────────
BEHIND=$(git rev-list --count HEAD..origin/main)
if [[ "$BEHIND" -eq 0 ]]; then
  echo "  Already up to date with origin/main — nothing to rebase."
else
  echo "  Rebasing $BEHIND commits from origin/main..."
  # Start rebase; it may conflict multiple times (once per queued commit
  # that touched .confidentiality-signature). Loop auto-resolving until
  # rebase completes or hits a non-signature conflict.
  git rebase origin/main >/tmp/pr-rebase-output.log 2>&1 || true

  MAX_ITER=50
  ITER=0
  while [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; do
    ITER=$((ITER + 1))
    if [[ $ITER -gt $MAX_ITER ]]; then
      echo "ERROR: rebase exceeded $MAX_ITER iterations, aborting." >&2
      git rebase --abort 2>/dev/null || true
      exit 2
    fi

    CONFLICTS=$(git diff --name-only --diff-filter=U)
    if [[ -n "$CONFLICTS" ]] && only_derived "$CONFLICTS"; then
      # SE-501: un conflicto solo en derivados (D) se resuelve sacándolos del índice, como derived.sh drop.
      while IFS= read -r f; do git rm -q --cached -- "$f" >/dev/null 2>&1; done <<<"$CONFLICTS"
      git -c core.editor=true rebase --continue >>/tmp/pr-rebase-output.log 2>&1 || true
    elif [[ -z "$CONFLICTS" ]]; then
      # Empty commit case (changes became no-op after rebase)
      git -c core.editor=true rebase --skip >>/tmp/pr-rebase-output.log 2>&1 || true
    else
      echo "ERROR: rebase conflicts not limited to derived paths (SE-501):" >&2
      echo "$CONFLICTS" | sed 's/^/  /' >&2
      echo "Run 'git rebase --abort' and resolve manually." >&2
      exit 2
    fi
  done
  echo "  Rebase complete after $ITER auto-resolution(s)."
fi

# SE-501: la firma ya no se versiona; no hay re-firma tras el rebase.

# ── Push (with lease) ──────────────────────────────────────────────────────
if $DO_PUSH; then
  echo "  Pushing with --force-with-lease..."
  if git push --force-with-lease origin "$BRANCH" 2>&1 | tail -2; then
    echo "  Done."
  else
    echo "ERROR: push failed (remote may have diverged further)." >&2
    exit 3
  fi
else
  echo "  Skipped push (--no-push)."
fi

echo "─────────────────────────────────────────────────────────────"
