#!/usr/bin/env bats
# Tests for SPEC-053 Savia Capability Map (.scm)

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  SCRIPT="scripts/generate-capability-map.py"
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

@test "generate-capability-map.py exists and compiles" {
  [ -f "$SCRIPT" ]
  python3 -m py_compile "$SCRIPT"
}

@test "SE-501: the retired .sh wrapper is gone and no script, hook or workflow still calls it" {
  [ ! -e scripts/generate-capability-map.sh ]
  run grep -rlE 'generate-capability-map\.sh' scripts .claude/hooks .claude/settings.json .opencode/plugins .github/workflows
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "generator produces INDEX.scm with header" {
  mk_cmd "sprint-status" "Sprint progress and burndown"
  python3 "$SCRIPT" "$TMPDIR_SCM"
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
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep -q 'cmd:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'skill:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'agent:' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q 'script:' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "generator creates 7 category files" {
  mk_cmd "dummy" "Dummy command"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  for cat in quality development planning analysis memory communication governance; do
    [ -f "$TMPDIR_SCM/.scm/categories/${cat}.scm" ]
  done
}

@test "classification: sprint-* goes to planning" {
  mk_cmd "sprint-plan" "Plan the next sprint with capacity"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep -q '\[planning\] sprint-plan' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "classification: security-* goes to quality" {
  mk_cmd "security-review" "Review security posture"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep -q '\[quality\] security-review' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "INDEX.scm lines follow format [cat] name — intents — type:path" {
  mk_cmd "test-run" "Execute test suite with coverage"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep '^\[' "$TMPDIR_SCM/.scm/INDEX.scm" | head -1 \
    | grep -qE '^\[[a-z]+\] [^ ]+ — .+ — (cmd|skill|agent|script):'
}

@test "category files contain L1 descriptions from frontmatter" {
  mk_cmd "sprint-status" "Estado del sprint actual"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep -q 'sprint-status' "$TMPDIR_SCM/.scm/categories/planning.scm"
  grep -q 'Estado del sprint actual' "$TMPDIR_SCM/.scm/categories/planning.scm"
}

@test "generator stdout reports resource counts" {
  mk_cmd "alpha" "Alpha command"
  mk_agent "beta" "Beta agent"
  run python3 "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCM generated"* ]]
  [[ "$output" == *"commands"* ]]
}

@test "INDEX.scm header shows correct resource counts" {
  mk_cmd "c1" "Cmd one"
  mk_cmd "c2" "Cmd two"
  mk_agent "a1" "Agent one"
  python3 "$SCRIPT" "$TMPDIR_SCM"
  grep -q '2 commands' "$TMPDIR_SCM/.scm/INDEX.scm"
  grep -q '1 agents' "$TMPDIR_SCM/.scm/INDEX.scm"
}

@test "error: missing directory argument handled gracefully" {
  run python3 "$SCRIPT" "/nonexistent-dir-$$"
  [ "$status" -eq 2 ]
  [[ "$output" == *"directory not found"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "error: empty workspace produces valid but minimal output" {
  run python3 "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_SCM/.scm/INDEX.scm" ]
}

@test "edge: empty frontmatter description still classified" {
  mk_cmd "orphan-cmd" ""
  run python3 "$SCRIPT" "$TMPDIR_SCM"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_SCM/.scm/INDEX.scm" ]
}
