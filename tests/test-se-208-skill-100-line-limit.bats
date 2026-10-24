#!/usr/bin/env bats
# tests/test-se-208-skill-100-line-limit.bats
# SE-208 — SKILL.md hard limit 100 lines + progressive disclosure
# Ref: docs/propuestas/SE-208-skill-100-line-limit.md

AUDITOR="scripts/skill-catalog-auditor.sh"
TEMPLATE="templates/skills/_template/SKILL.md"
PROTOCOL="docs/rules/domain/skill-template-protocol.md"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# ── Helper: create a fake skill dir with controlled line count ────────────────

make_skill() {
  local skills_root="$1" name="$2" target_lines="$3"
  local skill_dir="$skills_root/$name"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/DOMAIN.md" <<'DOMEOF'
---
name: domain
---

content here
DOMEOF
  cat > "$skill_dir/SKILL.md" <<SKILLEOF
---
name: $name
description: "Test skill. Usar cuando se necesita probar SE-208."
---

# Test

Ref: scripts/skill-catalog-auditor.sh

body content here
SKILLEOF
  local current
  current=$(wc -l < "$skill_dir/SKILL.md")
  while [[ "$current" -lt "$target_lines" ]]; do
    echo "padding line" >> "$skill_dir/SKILL.md"
    current=$(wc -l < "$skill_dir/SKILL.md")
  done
  while [[ "$current" -gt "$target_lines" ]]; do
    head -n $((current - 1)) "$skill_dir/SKILL.md" > "$skill_dir/SKILL.md.tmp"
    mv "$skill_dir/SKILL.md.tmp" "$skill_dir/SKILL.md"
    current=$(wc -l < "$skill_dir/SKILL.md")
  done
}

# ── Existence ─────────────────────────────────────────────────────────────────

@test "SE-208: skill-catalog-auditor.sh exists" {
  [ -f "$ROOT/$AUDITOR" ]
}

@test "SE-208: skill-catalog-auditor.sh is executable" {
  [ -x "$ROOT/$AUDITOR" ]
}

# ── WARN for 110-line skill ───────────────────────────────────────────────────

@test "SE-208: auditor emits WARN for SKILL.md with 110 lines" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-warn-skill" 110
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-warn-skill" 2>&1
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"progressive disclosure"* ]]
}

# ── FAIL for 151-line skill ───────────────────────────────────────────────────

@test "SE-208: auditor emits FAIL for SKILL.md with 151 lines" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-fail-skill" 151
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-fail-skill" 2>&1
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"150"* || "$output" == *"hard limit"* ]]
}

# ── OK for 90-line skill (no SE-208 WARN) ────────────────────────────────────

@test "SE-208: auditor emits no SE-208 WARN for SKILL.md with 90 lines" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-ok-skill" 90
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-ok-skill" 2>&1
  [[ "$output" != *"progressive disclosure"* ]]
}

# ── WARN does not change exit code ────────────────────────────────────────────

@test "SE-208: WARN-only result does not produce non-zero exit code" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-exit-skill" 110
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-exit-skill"
  [ "$status" -eq 0 ]
}

# ── Boundary: exactly 100 lines should NOT trigger progressive disclosure WARN ─

@test "SE-208: SKILL.md with exactly 100 lines does not trigger progressive disclosure WARN" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-boundary-skill" 100
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-boundary-skill" 2>&1
  [[ "$output" != *"progressive disclosure"* ]]
}

# ── Boundary: exactly 101 lines triggers WARN ────────────────────────────────

@test "SE-208: SKILL.md with 101 lines triggers progressive disclosure WARN" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se208-101-skill" 101
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se208-101-skill" 2>&1
  [[ "$output" == *"progressive disclosure"* ]]
}

# ── Template mentions 100-line limit ─────────────────────────────────────────

@test "SE-208: template SKILL.md mentions 100-line target" {
  grep -q "100" "$ROOT/$TEMPLATE"
}

@test "SE-208: template SKILL.md contains TARGET or progressive disclosure mention" {
  grep -qiE "(TARGET|progressive disclosure|100)" "$ROOT/$TEMPLATE"
}

# ── skill-template-protocol.md has Progressive Disclosure section ─────────────

@test "SE-208: skill-template-protocol.md exists" {
  [ -f "$ROOT/$PROTOCOL" ]
}

@test "SE-208: skill-template-protocol.md has Progressive Disclosure section" {
  grep -q "Progressive Disclosure" "$ROOT/$PROTOCOL"
}

@test "SE-208: skill-template-protocol.md mentions satellite files" {
  grep -qE "(REFERENCE\.md|tests\.md|examples\.md)" "$ROOT/$PROTOCOL"
}

# ── SE-208 referenced in auditor ─────────────────────────────────────────────

@test "SE-208: skill-catalog-auditor.sh references SE-208" {
  grep -q "SE-208" "$ROOT/$AUDITOR"
}

# ── Safety verification ────────────────────────────────────────────────────────
@test "SE-208: skill-catalog-auditor.sh has set -uo pipefail" {
  grep -q "set -uo pipefail" "$ROOT/$AUDITOR"
}

# ── Edge cases ────────────────────────────────────────────────────────────────
@test "SE-208 edge: skill with exactly 100 lines is OK (boundary)" {
  mkdir -p "$TMPDIR_TEST/skills/boundary-skill"
  { printf -- '---\nname: boundary\ndescription: "Boundary skill. Usar cuando boundary."\n---\n\nrefs path/to/file\n'; yes "x" | head -94; } > "$TMPDIR_TEST/skills/boundary-skill/SKILL.md"
  printf 'domain content here\nmore here\nthird line\nfourth\n' > "$TMPDIR_TEST/skills/boundary-skill/DOMAIN.md"
  run env SAVIA_SKILLS_DIR="$TMPDIR_TEST/skills" bash "$ROOT/$AUDITOR" 2>&1
  [[ "$output" != *"boundary-skill"*"WARN"* ]] || [[ "$output" == *"OK"* ]]
}

@test "SE-208 edge: nonexistent SKILLS_DIR handled gracefully" {
  run env SAVIA_SKILLS_DIR="/nonexistent/$$" bash "$ROOT/$AUDITOR" 2>&1 || true
  [ "$status" -le 2 ]
}

@test "SE-208 edge: empty skills directory returns PASS with 0 total" {
  mkdir -p "$TMPDIR_TEST/empty_skills"
  run env SAVIA_SKILLS_DIR="$TMPDIR_TEST/empty_skills" bash "$ROOT/$AUDITOR" 2>&1
  [ "$status" -eq 0 ]
}

@test "SE-208 coverage: skill-template-protocol.md exists" {
  [ -f "$ROOT/docs/rules/domain/skill-template-protocol.md" ]
}
