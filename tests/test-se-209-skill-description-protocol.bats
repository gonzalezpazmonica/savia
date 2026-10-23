#!/usr/bin/env bats
# tests/test-se-209-skill-description-protocol.bats
# SE-209 — Canonical description format for SKILL.md
# Ref: docs/propuestas/SE-209-skill-description-protocol.md

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

# ── Helper: create fake skill with given description ─────────────────────────

make_skill() {
  local skills_root="$1" name="$2" desc="$3"
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
description: "$desc"
---

# Test

Ref: scripts/skill-catalog-auditor.sh

body content here
SKILLEOF
}

# ── Existence ─────────────────────────────────────────────────────────────────

@test "SE-209: skill-catalog-auditor.sh exists" {
  [ -f "$ROOT/$AUDITOR" ]
}

@test "SE-209: skill-catalog-auditor.sh contains check_description_format function" {
  grep -q "check_description_format" "$ROOT/$AUDITOR"
}

# ── WARN for short description (<20 chars) ────────────────────────────────────

@test "SE-209: WARN emitted for description with fewer than 20 chars" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-short-desc" "Too short."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-short-desc" 2>&1
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"description"* ]]
}

# ── WARN for description without trigger keyword ──────────────────────────────

@test "SE-209: WARN emitted for description without when/cuando/Usar/Use" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-no-trigger" "Herramienta para gestionar la agenda con sincronizacion Outlook y Teams completa."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-no-trigger" 2>&1
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"trigger"* || "$output" == *"description"* ]]
}

# ── OK for well-formed descriptions ──────────────────────────────────────────

@test "SE-209: no description WARN for well-formed description with Usar" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-good-usar" "Audita compliance legal. Usar cuando se crea un contrato o se procesa PII."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-good-usar" 2>&1
  [[ "$output" != *"trigger keyword"* ]]
  [[ "$output" != *"description < 20"* ]]
}

@test "SE-209: no description WARN for well-formed description with Use" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-good-use" "Maps architecture dependencies. Use when designing a new feature or evaluating trade-offs."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-good-use" 2>&1
  [[ "$output" != *"trigger keyword"* ]]
  [[ "$output" != *"description < 20"* ]]
}

@test "SE-209: no description WARN for well-formed description with cuando" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-good-cuando" "Genera informes ejecutivos. Usar cuando se necesita informe para la direccion de empresa."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-good-cuando" 2>&1
  [[ "$output" != *"trigger keyword"* ]]
  [[ "$output" != *"description < 20"* ]]
}

@test "SE-209: no description WARN for well-formed description with when" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-good-when" "Runs adversarial review. Use when merging non-trivial PRs or reviewing security code."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-good-when" 2>&1
  [[ "$output" != *"trigger keyword"* ]]
  [[ "$output" != *"description < 20"* ]]
}

# ── Description WARN is non-blocking (exit 0) ─────────────────────────────────

@test "SE-209: description WARN does not produce non-zero exit code" {
  local skills_root="$TMPDIR_TEST/skills"
  mkdir -p "$skills_root"
  make_skill "$skills_root" "se209-warn-exit" "No trigger here at all in this long enough description text."
  run env SAVIA_SKILLS_DIR="$skills_root" bash "$ROOT/$AUDITOR" --skill "se209-warn-exit"
  [ "$status" -eq 0 ]
}

# ── Template has canonical format ─────────────────────────────────────────────

@test "SE-209: template SKILL.md has canonical description format comment" {
  grep -qE "(qué hace|what|trigger|Usar cuando|Use when)" "$ROOT/$TEMPLATE"
}

@test "SE-209: template SKILL.md mentions 200 chars or SE-209" {
  grep -qE "(200|SE-209|canonical)" "$ROOT/$TEMPLATE"
}

# ── skill-template-protocol.md has Description Protocol section ──────────────

@test "SE-209: skill-template-protocol.md has Description Protocol section" {
  grep -q "Description Protocol" "$ROOT/$PROTOCOL"
}

@test "SE-209: skill-template-protocol.md mentions SE-203 relation" {
  grep -q "SE-203" "$ROOT/$PROTOCOL"
}

# ── SE-209 referenced in auditor ─────────────────────────────────────────────

@test "SE-209: skill-catalog-auditor.sh references SE-209" {
  grep -q "SE-209" "$ROOT/$AUDITOR"
}

# ── Safety verification ────────────────────────────────────────────────────────
@test "SE-209: skill-catalog-auditor.sh has set -uo pipefail" {
  grep -q "set -uo pipefail" "$ROOT/$AUDITOR"
}

# ── Edge cases ────────────────────────────────────────────────────────────────
@test "SE-209 edge: description with exactly 20 chars is OK (boundary)" {
  mkdir -p "$TMPDIR_TEST/skills/boundary-desc"
  printf -- '---\nname: bd\ndescription: "Analyze code. Use when boundary testing needed."\n---\n\nrefs path/to/file\n' > "$TMPDIR_TEST/skills/boundary-desc/SKILL.md"
  printf 'domain\ncontent\nhere\nfour\n' > "$TMPDIR_TEST/skills/boundary-desc/DOMAIN.md"
  run env SAVIA_SKILLS_DIR="$TMPDIR_TEST/skills" bash "$ROOT/$AUDITOR" 2>&1
  [[ "$output" != *"boundary-desc"*"description"*"WARN"* ]]
}

@test "SE-209 edge: null/empty description field produces WARN" {
  mkdir -p "$TMPDIR_TEST/skills/no-desc"
  printf -- '---\nname: no-desc\ndescription: ""\n---\n\nrefs path/to/file\n' > "$TMPDIR_TEST/skills/no-desc/SKILL.md"
  printf 'domain\ncontent\nhere\nfour\n' > "$TMPDIR_TEST/skills/no-desc/DOMAIN.md"
  run env SAVIA_SKILLS_DIR="$TMPDIR_TEST/skills" bash "$ROOT/$AUDITOR" 2>&1
  [[ "$output" == *"WARN"* || "$output" == *"description"* ]]
}

@test "SE-209 edge: description without trigger word produces WARN" {
  mkdir -p "$TMPDIR_TEST/skills/no-trigger"
  printf -- '---\nname: no-trigger\ndescription: "This skill does something useful for the team."\n---\n\nrefs path/to/file\n' > "$TMPDIR_TEST/skills/no-trigger/SKILL.md"
  printf 'domain\ncontent\nhere\nfour\n' > "$TMPDIR_TEST/skills/no-trigger/DOMAIN.md"
  run env SAVIA_SKILLS_DIR="$TMPDIR_TEST/skills" bash "$ROOT/$AUDITOR" 2>&1
  [[ "$output" == *"WARN"* ]]
}

@test "SE-209 coverage: Description Protocol in skill-template-protocol.md" {
  grep -qi "description protocol\|Description Protocol" "$ROOT/docs/rules/domain/skill-template-protocol.md"
}
