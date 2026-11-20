#!/usr/bin/env bats
# SE-272 S1 — Tests for capex-classify.sh
# Slice 1: CAPEX/OPEX classification and capitalization evidence

setup() {
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLASSIFY_SH="$REAL_ROOT/scripts/capex-classify.sh"
  TMPDIR_CX=$(mktemp -d)
  export TMPDIR_CX
  export REPO_ROOT="$TMPDIR_CX"
  mkdir -p "$TMPDIR_CX/rules"
  cp "$REAL_ROOT/rules/capitalization.rules.yaml" "$TMPDIR_CX/rules/" 2>/dev/null || true
  export ENGAGEMENT="test-client/se272-test"
  export ENG_DIR="$REPO_ROOT/engagements/test-client/se272-test"
  mkdir -p "$ENG_DIR"
}

teardown() {
  rm -rf "$TMPDIR_CX"
}

# ──────────────────────────────────────────────────────────────────────
# 1. classify rejects invalid nature values
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects invalid nature" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "invalid_nature" \
    --asset "A001,Test Asset,development" \
    --justification "Testing validation" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" =~ capitalizable|corriente|mixta ]]
}

# ──────────────────────────────────────────────────────────────────────
# 2. classify rejects missing required arguments
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects missing --nature" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --asset "A001,Test Asset,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects missing --asset" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects missing --engagement" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "A001,Test Asset,development" \
    --justification "Testing"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 3. classify succeeds for valid capitalizable classification
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records valid capitalizable classification" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "A001,Auth Module,development" \
    --justification "New authentication module development per IAS 38" \
    --engagement "$ENGAGEMENT" \
    --actor "test-runner"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"hash"* ]]

  # Verify ledger was created
  [[ -f "$ENG_DIR/capex-ledger.jsonl" ]]
}

# ──────────────────────────────────────────────────────────────────────
# 4. classify records corriente classification
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records corriente classification" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "corriente" \
    --asset "B001,Bug Fix,operation" \
    --justification "Routine bug fix under maintenance" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 5. classify records mixta with valid split
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify records mixta with valid split" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid Module,development" \
    --justification "Partially capitalizable work" \
    --engagement "$ENGAGEMENT" \
    --split "70/30"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 6. classify rejects mixta with invalid split
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify rejects mixta with invalid split (sum != 100)" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT" \
    --split "60/50"
  [[ "$status" -ne 0 ]]
}

@test "capex-classify rejects mixta without split" {
  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" classify \
    --nature "mixta" \
    --asset "C001,Hybrid,development" \
    --justification "Testing" \
    --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# 7. ledger-show displays classification history
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-show displays entries" {
  # First add an entry
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "D001,Show Test,development" \
    --justification "For ledger display test" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-show --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CAPEX Ledger"* ]]
  [[ "$output" == *"D001"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 8. ledger-verify confirms chain integrity
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-verify confirms integrity" {
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "E001,Chain Test,development" \
    --justification "Testing chain" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "corriente" \
    --asset "E002,Chain Test 2,operation" \
    --justification "Testing chain second entry" \
    --engagement "$ENGAGEMENT"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-verify --engagement "$ENGAGEMENT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"CHAIN OK"* ]]
}

# ──────────────────────────────────────────────────────────────────────
# 9. ledger-verify detects tampering
# ──────────────────────────────────────────────────────────────────────

@test "capex-classify ledger-verify detects tampering" {
  REPO_ROOT="$TMPDIR_CX" bash "$CLASSIFY_SH" classify \
    --nature "capitalizable" \
    --asset "F001,Tamper Test,development" \
    --justification "Original entry" \
    --engagement "$ENGAGEMENT"

  # Tamper with the ledger
  local ledger="$ENG_DIR/capex-ledger.jsonl"
  echo '{"tampered":true}' >> "$ledger"

  REPO_ROOT="$TMPDIR_CX" run bash "$CLASSIFY_SH" ledger-verify --engagement "$ENGAGEMENT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"TAMPERED"* || "$output" == *"CHAIN FAIL"* ]]
}
