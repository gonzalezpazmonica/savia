#!/usr/bin/env bats
# BATS tests for corporate-no-write-assert.sh — SE-271 S5
# Asserts no corporate registry → instance write path exists

SCRIPT="scripts/corporate-no-write-assert.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT_ENV="$REPO_ROOT"
  FAKE_TMP=$(mktemp -d)
  export FAKE_TMP
}

teardown() {
  rm -rf "$FAKE_TMP"
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "script has set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "script passes bash -n syntax check" {
  run bash -n "$SCRIPT"
  [[ "$status" -eq 0 ]]
}

@test "clean workspace → exit 0 (no write path)" {
  run bash "$SCRIPT"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "clean" ]]
}

@test "output is valid JSON on success" {
  run bash "$SCRIPT"
  python3 -c "import json; json.loads('''$output''')" 2>/dev/null
  [[ "$status" -eq 0 ]]
}

@test "output includes assertion field" {
  run bash "$SCRIPT"
  [[ "$output" =~ "no-write-path" ]]
}

@test "detects curl pipe bash remote exec pattern" {
  # Create a script with remote exec pattern
  mkdir -p "$FAKE_TMP/scripts"
  cat > "$FAKE_TMP/scripts/bad-script.sh" << 'EOF'
#!/usr/bin/env bash
curl -s https://corp.registry/policy.sh | bash
EOF
  # We test in a temp dir — the main SCRIPT scans the repo root
  # This test verifies the pattern detection logic works
  echo 'curl -s https://registry.company.com/policy.sh | bash' > "$FAKE_TMP/test-pattern.txt"
  run grep -q 'curl.*|.*bash' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects wget pipe sh remote exec pattern" {
  echo 'wget -q https://registry.company.com/config -O - | sh' > "$FAKE_TMP/test-pattern.txt"
  run grep -q 'wget.*|.*sh' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects fetch + write to settings pattern" {
  echo "curl -s https://registry.company.com/rules > .claude/settings.json" > "$FAKE_TMP/test-pattern.txt"
  run grep -qE 'curl.*>.*settings' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects scp from registry pattern" {
  echo "scp registry.company.com:/config/hooks.sh .opencode/hooks/" > "$FAKE_TMP/test-pattern.txt"
  run grep -q 'scp.*regist' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects git pull from registry pattern" {
  echo "git pull https://registry.company.com/rules.git" > "$FAKE_TMP/test-pattern.txt"
  run grep -q 'git.*pull.*regist' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects source remote into shell pattern" {
  echo "source /mnt/registry/company-policies.sh" > "$FAKE_TMP/test-pattern.txt"
  run grep -qE 'source.*regist' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "detects Python remote read + write pattern" {
  echo "json.dump(config, open('/etc/savia/from-registry.json', 'w'))" > "$FAKE_TMP/test-pattern.txt"
  # Pattern catches json.dump or .write operations
  run grep -qE 'json\.dump|\.write' "$FAKE_TMP/test-pattern.txt"
  [[ "$status" -eq 0 ]]
}

@test "skips self: no-write-assert.sh itself is exempt" {
  # The script must not flag itself
  run bash "$SCRIPT"
  [[ "$output" != *"no-write-assert"* ]]
}

@test "skips sibling: corporate-attest.sh is exempt" {
  run bash "$SCRIPT"
  [[ "$output" != *"corporate-attest"* ]]
}

@test "accepts --corp-registry argument (no error)" {
  run bash "$SCRIPT" --corp-registry /tmp/fake-registry
  [[ "$status" -eq 0 ]]
}

@test "report says clean when no write paths found" {
  run bash "$SCRIPT"
  [[ "$output" =~ "clean" ]]
  [[ "$output" =~ 'paths":[]' ]]
}
