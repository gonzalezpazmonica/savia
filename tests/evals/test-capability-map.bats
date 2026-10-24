#!/usr/bin/env bats
# Tests for SPEC-053 Savia Capability Map (.scm)

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  SCRIPT="scripts/generate-capability-map.sh"
  TMPDIR_SCM=$(mktemp -d)
  mkdir -p "$TMPDIR_SCM/.claude/commands" "$TMPDIR_SCM/.claude/skills/test-sk" \
           "$TMPDIR_SCM/.opencode/commands" "$TMPDIR_SCM/.opencode/agents" \
           "$TMPDIR_SCM/.claude/agents" "$TMPDIR_SCM/scripts"
}

teardown() { rm -rf "$TMPDIR_SCM"; }

mk_cmd() { printf -- '---\nname: %s\ndescription: %s\n---\n' "$1" "$2" > "$TMPDIR_SCM/.claude/commands/$1.md"; }
mk_skill() { mkdir -p "$TMPDIR_SCM/.claude/skills/$1"; printf -- '---\nname: %s\ndescription: %s\n---\n' "$1" "$2" > "$TMPDIR_SCM/.claude/skills/$1/SKILL.md"; }
mk_agent() { printf -- '---\nname: %s\ndescription: %s\n---\n' "$1" "$2" > "$TMPDIR_SCM/.opencode/agents/$1.md"; }
mk_script() { printf '#!/usr/bin/env bash\n# %s\nset -uo pipefail\n' "$2" > "$TMPDIR_SCM/scripts/$1.sh"; chmod +x "$TMPDIR_SCM/scripts/$1.sh"; }

@test "generate-capability-map.sh exists, executable, valid syntax" {
  [ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]
  bash -n "$SCRIPT"
}

@test "script is under 150 lines" {
  lines=$(wc -l < "$SCRIPT")
  [ "$lines" -le 150 ]
}

@test "script uses set -uo pipefail" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "generator produces INDEX.scm with header" {
  mk_cmd "sprint-status" "Sprint progress and burndown"
  bash "$SCRIPT" "$TMPDIR_SCM"
  [ -f "$TMPDIR_SCM/.scm/INDEX.scm" ]
  grep -q "Savia Capability Map" "$TMPDIR_SCM/.scm/INDEX.scm"
  # Header uses content hash (deterministic) instead of date timestamp — v5.34.0
  grep -qE "hash: [a-f0-9]{12}" "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "INDEX.scm contains all 4 resource types" {
  mk_cmd "test-cmd" "Quality testing command"
  mk_skill "my-skill" "Reporting metrics skill"
  mk_agent "test-agent" "Code review agent"
  mk_script "test-script" "Validation script"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep -q 'cmd:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'skill:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'agent:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'script:' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "generator creates 7 category files" {
  mk_cmd "dummy" "Dummy command"
  bash "$SCRIPT" "$TMPDIR_SCM"
  for cat in quality development planning analysis memory communication governance; do
    [ -f "$TMPDIR_SCM/.scm/categories/${cat}.scm" ]
  done
}

@test "classification: sprint-* goes to planning" {
  mk_cmd "sprint-plan" "Plan the next sprint with capacity"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep -q '\[planning\] sprint-plan' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "classification: security-* goes to quality" {
  mk_cmd "security-review" "Review security posture"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep -q '\[quality\] security-review' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "INDEX.scm lines follow format [cat] name — intents — type:path" {
  mk_cmd "test-run" "Execute test suite with coverage"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep '^\[' "$TMPDIR_SCM/.scm/INDEX.scm" | head -1 \
    | grep -qE '^\[[a-z]+\] [^ ]+ — .+ — (cmd|skill|agent|script):'
}

@test "category files contain L1 descriptions from frontmatter" {
  mk_cmd "sprint-status" "Estado del sprint actual"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep -q 'sprint-status' "$TMPDIR_SCM/.scm/categories/planning.scm"
  grep -q 'Estado del sprint actual' "$TMPDIR_SCM/.scm/categories/planning.scm"
}

@test "generator stdout reports resource counts" {
  mk_cmd "alpha" "Alpha command"
  mk_agent "beta" "Beta agent"
  run bash "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCM generated"* ]]
  [[ "$output" == *"commands"* ]]
}

@test "INDEX.scm header shows correct resource counts" {
  mk_cmd "c1" "Cmd one"
  mk_cmd "c2" "Cmd two"
  mk_agent "a1" "Agent one"
  bash "$SCRIPT" "$TMPDIR_SCM"
  grep -q '2 commands' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q '1 agents' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "error: missing directory argument handled gracefully" {
  run bash "$SCRIPT" "/nonexistent-dir-$$"
  [ "$status" -ne 0 ]
}

@test "error: empty workspace produces valid but minimal output" {
  run bash "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_SCM/.scm/INDEX.scm" ]
}

@test "edge: empty frontmatter description still classified" {
  mk_cmd "orphan-cmd" ""
  run bash "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_SCM/.scm/INDEX.scm" ]
}
