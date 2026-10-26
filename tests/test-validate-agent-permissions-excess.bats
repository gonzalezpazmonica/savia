#!/usr/bin/env bats
# Ref: docs/rules/domain/agent-permission-levels.md
# Excess-tool detection for validate-agent-permissions.sh: the level is a
# MAXIMUM, so a tool above it must fail; the ratchet baseline can only shrink.
# Kept apart from the sealed tests/test-validate-agent-permissions.bats.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/validate-agent-permissions.sh"
  export BASELINE="$REPO_ROOT/docs/agent-permissions-excess-baseline.txt"
  TMPDIR_AP=$(mktemp -d)
  mkdir -p "$TMPDIR_AP/agents"
}

teardown() {
  rm -rf "$TMPDIR_AP"
}

@test "excess: L0 agent with seven tools fails naming agent and tools" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Glob, Grep, Write, Edit, Bash, Task]\n---\nX.\n' \
    > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -ne 0 ]
  [[ "$output" == *"x (L0) — excess tool: Write"* ]]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"x (L0) — excess tool: Task"* ]]
  [[ "$output" == *"Errors:  4"* ]]
}

@test "excess: block-list tools above L1 detected" {
  printf -- '---\nname: y\npermission_level: L1\ntools:\n  - Read\n  - Write\n---\nY.\n' \
    > "$TMPDIR_AP/agents/y.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"y (L1) — excess tool: Write"* ]]
}

@test "excess: map-format true tools detected, false ones ignored" {
  printf -- '---\nname: z\npermission_level: L1\ntools:\n  read: true\n  bash: false\n  task: true\n---\nZ.\n' \
    > "$TMPDIR_AP/agents/z.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"z (L1) — excess tool: Task"* ]]
  [[ "$output" != *"excess tool: Bash"* ]]
}

@test "negative: skills list after tools is not read as tools" {
  printf -- '---\nname: w\npermission_level: L0\ntools:\n  - Read\n  - Glob\n  - Grep\nskills:\n  - some-skill\n---\nW.\n' \
    > "$TMPDIR_AP/agents/w.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
  [[ "$output" != *"some-skill"* ]]
}

@test "negative: conforming agents at every level exit 0" {
  printf -- '---\nname: a\npermission_level: L0\ntools: [Read, Glob, Grep]\n---\n' > "$TMPDIR_AP/agents/a.md"
  printf -- '---\nname: b\npermission_level: L3\ntools: [Read, Write, Edit, Bash, Glob, Grep]\n---\n' > "$TMPDIR_AP/agents/b.md"
  printf -- '---\nname: c\npermission_level: L4\ntools: [Read, Bash, Task]\n---\n' > "$TMPDIR_AP/agents/c.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Errors:  0"* ]]
}

@test "ratchet: baselined excess passes and is reported verbosely" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --verbose --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASELINE: x (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"Baselined excess: 1"* ]]
}

@test "ratchet: excess not in baseline still fails" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash, Write]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Write"* ]]
}

@test "ratchet: stale baseline entry fails so the list only shrinks" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale baseline entry 'x Bash'"* ]]
}

@test "ratchet: default baseline not applied to foreign directories" {
  printf -- '---\nname: tech-writer\npermission_level: L2\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/tech-writer.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tech-writer (L2) — excess tool: Bash"* ]]
}

@test "real repo: passes with baseline, every entry consumed" {
  run bash "$SCRIPT" "$REPO_ROOT/.claude/agents"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale baseline"* ]]
}

@test "real repo: baseline never grows past its initial 25 pairs" {
  count=$(grep -cvE '^(#|$)' "$BASELINE")
  [ "$count" -le 25 ]
}
