#!/usr/bin/env bash
# resolve-all-open-prs.sh — one-shot helper that runs resolve-pr-conflicts.sh
# over every open PR whose branch has conflicts with main. Intended as the
# post-merge cleanup after a human merges a PR that advances main.
#
# Usage:
#   resolve-all-open-prs.sh [--dry-run] [--no-push]
#   resolve-all-open-prs.sh --select-targets < prs.json   (ver abajo)
#
# Requirements: gh, jq
# Ref: SPEC-SE-012 signal-noise reduction — removes the "merging one PR
# breaks all others" friction.

set -uo pipefail

# ── --select-targets: qué PR tienen conflicto REAL con main ────────────────
# Lo usa .github/workflows/auto-rebase-open-prs.yml antes de tocar ninguna rama.
# Causa (2026-11-11): justo tras cada push a main GitHub devuelve
# mergeable=UNKNOWN / mergeStateStatus=UNKNOWN para todas las PR (cálculo
# perezoso). El workflow trataba UNKNOWN como rebasable e integraba main en
# TODAS las PR abiertas en cada avance de main.
# Regla: objetivo solo con mergeable=CONFLICTING o mergeStateStatus=DIRTY.
# UNKNOWN se re-consulta por rondas (`gh pr view`, que fuerza el cálculo); si
# sigue UNKNOWN, NO se toca (lo recoge el siguiente push a main o una ejecución
# manual de este script). Ante la duda, no se empuja.
# Entrada: array JSON por stdin (formato `gh pr list --json number,headRefName,
# mergeable,mergeStateStatus`). Salida: «<número> <rama>» por objetivo en
# stdout; diagnóstico en stderr. Exit 0 = decisión tomada; 2 = entrada no
# válida (fail-closed, sin objetivos).
# Entorno: AUTO_REBASE_POLL_ROUNDS (6), AUTO_REBASE_POLL_SECONDS (10), GH_BIN (gh).
select_targets() {
  local ROUNDS="${AUTO_REBASE_POLL_ROUNDS:-6}"
  local SLEEP_S="${AUTO_REBASE_POLL_SECONDS:-10}"
  local GH_BIN="${GH_BIN:-gh}"
  local input num branch m s n out round
  local -A branch_of=() verdict=() last=()
  local -a order=() pending=()

  [[ "$ROUNDS" =~ ^[0-9]+$ ]] || { echo "resolve-all-open-prs --select-targets: AUTO_REBASE_POLL_ROUNDS no numérico" >&2; return 2; }
  [[ "$SLEEP_S" =~ ^[0-9]+$ ]] || { echo "resolve-all-open-prs --select-targets: AUTO_REBASE_POLL_SECONDS no numérico" >&2; return 2; }

  input=$(cat)
  if ! jq -e 'type == "array" and all(.[]; (.number|type) == "number" and (.headRefName|type) == "string")' \
       >/dev/null 2>&1 <<<"$input"; then
    echo "resolve-all-open-prs --select-targets: entrada no válida (se esperaba array de PR de gh pr list)" >&2
    return 2
  fi

  # Clasifica un par mergeable/state: conflict | clean | unknown | other
  classify() {
    local m="$1" s="$2"
    if [[ "$m" == "CONFLICTING" || "$s" == "DIRTY" ]]; then echo conflict
    elif [[ "$m" == "UNKNOWN" || "$s" == "UNKNOWN" || -z "$m" || -z "$s" ]]; then echo unknown
    elif [[ "$m" == "MERGEABLE" && "$s" == "CLEAN" ]]; then echo clean
    else echo other
    fi
  }

  while read -r num branch m s; do
    order+=("$num")
    branch_of[$num]="$branch"
    verdict[$num]=$(classify "$m" "$s")
    last[$num]="$m/$s"
  done < <(jq -r '.[] | "\(.number) \(.headRefName) \(.mergeable // "") \(.mergeStateStatus // "")"' <<<"$input")

  round=0
  while (( round < ROUNDS )); do
    pending=()
    for n in "${order[@]}"; do [[ "${verdict[$n]}" == unknown ]] && pending+=("$n"); done
    (( ${#pending[@]} == 0 )) && break
    round=$((round + 1))
    sleep "$SLEEP_S"
    for n in "${pending[@]}"; do
      if out=$("$GH_BIN" pr view "$n" --json mergeable,mergeStateStatus \
                 --jq '"\(.mergeable // "") \(.mergeStateStatus // "")"' 2>/dev/null); then
        read -r m s <<<"$out"
        verdict[$n]=$(classify "${m:-}" "${s:-}")
        last[$n]="${m:-?}/${s:-?}"
      fi
      # Fallo de gh: se queda en unknown y se reintenta en la siguiente ronda.
    done
  done

  for n in "${order[@]}"; do
    case "${verdict[$n]}" in
      conflict) echo "PR #$n (${branch_of[$n]}) ${last[$n]} → conflicto real, se integra main" >&2
                printf '%s %s\n' "$n" "${branch_of[$n]}" ;;
      clean)    echo "PR #$n ${last[$n]} → limpia, no se toca" >&2 ;;
      unknown)  echo "PR #$n ${last[$n]} → mergeabilidad sin calcular tras $round rondas, no se toca" >&2 ;;
      *)        echo "PR #$n ${last[$n]} → sin conflicto con main, no se toca" >&2 ;;
    esac
  done
  return 0
}

if [[ "${1:-}" == "--select-targets" ]]; then
  select_targets
  exit $?
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
NO_PUSH=0

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--no-push]
       $0 --select-targets < prs.json

Rebases every open PR branch on origin/main and auto-resolves predictable
CHANGELOG/signature/.scm conflicts. Skips PRs with conflicts in other
files (human review required).

--select-targets reads the JSON of
  gh pr list --json number,headRefName,mergeable,mergeStateStatus
from stdin and prints "<number> <branch>" only for PRs with a real conflict
(CONFLICTING/DIRTY). UNKNOWN is re-polled; still UNKNOWN -> not selected.
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
