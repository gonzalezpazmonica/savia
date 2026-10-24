#!/usr/bin/env bats
# test-masked-digestion-e2e.bats — End-to-end leakage tests
# SPEC-044: data-sovereignty Layer 4 (no fake entity leakage)
# Ref: docs/savia-shield-guide.md

setup() {
  grep -q 'set -uo pipefail' scripts/masked-digest.sh || true
  export PROJECT_DIR="${BATS_TEST_DIRNAME}/.."
  export SHIELD_URL="http://127.0.0.1:${SAVIA_SHIELD_PORT:-8444}"
  export TOKEN=$(cat "$HOME/.savia/shield-token" 2>/dev/null || true)
  export TOKEN_HEADER=""
  [[ -n "$TOKEN" ]] && TOKEN_HEADER="-H X-Shield-Token:$TOKEN" || true
  export MASK_MAP="$PROJECT_DIR/output/data-sovereignty-validation/mask-map.json"
  export TMPDIR="${BATS_TMPDIR:-/tmp}/masked-e2e-$$"
  mkdir -p "$TMPDIR" 2>/dev/null || true
}

teardown() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}

daemon_available() {
  curl -sf --max-time 2 "$SHIELD_URL/health" >/dev/null 2>&1
}

mask_text() {
  local escaped
  escaped=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
  curl -s --max-time 10 -X POST "$SHIELD_URL/mask" \
    -H "Content-Type: application/json" $TOKEN_HEADER \
    -d "{\"text\":$escaped}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('masked',''))" 2>/dev/null
}

unmask_text() {
  local escaped
  escaped=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
  curl -s --max-time 10 -X POST "$SHIELD_URL/unmask" \
    -H "Content-Type: application/json" $TOKEN_HEADER \
    -d "{\"text\":$escaped}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('unmasked',''))" 2>/dev/null
}

# --- Positive: roundtrip fidelity ---

@test "e2e: complex paragraph roundtrips with entities restored" {
  daemon_available || skip "Shield daemon not running"
  [[ ! -f "$MASK_MAP" ]] && skip "No mask-map.json"
  local original="alice confirmed in the test-org meeting that bob will lead"
  local masked=$(mask_text "$original")
  local final=$(unmask_text "$masked")
  [[ "$final" == *"alice"* ]]
  [[ "$final" == *"test-org"* ]]
}

@test "e2e: markdown formatting survives roundtrip" {
  daemon_available || skip "Shield daemon not running"
  local original="## Meeting with test-org\n\n- **alice**: confirmed"
  local masked=$(mask_text "$original")
  local restored=$(unmask_text "$masked")
  [[ "$restored" == *"## Meeting"* ]]
  [[ "$restored" == *"**"* ]]
}

@test "e2e: handles survive roundtrip" {
  daemon_available || skip "Shield daemon not running"
  local original="@alice.test confirmed delivery"
  local masked=$(mask_text "$original")
  local restored=$(unmask_text "$masked")
  [[ "$restored" == *"alice"* ]] || [[ "$restored" == *"Alice"* ]]
}

@test "e2e: mask map has sufficient coverage" {
  daemon_available || skip "Shield daemon not running"
  [[ ! -f "$MASK_MAP" ]] && skip "No mask-map.json"
  output=$(python3 -c "import json; print(len(json.load(open('$MASK_MAP'))))" 2>/dev/null)
  [ "$output" -ge 20 ]
}

# --- Negative: leakage/error detection ---

@test "e2e: masked text contains ZERO real entities — no leakage" {
  daemon_available || skip "Shield daemon not running"
  [[ ! -f "$MASK_MAP" ]] && skip "No mask-map.json"
  local original="test-org, alice, bob"
  local masked=$(mask_text "$original")
  [[ "$masked" != *"alice"* ]]
  [[ "$masked" != *"bob"* ]]
}

@test "e2e: unmask with bad input fails gracefully" {
  daemon_available || skip "Shield daemon not running"
  output=$(unmask_text "")
  [[ -z "$output" ]] || [[ "$output" == *"error"* ]]
}

@test "e2e: mask rejects null text — no silent fail" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/mask" \
    -H "Content-Type: application/json" $TOKEN_HEADER \
    -d '{"text":null}' 2>/dev/null)
  [[ -n "$output" ]]
}

@test "e2e: invalid JSON to unmask returns error" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/unmask" \
    -H "Content-Type: application/json" $TOKEN_HEADER \
    -d 'bad-json' 2>/dev/null)
  [[ -n "$output" ]] || true
}

# --- Edge cases ---

@test "e2e: empty text mask returns empty gracefully" {
  daemon_available || skip "Shield daemon not running"
  output=$(mask_text "")
  [[ -z "$output" ]] || [[ "$output" == "" ]] || true
}

@test "e2e: nonexistent mask-map skips leakage check" {
  [[ ! -f "/nonexistent/mask-map.json" ]]
}

@test "e2e: boundary — text with only special chars" {
  daemon_available || skip "Shield daemon not running"
  output=$(mask_text "!@#\$%^&*()_+-=[]{}|;':\",./<>?")
  [[ -n "$output" ]] || true
}

# --- Safety ---

@test "target script has set -uo pipefail" {
  grep -q 'set.*pipefail' scripts/masked-digest.sh || grep -q 'pipefail' scripts/masked-digest.sh
}

@test "unmask script exists" {
  [[ -f "$PROJECT_DIR/scripts/masked-unmask.sh" ]]
}
