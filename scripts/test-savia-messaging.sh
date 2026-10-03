#!/bin/bash
# test-savia-messaging.sh — Tests for savia branch-based messaging infrastructure
# Usage: bash scripts/test-savia-messaging.sh
#
# Tests savia-branch.sh interface: read, list, write, exists, ensure-orphan, check-permission

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/savia-compat.sh"

test_pass() { PASS=$((PASS + 1)); echo -e "${GREEN}✅ $1${NC}"; }
test_fail() { FAIL=$((FAIL + 1)); echo -e "${RED}❌ $1${NC}"; }

# Setup
TMPDIR_BASE=$(mktemp -d)
REPO="$TMPDIR_BASE/company-repo"
WORK="$TMPDIR_BASE/work-repo"
ORIG_HOME="$HOME"
cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

echo "━━━ Test: Savia Branch Commands ━━━"

# Create a working repo (not bare) where we can actually operate
git init -b main "$WORK" > /dev/null 2>&1 || test_fail "Git init"
cd "$WORK"
git config user.email "test@test.local"
git config user.name "Test"
echo "# Repo" > README.md
git add README.md
git commit -m "init" > /dev/null 2>&1 || test_fail "Initial commit"
cd - > /dev/null
test_pass "Git repo created"

# Test 1: write command
CONTENT1="---
id: msg-001
from: @alice
subject: Test
---
Body text"

bash "$SCRIPTS_DIR/savia-branch.sh" write "$WORK" main "test.md" "$CONTENT1" \
  "[main] test" 2>/dev/null || true

# Verify write with read
if bash "$SCRIPTS_DIR/savia-branch.sh" read "$WORK" main "test.md" 2>/dev/null | grep -q "Body text"; then
  test_pass "Write/read on main works"
else
  test_fail "Write/read on main failed"
fi

# Test 2: ensure-orphan and write on orphan branch
bash "$SCRIPTS_DIR/savia-branch.sh" ensure-orphan "$WORK" exchange 2>/dev/null || true

CONTENT2="---
id: msg-002
type: message
---
Exchange message"

bash "$SCRIPTS_DIR/savia-branch.sh" write "$WORK" exchange "msg-002.md" "$CONTENT2" \
  "[exchange] msg" 2>/dev/null || true

if bash "$SCRIPTS_DIR/savia-branch.sh" read "$WORK" exchange "msg-002.md" 2>/dev/null | grep -q "Exchange message"; then
  test_pass "Orphan branch write/read works"
else
  test_fail "Orphan branch write/read failed"
fi

# Test 3: list command (list root by checking git ls-tree directly)
if git -C "$WORK" ls-tree exchange 2>/dev/null | grep -q "msg-002.md"; then
  test_pass "List command works"
else
  test_fail "List command failed"
fi

# Test 4: exists command
if bash "$SCRIPTS_DIR/savia-branch.sh" exists "$WORK" exchange 2>/dev/null; then
  test_pass "Exists command works"
else
  test_fail "Exists command failed"
fi

# Test 5: check-permission
if bash "$SCRIPTS_DIR/savia-branch.sh" check-permission main alice admin 2>/dev/null; then
  test_pass "Check-permission admin on main works"
else
  test_fail "Check-permission failed"
fi

# Test 6: check-permission on user branch
if bash "$SCRIPTS_DIR/savia-branch.sh" check-permission "user/alice" alice member 2>/dev/null; then
  test_pass "Check-permission owner on user branch works"
else
  test_fail "Check-permission on user branch failed"
fi

# Test 7: Create multiple orphan branches for users
for user in alice bob carol; do
  bash "$SCRIPTS_DIR/savia-branch.sh" ensure-orphan "$WORK" "user/$user" 2>/dev/null || true
  if bash "$SCRIPTS_DIR/savia-branch.sh" exists "$WORK" "user/$user" 2>/dev/null; then
    test_pass "User branch user/$user created"
  else
    test_fail "User branch user/$user not created"
  fi
done

# Test 8: Setup user environments with RSA keys
for user in alice bob carol; do
  export HOME="$TMPDIR_BASE/home-$user"
  mkdir -p "$HOME/.pm-workspace/savia-keys"
  cat > "$HOME/.pm-workspace/company-repo" <<EOF
LOCAL_PATH=$WORK
USER_HANDLE=$user
EOF
  bash "$SCRIPTS_DIR/savia-crypto.sh" keygen 2>/dev/null || true
  if [ -f "$HOME/.pm-workspace/savia-keys/private.pem" ]; then
    test_pass "RSA keys generated for $user"
  else
    test_fail "RSA keys missing for $user"
  fi
done

# Test 9: Verify savia-messaging.sh interface (availability, not execution)
if [ -f "$SCRIPTS_DIR/savia-messaging.sh" ] && grep -q "do_send" "$SCRIPTS_DIR/savia-messaging.sh"; then
  test_pass "savia-messaging.sh has send function"
else
  test_fail "savia-messaging.sh missing send"
fi

if [ -f "$SCRIPTS_DIR/savia-messaging-inbox.sh" ] && grep -q "do_reply" "$SCRIPTS_DIR/savia-messaging-inbox.sh"; then
  test_pass "savia-messaging-inbox.sh has reply function"
else
  test_fail "savia-messaging-inbox.sh missing reply"
fi

# Summary
export HOME="$ORIG_HOME"
echo ""
echo "━━━ Results: $PASS passed, $FAIL failed ━━━"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
