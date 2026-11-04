#!/usr/bin/env bash
# resolve-all-open-prs.sh — one-shot helper that runs resolve-pr-conflicts.sh
# over every open PR whose branch has conflicts with main. Intended as the
# post-merge cleanup after a human merges a PR that advances main.
#
# Usage:
#   resolve-all-open-prs.sh [--dry-run] [--no-push]
#
# Requirements: gh, jq
# Ref: SPEC-SE-012 signal-noise reduction — removes the "merging one PR
# breaks all others" friction.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
NO_PUSH=0

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--no-push]

Rebases every open PR branch on origin/main and auto-resolves predictable
CHANGELOG/signature/.scm conflicts. Skips PRs with conflicts in other
files (human review required).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; usage; exit 2 ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI required" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

original_branch=$(git rev-parse --abbrev-ref HEAD)
git fetch origin --quiet

# Snapshot the resolver script BEFORE any branch switching — otherwise
# `scripts/resolve-pr-conflicts.sh` disappears when we checkout a peer
# branch that doesn't contain it.
# SE-501: derived.sh and the D list travel with it (never read from the peer branch).
RESOLVER_DIR=$(mktemp -d)
mkdir -p "$RESOLVER_DIR/scripts"
cp "$REPO_ROOT/scripts/resolve-pr-conflicts.sh" "$REPO_ROOT/scripts/derived.sh" \
   "$REPO_ROOT/scripts/derived-paths.txt" "$RESOLVER_DIR/scripts/"
RESOLVER_TMP="$RESOLVER_DIR/scripts/resolve-pr-conflicts.sh"
chmod +x "$RESOLVER_TMP"
trap 'rm -rf "$RESOLVER_DIR"' EXIT

# Get every open PR's head branch + mergeable state.
prs=$(gh pr list --state open --json number,headRefName,mergeable,mergeStateStatus 2>/dev/null)
pr_count=$(echo "$prs" | jq 'length')

echo "resolve-all-open-prs: $pr_count open PR(s) detected"

resolved=0
skipped=0
manual=0

echo "$prs" | jq -r '.[] | "\(.number) \(.headRefName) \(.mergeable) \(.mergeStateStatus)"' | \
while read -r num branch mergeable state; do
  echo ""
  echo "→ PR #$num ($branch) — mergeable=$mergeable state=$state"

  if [[ "$mergeable" == "MERGEABLE" && "$state" == "CLEAN" ]]; then
    echo "  SKIP (already clean)"
    continue
  fi

  if [[ "$mergeable" != "CONFLICTING" && "$state" != "DIRTY" ]]; then
    echo "  SKIP (state $mergeable/$state not conflict-actionable)"
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would: resolve-pr-conflicts.sh --branch $branch"
    continue
  fi

  git checkout "$branch" --quiet 2>&1 || {
    git checkout -b "$branch" "origin/$branch" --quiet 2>&1 || {
      echo "  ERROR: cannot checkout branch" >&2
      continue
    }
  }
  git pull origin "$branch" --ff-only --quiet 2>&1 || true

  local_extra=""
  [[ "$NO_PUSH" -eq 1 ]] && local_extra="--no-push"

  if bash "$RESOLVER_TMP" --branch "$branch" $local_extra; then
    echo "  ✅ resolved"
  else
    rc=$?
    if [[ "$rc" -eq 3 ]]; then
      echo "  ⚠️  MANUAL review required (unexpected conflicts)"
      git merge --abort 2>/dev/null || true
    else
      echo "  ❌ failure (exit $rc)"
    fi
  fi
done

git checkout "$original_branch" --quiet 2>&1 || true

echo ""
echo "resolve-all-open-prs: done. Re-run '/pr-plan' on any PR that needed manual review."
exit 0
