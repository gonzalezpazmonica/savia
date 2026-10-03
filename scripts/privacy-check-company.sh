#!/bin/bash
# privacy-check-company.sh — Privacy filter for company repo content
# Uso: bash scripts/privacy-check-company.sh <repo_dir> <handle>
#      bash scripts/privacy-check-company.sh --stdin   (scan one message)
#
# Scans company repo content before push for secrets and private data.
# Reuses validate_privacy() patterns from contribute.sh.

set -euo pipefail

# ── Constantes ──────────────────────────────────────────────────────
WORKSPACE_DIR="${PM_WORKSPACE_ROOT:-$HOME/claude}"

# ── Colores ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}ℹ${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✅${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

# ── Privacy validation (reuse patterns from contribute.sh) ─────────
check_content() {
  local content="$1"
  local violations=()

  # PATs and tokens
  echo "$content" | grep -qEi 'AKIA[0-9A-Z]{16}' && violations+=("AWS Access Key")
  echo "$content" | grep -qEi 'ghp_[a-zA-Z0-9]{36}' && violations+=("GitHub PAT")
  echo "$content" | grep -qEi 'sk-[a-zA-Z0-9]{20,}' && violations+=("API key (sk-)")
  echo "$content" | grep -qE 'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}' && violations+=("JWT token")

  # Private IPs
  echo "$content" | grep -qE '(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)' \
    && violations+=("Private IP address")

  # Connection strings
  echo "$content" | grep -qEi '(Server=.*Password=|jdbc:|mongodb\+srv://)' \
    && violations+=("Connection string")

  # Private keys (actual key content, not pubkey references).
  # -e: a pattern starting with "-" would otherwise be parsed as an option
  echo "$content" | grep -qE -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
    && violations+=("Private key content")

  printf '%s\n' "${violations[@]+"${violations[@]}"}"
}

# ── Helper: scan branch directory ──────────────────────────────────
scan_branch_dir() {
  local repo_dir="$1" handle="$2" bdir="$3" label="$4" savia_script
  savia_script="$(dirname "$0")/savia-branch.sh"
  [ ! -f "$savia_script" ] && return 0
  local items
  items=$(bash "$savia_script" list "$repo_dir" "user/$handle" "$bdir" 2>/dev/null || echo "")
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    file=$(basename "$file")   # list returns paths relative to the branch root
    local content
    content=$(bash "$savia_script" read "$repo_dir" "user/$handle" "$bdir/$file" 2>/dev/null || echo "")
    [ -z "$content" ] && continue
    local vlist=$(check_content "$content")
    while IFS= read -r v; do
      [ -n "$v" ] && echo "$label $file: $v"
    done <<< "$vlist"
  done <<< "$items"
}

# ── Scan staged files and user branch content ──────────────────────
do_scan() {
  local repo_dir="${1:?Uso: privacy-check-company.sh <repo_dir> [handle]}"
  local handle="${2:-}"
  [ ! -d "$repo_dir/.git" ] && { log_error "Not a git repo: $repo_dir"; return 1; }
  [ -z "$handle" ] && { log_error "Handle required"; return 1; }

  log_info "Scanning user branch and staged changes..."

  # Staged changes only matter when the checkout is on a pushable branch.
  # Messaging writes through temporary worktrees, so the clone normally
  # stays on main: then only the branch contents below are scanned.
  local current_branch
  current_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  local all_violations=()
  local staged_diff=""
  if [ "$current_branch" = "user/$handle" ] || [ "$current_branch" = "exchange" ]; then
    staged_diff=$(git -C "$repo_dir" diff --cached 2>/dev/null || true)
  fi
  if [ -n "$staged_diff" ]; then
    local added_lines=$(echo "$staged_diff" | grep '^+' | grep -v '^\+\+\+' || true)
    if [ -n "$added_lines" ]; then
      local vlist=$(check_content "$added_lines")
      while IFS= read -r v; do
        [ -n "$v" ] && all_violations+=("Staged: $v")
      done <<< "$vlist"
    fi
  fi

  # Scan user branch directories
  while IFS= read -r violation; do
    [ -n "$violation" ] && all_violations+=("$violation")
  done < <(scan_branch_dir "$repo_dir" "$handle" "inbox/unread" "Message")
  while IFS= read -r violation; do
    [ -n "$violation" ] && all_violations+=("$violation")
  done < <(scan_branch_dir "$repo_dir" "$handle" "documents" "Document")

  # Report violations
  if [ ${#all_violations[@]} -gt 0 ]; then
    log_error "Privacy check FAILED — ${#all_violations[@]} violation(s):"
    for v in "${all_violations[@]}"; do
      echo -e "  ${RED}•${NC} $v"
    done
    return 1
  fi

  log_ok "Privacy check PASSED"
  return 0
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"

  case "$cmd" in
    --stdin)
      local content vlist
      content=$(cat)
      vlist=$(check_content "$content")
      if [ -n "$vlist" ]; then
        log_error "Privacy check FAILED:"
        while IFS= read -r v; do echo -e "  ${RED}•${NC} $v"; done <<< "$vlist"
        return 1
      fi
      return 0
      ;;
    help|--help|-h)
      echo "privacy-check-company.sh — Privacy filter for company repo"
      echo ""
      echo "Uso: bash scripts/privacy-check-company.sh <repo_dir> <handle>"
      echo "     bash scripts/privacy-check-company.sh --stdin < message.md"
      echo ""
      echo "Scans staged changes and personal folders for secrets/private data."
      echo "Returns exit code 0 (PASS) or 1 (FAIL)."
      ;;
    *)
      do_scan "$@" ;;
  esac
}

main "$@"
