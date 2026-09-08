#!/usr/bin/env bats
# tests/test-se-260-s4-receipts.bats — Tests for receipt-v2.sh.
# Ref: docs/specs/SE-260-gentle-patterns.spec.md (S4)

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/receipt-v2.sh"
TMP_REPO=""

setup() {
  [[ -x "$SCRIPT" ]] || skip "receipt-v2.sh missing"
  TMP_REPO=$(mktemp -d)
  cd "$TMP_REPO"
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > file.txt
  git add file.txt && git commit -q -m "initial"
  mkdir -p output/receipts
}

teardown() {
  [[ -n "$TMP_REPO" ]] && rm -rf "$TMP_REPO"
}

@test "S4-T01: sign creates receipt file" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  [[ -f "$TMP_REPO/output/receipts/test-branch.receipt.json" ]]
}

@test "S4-T02: sign with no paths derives from git" {
  cd "$TMP_REPO"
  echo "v2" > file.txt
  git add file.txt && git commit -q -m "change"
  bash "$SCRIPT" sign --project "$TMP_REPO" --branch test-branch
  [[ -f "$TMP_REPO/output/receipts/test-branch.receipt.json" ]]
  cd "$BATS_TEST_DIRNAME/.."
}

@test "S4-T03: verify passes when content unchanged" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  run bash "$SCRIPT" verify --project "$TMP_REPO" --branch test-branch
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "RECEIPT VALID" ]]
}

@test "S4-T04: verify fails when content changed" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  echo "changed!" > "$TMP_REPO/file.txt"
  run bash "$SCRIPT" verify --project "$TMP_REPO" --branch test-branch
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "RECEIPT STALE" ]]
}

@test "S4-T05: nonexistent receipt is graceful" {
  run bash "$SCRIPT" verify --project "$TMP_REPO" --branch no-receipt
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "no receipt found" ]]
}

@test "S4-T06: verify detects new paths outside receipt" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  echo "new" > "$TMP_REPO/newfile.txt"
  cd "$TMP_REPO" && git add newfile.txt && git commit -q -m "new file" && cd "$BATS_TEST_DIRNAME/.."
  run bash "$SCRIPT" verify --project "$TMP_REPO" --branch test-branch
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "RECEIPT VALID" ]]
  [[ "$output" =~ "new path" ]] || [[ "$output" =~ "WARN" ]]
}

@test "S4-T07: show displays receipt JSON" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  run bash "$SCRIPT" show --project "$TMP_REPO" --branch test-branch
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ '"version": 2' ]]
  [[ "$output" =~ '"tree_hash"' ]]
  [[ "$output" =~ '"paths"' ]]
}

@test "S4-T08: receipt has normalization field" {
  bash "$SCRIPT" sign --project "$TMP_REPO" --paths file.txt --branch test-branch
  run bash "$SCRIPT" show --project "$TMP_REPO" --branch test-branch
  [[ "$output" =~ "normalization" ]]
  [[ "$output" =~ "hash_method" ]]
}

@test "S4-T09: help works" {
  run bash "$SCRIPT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "Usage" ]]
}

@test "S4-T10: no arg shows error" {
  run bash "$SCRIPT"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "command required" ]]
}

@test "invalid command is rejected" {
  run bash "$SCRIPT" invalid
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"unknown option"* ]]
}

@test "safety: receipt enables nounset and pipefail" {
  run grep -q '^set -uo pipefail' "$SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "AC-4.7: G0b runs under nounset using the pr-plan ROOT" {
  run bash -c 'set -u; ROOT="$1"; BRANCH=no-receipt; source "$1/scripts/pr-plan-gates.sh"; g0b' _ \
    "$BATS_TEST_DIRNAME/.."
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"unbound variable"* ]]
}
