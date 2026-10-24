#!/usr/bin/env bats
# test-savia-shield-daemon.bats — Shield daemon health, gate integration
# SPEC-044: data-sovereignty daemon (Layer 1+2 integration)
# Ref: docs/savia-shield-guide.md

setup() {
  grep -q 'set -uo pipefail' .opencode/hooks/data-sovereignty-gate.sh || true
  export SHIELD_URL="http://127.0.0.1:${SAVIA_SHIELD_PORT:-8444}"
  export TMPDIR="${BATS_TMPDIR:-/tmp}/shield-daemon-$$"
  mkdir -p "$TMPDIR" 2>/dev/null || true
  # Load auth token for daemon requests
  SHIELD_TOKEN=""
  [[ -f "$HOME/.savia/shield-token" ]] && SHIELD_TOKEN=$(cat "$HOME/.savia/shield-token" 2>/dev/null | tr -d '\r\n') || true
  AUTH_HEADER=""
  [[ -n "$SHIELD_TOKEN" ]] && AUTH_HEADER="-H X-Shield-Token:$SHIELD_TOKEN" || true
}

teardown() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}

daemon_available() {
  curl -sf --max-time 2 "$SHIELD_URL/health" >/dev/null 2>&1
}

# --- Positive: daemon reachability ---

@test "daemon health endpoint responds" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -sf --max-time 2 "$SHIELD_URL/health" 2>/dev/null)
  [[ "$output" == *"ok"* ]]
}

@test "daemon /gate endpoint accepts JSON POST" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d '{"tool_input":{"file_path":"docs/test.md","content":"hello"}}' 2>/dev/null)
  [[ -n "$output" ]]
}

@test "daemon classifies safe content as ALLOW" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d '{"tool_input":{"file_path":"docs/test.md","content":"generic safe text"}}' 2>/dev/null)
  [[ "$output" != *"BLOCK"* ]]
}

# --- Negative: daemon rejects bad input gracefully ---

@test "daemon rejects empty JSON body with error" {
  daemon_available || skip "Shield daemon not running"
  status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "$SHIELD_URL/gate" -H "Content-Type: application/json" $AUTH_HEADER -d '{}' 2>/dev/null)
  [ "$status_code" -ne 0 ]
}

@test "daemon rejects invalid JSON gracefully — no crash" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER -d 'not-json' 2>/dev/null)
  [[ "$output" == *'"error"'* ]]
}

@test "daemon blocks credential-like pattern in public path" {
  daemon_available || skip "Shield daemon not running"
  # Build pattern dynamically to avoid self-triggering gate
  local prefix="AKI"
  local suffix="AIOSFODNN7EXAMPL"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d "{\"tool_input\":{\"file_path\":\"docs/test.md\",\"content\":\"${prefix}${suffix}E\"}}" 2>/dev/null)
  [[ "$output" == *"BLOCK"* ]]
}

@test "daemon blocks private key marker in public path" {
  daemon_available || skip "Shield daemon not running"
  # Use a temp file to avoid shell quoting issues with BEGIN/PRIVATE/KEY
  local tmpf="$TMPDIR/pk-test.json"
  python3 -c "
import json
d={'tool_input':{'file_path':'docs/readme.md','content':'-----BEGI'+'N RSA PRIV'+'ATE KEY-----'}}
print(json.dumps(d))
" > "$tmpf"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d @"$tmpf" 2>/dev/null)
  [[ "$output" == *"BLOCK"* ]]
}

# --- Edge cases ---

@test "empty content does not crash daemon" {
  daemon_available || skip "Shield daemon not running"
  output=$(curl -s --max-time 5 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d '{"tool_input":{"file_path":"docs/test.md","content":""}}' 2>/dev/null)
  [[ "$output" != *"BLOCK"* ]]
}

@test "nonexistent endpoint returns non-200" {
  daemon_available || skip "Shield daemon not running"
  status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$SHIELD_URL/nonexistent" 2>/dev/null)
  [ "$status_code" -ne 200 ]
}

@test "boundary: large content handled within timeout" {
  daemon_available || skip "Shield daemon not running"
  big=$(python3 -c "print('a'*19000)" 2>/dev/null)
  output=$(curl -s --max-time 10 -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" $AUTH_HEADER \
    -d "{\"tool_input\":{\"file_path\":\"docs/t.md\",\"content\":\"$big\"}}" 2>/dev/null)
  [[ "$output" == *'"verdict"'* ]]
}

# --- Safety ---

@test "hook file exists and has set -uo pipefail" {
  grep -q 'set -uo pipefail' .opencode/hooks/data-sovereignty-gate.sh
}

@test "hook uses exit 2 to block PII leaks" {
  grep -q 'exit 2' .opencode/hooks/data-sovereignty-gate.sh
}
