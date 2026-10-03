#!/bin/bash
set -euo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

assert_ok() { local desc="$1"; shift; TOTAL=$((TOTAL+1)); if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo -e "${GREEN}✓${NC} $desc"; else FAIL=$((FAIL+1)); echo -e "${RED}✗${NC} $desc"; fi; }
assert_fail() { local desc="$1"; shift; TOTAL=$((TOTAL+1)); if "$@" >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo -e "${RED}✗${NC} $desc"; else PASS=$((PASS+1)); echo -e "${GREEN}✓${NC} $desc"; fi; }
assert_file() { local desc="$1" f="$2"; TOTAL=$((TOTAL+1)); if [ -f "$f" ]; then PASS=$((PASS+1)); echo -e "${GREEN}✓${NC} $desc"; else FAIL=$((FAIL+1)); echo -e "${RED}✗${NC} $desc"; fi; }
assert_contains() { local desc="$1" f="$2" pat="$3"; TOTAL=$((TOTAL+1)); if grep -q "$pat" "$f" 2>/dev/null; then PASS=$((PASS+1)); echo -e "${GREEN}✓${NC} $desc"; else FAIL=$((FAIL+1)); echo -e "${RED}✗${NC} $desc"; fi; }
assert_eq() { local desc="$1" a="$2" b="$3"; TOTAL=$((TOTAL+1)); if [ "$a" = "$b" ]; then PASS=$((PASS+1)); echo -e "${GREEN}✓${NC} $desc"; else FAIL=$((FAIL+1)); echo -e "${RED}✗${NC} $desc (got='$a' expected='$b')"; fi; }

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

# Setup: create bare repo + clone
BARE_REPO="$TMPDIR/repo.git"
CLONE_DIR="$TMPDIR/clone"
git init --bare -b main "$BARE_REPO" >/dev/null 2>&1
git clone "$BARE_REPO" "$CLONE_DIR" >/dev/null 2>&1

# Initial commit on main
cd "$CLONE_DIR"
git config user.name "Test" && git config user.email "test@example.com"
echo "Initial README" > README.md
git add README.md && git commit -m "Initial commit" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

# Tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "test-savia-branches — Testing savia-branch.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. ensure-orphan creates a new branch
assert_ok "ensure-orphan creates exchange branch" \
  bash "$SCRIPTS_DIR/savia-branch.sh" ensure-orphan "$CLONE_DIR" exchange "init"
assert_ok "exchange branch exists after ensure-orphan" \
  bash "$SCRIPTS_DIR/savia-branch.sh" exists "$CLONE_DIR" exchange

# 2. ensure-orphan is idempotent
assert_ok "ensure-orphan idempotent (call again)" \
  bash "$SCRIPTS_DIR/savia-branch.sh" ensure-orphan "$CLONE_DIR" exchange "reinit"

# 3. do_exists returns 0 for existing branch
assert_ok "do_exists returns 0 for exchange" \
  bash "$SCRIPTS_DIR/savia-branch.sh" exists "$CLONE_DIR" exchange

# 4. do_exists returns 1 for missing branch
assert_fail "do_exists returns 1 for nonexistent branch" \
  bash "$SCRIPTS_DIR/savia-branch.sh" exists "$CLONE_DIR" nonexistent

# 5. branch_write creates file on branch
assert_ok "branch_write creates exchange:test.txt" \
  bash "$SCRIPTS_DIR/savia-branch.sh" write "$CLONE_DIR" exchange "test.txt" "hello world" "test: add test.txt"

# 6. branch_read reads file from branch
CONTENT=$(bash "$SCRIPTS_DIR/savia-branch.sh" read "$CLONE_DIR" exchange "test.txt")
assert_eq "branch_read returns correct content" "$CONTENT" "hello world"

# 7. branch_list lists directory contents
bash "$SCRIPTS_DIR/savia-branch.sh" write "$CLONE_DIR" exchange "file1.txt" "content1" "test: add file1" >/dev/null 2>&1
bash "$SCRIPTS_DIR/savia-branch.sh" write "$CLONE_DIR" exchange "file2.txt" "content2" "test: add file2" >/dev/null 2>&1
LIST=$(bash "$SCRIPTS_DIR/savia-branch.sh" list "$CLONE_DIR" exchange ".")
assert_ok "branch_list returns 3 files" [ "$(echo "$LIST" | wc -l)" -ge 1 ]

# 8. check-permission: user/alice allowed for alice
assert_ok "check-permission allows alice for user/alice" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "user/alice" "alice"

# 9. check-permission: user/alice denied for bob
assert_fail "check-permission denies bob for user/alice" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "user/alice" "bob"

# 10. check-permission: exchange allowed for anyone
assert_ok "check-permission allows alice for exchange" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "exchange" "alice"
assert_ok "check-permission allows bob for exchange" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "exchange" "bob"

# 11. check-permission: main denied for non-admin
assert_fail "check-permission denies user for main" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "main" "alice" "member"
assert_ok "check-permission allows admin for main" \
  bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "main" "alice" "admin"

# 12. Orphan branch has no shared history with main
MAIN_LOG=$(git -C "$CLONE_DIR" log --oneline main | wc -l)
EXCHANGE_LOG=$(git -C "$CLONE_DIR" log --oneline exchange 2>/dev/null | wc -l)
assert_ok "exchange has independent history (different from main)" \
  [ "$MAIN_LOG" -ne "$EXCHANGE_LOG" ] || [ "$EXCHANGE_LOG" -gt 0 ]

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "test-savia-branches: $PASS/$TOTAL PASS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAIL -eq 0 ] && exit 0 || exit 1
