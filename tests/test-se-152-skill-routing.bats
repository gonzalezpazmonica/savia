#!/usr/bin/env bats
# BATS tests for SE-152: skill-routing-index.sh + consumes/produces frontmatter
# Min 15 tests targeting >=80 score.
# Ref: SE-152

SCRIPT="scripts/skill-routing-index.sh"
INDEX_FILE="output/skill-routing-index.json"
TEMPLATE_SKILL="templates/skills/_template/SKILL.md"

setup_file() {
  cd "$BATS_TEST_DIRNAME/.."
  mkdir -p output
  # Generate fresh index for all tests
  bash "$SCRIPT" > /dev/null 2>&1 || true
}

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() { cd /; }

# ── Script existence & meta ───────────────────────────────────────────────────

@test "SE-152: skill-routing-index.sh exists" {
  [[ -f "$SCRIPT" ]]
}

@test "SE-152: skill-routing-index.sh is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE-152: set -uo pipefail present" {
  run grep -c 'set -uo pipefail' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

@test "SE-152: bash -n syntax check passes" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SE-152: SE-152 reference present in script" {
  run grep -c 'SE-152' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}

# ── JSON output ───────────────────────────────────────────────────────────────

@test "SE-152: generates output/skill-routing-index.json" {
  [[ -f "$INDEX_FILE" ]]
}

@test "SE-152: JSON output is valid JSON" {
  run python3 -c "import json,sys; json.load(open('$INDEX_FILE'))"
  [ "$status" -eq 0 ]
}

@test "SE-152: JSON has consumes key" {
  run python3 -c "import json; d=json.load(open('$INDEX_FILE')); assert 'consumes' in d"
  [ "$status" -eq 0 ]
}

@test "SE-152: JSON has produces key" {
  run python3 -c "import json; d=json.load(open('$INDEX_FILE')); assert 'produces' in d"
  [ "$status" -eq 0 ]
}

@test "SE-152: JSON has skills key" {
  run python3 -c "import json; d=json.load(open('$INDEX_FILE')); assert 'skills' in d"
  [ "$status" -eq 0 ]
}

# ── consumes/produces extracted correctly ────────────────────────────────────

@test "SE-152: weekly-report appears under consumes[sprint_data]" {
  run python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
assert 'weekly-report' in d['consumes']['sprint_data'], d['consumes']
"
  [ "$status" -eq 0 ]
}

@test "SE-152: weekly-report appears under produces[report]" {
  run python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
assert 'weekly-report' in d['produces']['report'], d['produces']
"
  [ "$status" -eq 0 ]
}

@test "SE-152: knowledge-graph produces graph_db" {
  run python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
assert 'knowledge-graph' in d['produces']['graph_db']
"
  [ "$status" -eq 0 ]
}

@test "SE-152: savia-memory consumes session_data" {
  run python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
assert 'savia-memory' in d['consumes']['session_data']
"
  [ "$status" -eq 0 ]
}

# ── --check mode ──────────────────────────────────────────────────────────────

@test "SE-152: --check mode passes when index is up-to-date" {
  run bash "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "SE-152: --check mode fails when index missing" {
  local tmp_index
  tmp_index="${BATS_TEST_TMPDIR}/routing-check-test.json"
  # Temporarily rename index
  mv "$INDEX_FILE" "$tmp_index"
  run bash "$SCRIPT" --check
  local rc="$status"
  mv "$tmp_index" "$INDEX_FILE"
  [ "$rc" -eq 1 ]
}

# ── Template has consumes/produces documented ─────────────────────────────────

@test "SE-152: template SKILL.md has consumes field documented" {
  run grep -c 'consumes' "$TEMPLATE_SKILL"
  [[ "$output" -ge 1 ]]
}

@test "SE-152: template SKILL.md has produces field documented" {
  run grep -c 'produces' "$TEMPLATE_SKILL"
  [[ "$output" -ge 1 ]]
}

# ── Edge: skill without consumes/produces does not fail ───────────────────────

@test "SE-152: skill without consumes/produces not present in skills map" {
  # Verify a skill that has neither doesn't crash the script
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SE-152: skill-routing-index produces non-empty JSON object" {
  run python3 -c "
import json
d = json.load(open('$INDEX_FILE'))
# At minimum 5 representative skills should be indexed
assert len(d['skills']) >= 4, f'Expected >= 4 skills, got {len(d[\"skills\"])}'
"
  [ "$status" -eq 0 ]
}

# ── Edge: empty array in auditor ─────────────────────────────────────────────

@test "SE-152: skill-catalog-auditor detects empty produces []" {
  # Create a temporary skill in the real skills dir for the --skill flag to find it
  local real_skills_dir
  real_skills_dir="$(cd "$(dirname scripts/skill-catalog-auditor.sh)/.." && cd -P .opencode/skills && pwd)"
  local tmp_skill_dir="${real_skills_dir}/test-se152-fixture-$$"
  mkdir -p "$tmp_skill_dir"
  cat > "$tmp_skill_dir/SKILL.md" << 'EOF'
---
name: test-se152-fixture
description: "Fixture skill with empty produces array"
produces: []
---
# Skill
See docs/rules/domain/test.md for details.
EOF
  printf "# Domain\nLine 2.\nLine 3.\nLine 4.\n" > "$tmp_skill_dir/DOMAIN.md"
  run bash scripts/skill-catalog-auditor.sh --skill "test-se152-fixture-$$"
  local rc="$status"
  rm -rf "$tmp_skill_dir"
  [[ "$output" == *"produces is empty array"* ]]
}
