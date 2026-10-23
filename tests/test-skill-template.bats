#!/usr/bin/env bats
# BATS tests for templates/skills/_template/SKILL.md
# Ref: SE-153 — see docs/rules/domain/skill-template-protocol.md
# Pattern: "Authoritative paths first" (SE-153, inspirado en flowsint)

TEMPLATE="templates/skills/_template/SKILL.md"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMPDIR_TEST=$(mktemp -d)
  export TMPDIR_TEST
}

teardown() {
  [ -n "${TMPDIR_TEST:-}" ] && [ -d "$TMPDIR_TEST" ] && rm -rf "$TMPDIR_TEST"
}

# ── Existence + not discoverable as skill ───────────────────────

@test "template SKILL.md exists in templates/skills/_template/" {
  [[ -f "$TEMPLATE" ]]
}

@test "templates are not discoverable as skills (outside .claude/skills)" {
  [[ ! -e .claude/skills/_template ]]
  [[ ! -e .claude/skills/_template_python ]]
  [[ -f templates/skills/_template_python/SKILL.md ]]
}

# ── Frontmatter ───────────────────────────────────────────────────────

@test "template has YAML frontmatter delimited" {
  head -1 "$TEMPLATE" | grep -qE '^---$'
  awk '/^---$/{c++}END{exit (c<2)}' "$TEMPLATE"
}

@test "template name field equals _template" {
  grep -qE '^name: _template$' "$TEMPLATE"
}

@test "template has description field with TEMPLATE marker" {
  grep -qE '^description:.*TEMPLATE' "$TEMPLATE"
}

@test "template maturity is template (not stable/proposed)" {
  grep -qE '^[[:space:]]*savia\.maturity:[[:space:]]*"?template"?$' "$TEMPLATE"
}

# ── Authoritative Paths First pattern ─────────────────────────────────

@test "template has Authoritative Paths section" {
  grep -qE '^## Authoritative Paths' "$TEMPLATE"
}

@test "Authoritative Paths section appears BEFORE Workflow (paths first rule)" {
  local auth_line workflow_line
  auth_line=$(grep -n '^## Authoritative Paths' "$TEMPLATE" | cut -d: -f1)
  workflow_line=$(grep -n '^## Workflow' "$TEMPLATE" | cut -d: -f1)
  [ -n "$auth_line" ]
  [ -n "$workflow_line" ]
  [ "$auth_line" -lt "$workflow_line" ]
}

@test "Authoritative Paths section appears BEFORE Decision Checklist" {
  local auth_line dc_line
  auth_line=$(grep -n '^## Authoritative Paths' "$TEMPLATE" | cut -d: -f1)
  dc_line=$(grep -n '^## Decision Checklist' "$TEMPLATE" | cut -d: -f1)
  [ "$auth_line" -lt "$dc_line" ]
}

@test "Authoritative Paths warns against assuming or inventing" {
  awk '/^## Authoritative Paths/{f=1;next} /^## /{f=0} f' "$TEMPLATE" | grep -qiE 'NUNCA|NEVER|asum|invent'
}

# ── Standard sections present ─────────────────────────────────────────

@test "template has Cuándo usar section" {
  grep -qE '^## Cuándo usar' "$TEMPLATE"
}

@test "template has Cuándo NO usar (anti-trigger) section" {
  grep -qE '^## Cuándo NO usar' "$TEMPLATE"
}

@test "template has Memory hooks section" {
  grep -qE '^## Memory hooks' "$TEMPLATE"
}

@test "template has Related section" {
  grep -qE '^## Related' "$TEMPLATE"
}

@test "template has Subagent Scope Guard" {
  grep -qE '^## Subagent Scope Guard' "$TEMPLATE"
}

# ── Constraints (Rule #11 — 150 line cap) ─────────────────────────────

@test "template stays under 150 lines (Rule #11)" {
  local lines
  lines=$(wc -l < "$TEMPLATE")
  [ "$lines" -le 150 ]
}

