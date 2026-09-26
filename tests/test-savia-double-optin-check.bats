#!/usr/bin/env bats
# BATS tests for scripts/savia-double-optin-check.sh
# Ref: SPEC-186 (Era 199 Wave 1)

SCRIPT="scripts/savia-double-optin-check.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP_AUDIT="$(mktemp -t optin-audit.XXXXXX)"
  TMP_GRANTS="$(mktemp -d -t optin-grants.XXXXXX)"
  export SAVIA_OPTIN_AUDIT_LOG="$TMP_AUDIT"
  export SAVIA_GRANTS_DIR="$TMP_GRANTS"
  # Clean any inherited gate vars to keep tests deterministic.
  unset OVERNIGHT_SPRINT_ENABLED CODE_IMPROVEMENT_LOOP_ENABLED \
        ADVERSARIAL_SECURITY_ENABLED TECH_RESEARCH_AGENT_ENABLED \
        SAVIA_DUAL_FAILOVER_ENABLED SAVIA_TESTING || true
}

teardown() {
  [[ -n "${TMP_AUDIT:-}" && -f "$TMP_AUDIT" ]] && rm -f "$TMP_AUDIT"
  [[ -n "${TMP_GRANTS:-}" && -d "$TMP_GRANTS" ]] && rm -rf "$TMP_GRANTS"
  cd /
}

# ── Meta ──────────────────────────────────────────────────────────────

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "passes bash -n syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "uses set -uo pipefail" {
  run grep -c 'set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "references SPEC-186" {
  run grep -c 'SPEC-186' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "--help exits 0 with usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "--version exits 0 with semver" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── Invalid invocation ────────────────────────────────────────────────

@test "missing --skill exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--skill"* ]]
}

@test "unknown skill exits 2" {
  run bash "$SCRIPT" --skill bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown skill"* ]]
}

# ── 4 combinations × 2 skills (overnight-sprint + adversarial-security) ──

@test "00 overnight-sprint: missing both -> exit 1" {
  run bash "$SCRIPT" --skill overnight-sprint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: OVERNIGHT_SPRINT_ENABLED"* ]]
  [[ "$output" == *"[FALTA] Flag explicito: --confirm-autonomous"* ]]
}

@test "01 overnight-sprint: only flag -> exit 1, env missing" {
  run bash "$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: OVERNIGHT_SPRINT_ENABLED"* ]]
  [[ "$output" == *"[OK]    Flag explicito"* ]]
}

@test "10 overnight-sprint: only env -> exit 1, flag missing" {
  OVERNIGHT_SPRINT_ENABLED=true run bash "$SCRIPT" --skill overnight-sprint
  [ "$status" -eq 1 ]
  [[ "$output" == *"[OK]    Variable de entorno"* ]]
  [[ "$output" == *"[FALTA] Flag explicito"* ]]
}

@test "11 overnight-sprint: both -> exit 0" {
  OVERNIGHT_SPRINT_ENABLED=true run bash "$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 0 ]
}

@test "00 adversarial-security: missing both -> exit 1" {
  run bash "$SCRIPT" --skill adversarial-security
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADVERSARIAL_SECURITY_ENABLED"* ]]
}

@test "11 adversarial-security: both -> exit 0" {
  ADVERSARIAL_SECURITY_ENABLED=true run bash "$SCRIPT" --skill adversarial-security --confirm-autonomous
  [ "$status" -eq 0 ]
}

# ── Other 3 skills resolve correct env var name ───────────────────────

@test "code-improvement-loop maps to CODE_IMPROVEMENT_LOOP_ENABLED" {
  run bash "$SCRIPT" --skill code-improvement-loop
  [[ "$output" == *"CODE_IMPROVEMENT_LOOP_ENABLED"* ]]
}

@test "tech-research-agent maps to TECH_RESEARCH_AGENT_ENABLED" {
  run bash "$SCRIPT" --skill tech-research-agent
  [[ "$output" == *"TECH_RESEARCH_AGENT_ENABLED"* ]]
}

@test "savia-dual maps to SAVIA_DUAL_FAILOVER_ENABLED" {
  run bash "$SCRIPT" --skill savia-dual
  [[ "$output" == *"SAVIA_DUAL_FAILOVER_ENABLED"* ]]
}

# ── env=false treated as missing ──────────────────────────────────────

@test "env var set but not 'true' (false) -> exit 1" {
  OVERNIGHT_SPRINT_ENABLED=false run bash "$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno"* ]]
}

@test "env var set but not 'true' (1) -> exit 1" {
  OVERNIGHT_SPRINT_ENABLED=1 run bash "$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 1 ]
}

# ── --skill=foo equals form ───────────────────────────────────────────

@test "--skill=foo equals form works" {
  OVERNIGHT_SPRINT_ENABLED=true run bash "$SCRIPT" --skill=overnight-sprint --confirm-autonomous
  [ "$status" -eq 0 ]
}

# ── Test bypass (SAVIA_TESTING + BATS) ────────────────────────────────

@test "SAVIA_TESTING=1 inside BATS -> bypass exit 0 even with both missing" {
  SAVIA_TESTING=1 run bash "$SCRIPT" --skill overnight-sprint
  [ "$status" -eq 0 ]
}

@test "SAVIA_TESTING=1 WITHOUT BATS_TEST_NAME -> NO bypass" {
  # Run via env -i to strip BATS_TEST_NAME from child process.
  run env -i PATH="$PATH" SAVIA_TESTING=1 bash "$SCRIPT" --skill overnight-sprint
  [ "$status" -eq 1 ]
}

# ── Audit log ─────────────────────────────────────────────────────────

@test "audit log records denied attempt" {
  run bash "$SCRIPT" --skill overnight-sprint
  [ "$status" -eq 1 ]
  [[ -f "$TMP_AUDIT" ]]
  run cat "$TMP_AUDIT"
  [[ "$output" == *"overnight-sprint"* ]]
  [[ "$output" == *"verdict=denied"* ]]
  [[ "$output" == *"env=0"* ]]
  [[ "$output" == *"flag=0"* ]]
}

@test "audit log records ok attempt with both factors" {
  OVERNIGHT_SPRINT_ENABLED=true run bash "$SCRIPT" --skill overnight-sprint --confirm-autonomous
  [ "$status" -eq 0 ]
  run cat "$TMP_AUDIT"
  [[ "$output" == *"verdict=ok"* ]]
  [[ "$output" == *"env=1"* ]]
  [[ "$output" == *"flag=1"* ]]
}
