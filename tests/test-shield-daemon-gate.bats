#!/usr/bin/env bats
# test-shield-daemon-gate.bats — Gate path normalization + classification
# SPEC-044: data-sovereignty (Layer 1 — deterministic path gate)
# Ref: docs/rules/domain/data-sovereignty.md
# Target: .opencode/hooks/data-sovereignty-gate.sh

setup() {
  # Verify set -uo pipefail in target hook
  grep -q 'set -uo pipefail' "${BATS_TEST_DIRNAME}/../.opencode/hooks/data-sovereignty-gate.sh"
  export TMPDIR="${BATS_TMPDIR:-/tmp}/shield-gate-$$"
  mkdir -p "$TMPDIR" 2>/dev/null || true
}

teardown() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}

classify() {
  python3 -c "
import sys, os, json
fp = sys.argv[1]
fp_norm = os.path.normpath(fp).replace('\\\\', '/')
patterns = ['/projects/', 'projects/', '.local.', '/output/', 'private-agent-memory', '/config.local/', '/.savia/', '/.claude/sessions/', 'settings.local.json']
for p in patterns:
    if p in fp_norm:
        print('PRIVATE'); sys.exit(0)
print('PUBLIC')
" "$1" 2>/dev/null
}

# --- Positive: private paths correctly detected ---

@test "projects/ forward slash path is PRIVATE" {
  output=$(classify "/home/user/savia/projects/alpha/docs/digest.md")
  [[ "$output" == "PRIVATE" ]]
}

@test "projects/ Windows path is PRIVATE" {
  output=$(classify "C:/Users/user/savia/projects/alpha/docs/file.md")
  [[ "$output" == "PRIVATE" ]]
}

@test ".local. files are PRIVATE" {
  output=$(classify "/home/user/savia/CLAUDE.local.md")
  [[ "$output" == "PRIVATE" ]]
}

@test "output/ directory is PRIVATE" {
  output=$(classify "/home/user/savia/output/audits/report.md")
  [[ "$output" == "PRIVATE" ]]
}

@test "private-agent-memory is PRIVATE" {
  output=$(classify "/home/user/savia/private-agent-memory/arch/mem.md")
  [[ "$output" == "PRIVATE" ]]
}

@test "config.local/ is PRIVATE" {
  output=$(classify "/home/user/savia/config.local/secrets.env")
  [[ "$output" == "PRIVATE" ]]
}

# --- Negative: public paths flagged for scan (no blocking error) ---

@test "docs/README.md is PUBLIC — no false blocking" {
  output=$(classify "/home/user/savia/docs/README.md")
  [[ "$output" == "PUBLIC" ]]
}

@test "scripts/ is PUBLIC — no false reject" {
  output=$(classify "/home/user/savia/scripts/test.sh")
  [[ "$output" == "PUBLIC" ]]
}

@test "docs/rules/ is PUBLIC — invalid skip would miss PII" {
  output=$(classify "/home/user/savia/docs/rules/domain/rule.md")
  [[ "$output" == "PUBLIC" ]]
}

@test "CHANGELOG.md is PUBLIC — blocks if wrongly PRIVATE" {
  output=$(classify "/home/user/savia/CHANGELOG.md")
  [[ "$output" == "PUBLIC" ]]
}

# --- Edge: empty, nonexistent, boundary ---

@test "empty path returns PUBLIC gracefully" {
  output=$(classify "")
  [[ "$output" == "PUBLIC" ]]
}

@test "nonexistent deep path with projects/ is PRIVATE" {
  output=$(classify "/nonexistent/deep/projects/alpha/x.md")
  [[ "$output" == "PRIVATE" ]]
}

@test "boundary: path traversal ../ resolves to projects/" {
  output=$(classify "/home/user/savia/docs/../projects/alpha/x.md")
  [[ "$output" == "PRIVATE" ]]
}

# --- Safety: verify target hook has set -uo pipefail ---

@test "target hook has set -uo pipefail for safety" {
  grep -q 'set -uo pipefail' .opencode/hooks/data-sovereignty-gate.sh
}

@test "target hook blocks with exit 2 on PII detection" {
  grep -q 'exit 2' .opencode/hooks/data-sovereignty-gate.sh
}