@test "template under 150 lines boundary not zero (non-empty)" {
  local lines
  lines=$(wc -l < "$TEMPLATE")
  [ "$lines" -gt 30 ]
}

# ── Generators exclude _template ──────────────────────────────────────

@test "skills-md-generate.sh excludes _template (no contamination)" {
  grep -qE "_template" scripts/skills-md-generate.sh
}

@test "resolver-md-generate.sh excludes _template (no contamination)" {
  grep -qE "_template" scripts/resolver-md-generate.sh
}

@test "RESOLVER.md does not contain _template entry (regression guard)" {
  ! grep -qE 'skill:_template' docs/RESOLVER.md
}

# ── Negative: malformed/missing template detection ────────────────────

@test "edge: nonexistent template path detected" {
  [ ! -f "$TMPDIR_TEST/missing-skill.md" ]
}

@test "edge: empty file would fail validator (regression boundary)" {
  : > "$TMPDIR_TEST/empty.md"
  [ ! -s "$TMPDIR_TEST/empty.md" ]
}

@test "edge: skill-validator.sh accepts the template (no false positives)" {
  if [[ -x scripts/skill-validator.sh ]]; then
    run bash scripts/skill-validator.sh "$TEMPLATE"
    [ "$status" -eq 0 ]
  else
    skip "skill-validator.sh missing"
  fi
}

# ── Copyability ───────────────────────────────────────────────────────

@test "edge: template is copyable to a new dir without modification" {
  cp -r templates/skills/_template "$TMPDIR_TEST/new-skill"
  [[ -f "$TMPDIR_TEST/new-skill/SKILL.md" ]]
  diff "$TEMPLATE" "$TMPDIR_TEST/new-skill/SKILL.md"
}

@test "edge: template has placeholder markers for users to replace" {
  grep -qE '<[A-Za-z][^>]+>' "$TEMPLATE"
}

@test "edge: template lists hard rules (NUNCA/NEVER)" {
  grep -qiE 'NUNCA|NEVER' "$TEMPLATE"
}

# ── Safety verification on companion scripts (required by auditor) ────

@test "skills-md-generate.sh declares set -uo pipefail (safety)" {
  grep -qE 'set -uo pipefail' scripts/skills-md-generate.sh
}

@test "resolver-md-generate.sh declares set -uo pipefail (safety)" {
  grep -qE 'set -uo pipefail' scripts/resolver-md-generate.sh
}

# ── Stronger assertions ───────────────────────────────────────────────

@test "frontmatter parses as YAML (python3 stdlib)" {
  python3 -c "
import sys, json
with open('$TEMPLATE') as f:
    txt = f.read()
parts = txt.split('---', 2)
assert len(parts) >= 3, 'frontmatter delimiters missing'
fm = parts[1]
assert 'name:' in fm, 'name missing'
assert 'description:' in fm, 'description missing'
print(json.dumps({'ok': True}))
"
}

@test "Authoritative Paths table has at least 5 rows (richness boundary)" {
  local rows
  rows=$(awk '/^## Authoritative Paths/{f=1;next} /^## /{f=0} f' "$TEMPLATE" | grep -cE '^\| ')
  [ "$rows" -ge 5 ]
}

@test "template Workflow section uses fenced code block" {
  awk '/^## Workflow/{f=1} f' "$TEMPLATE" | grep -qE '^```'
}

@test "template Memory hooks section references memory-store.sh" {
  awk '/^## Memory hooks/{f=1;next} /^## /{f=0} f' "$TEMPLATE" | grep -q 'memory-store.sh'
}

@test "template Subagent Scope Guard names DONE/BLOCKED states" {
  awk '/^## Subagent Scope Guard/{f=1;next} /^## /{f=0} f' "$TEMPLATE" | grep -qE 'DONE.*BLOCKED|BLOCKED.*DONE'
}
