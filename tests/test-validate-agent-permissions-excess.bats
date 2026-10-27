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
  printf 'x Bash operadora 2099-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --verbose --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BASELINE: x (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"Baselined excess: 1"* ]]
}

@test "ratchet: excess not in baseline still fails" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash, Write]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2099-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Write"* ]]
}

@test "ratchet: stale baseline entry fails so the list only shrinks" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2099-01-01\n' > "$TMPDIR_AP/base.txt"
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

@test "transient: expired baseline entry stops absorbing the excess" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2026-11-10\n' > "$TMPDIR_AP/base.txt"
  AGENT_PERMS_TODAY=2026-11-11 run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash (baseline entry expired 2026-11-10"* ]]
}

@test "transient: entry still valid on its expiry day" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2026-11-10\n' > "$TMPDIR_AP/base.txt"
  AGENT_PERMS_TODAY=2026-11-10 run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
}

@test "transient: entry without owner or date is an error" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  for entry in 'x Bash' 'x Bash operadora' 'x Bash operadora soon' 'x Bash operadora 2026-13-45'; do
    printf '%s\n' "$entry" > "$TMPDIR_AP/base.txt"
    run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed baseline entry"* ]]
    [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
  done
}

@test "transient: missing baseline file is an error, not a pass" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/nope.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"baseline file not found"* ]]
}

@test "new excess: an agent absent from a non-empty baseline cannot add a tool" {
  printf -- '---\nname: old\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/old.md"
  printf -- '---\nname: fresh\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/fresh.md"
  printf 'old Bash operadora 2099-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fresh (L0) — excess tool: Bash"* ]]
  [[ "$output" != *"old (L0) — excess tool"* ]]
}

@test "real repo: new excess on a real agent fails despite the real baseline" {
  cp -r "$REPO_ROOT/.claude/agents" "$TMPDIR_AP/real"
  # tools: line of a conforming agent gains Bash; its name is not in the baseline
  sed -i 's/^tools: .*/tools: [Read, Glob, Grep, Bash]/' "$TMPDIR_AP/real/code-reviewer.md"
  sed -i 's/^permission_level: .*/permission_level: L0/' "$TMPDIR_AP/real/code-reviewer.md"
  run bash "$SCRIPT" "$TMPDIR_AP/real" --baseline "$BASELINE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"code-reviewer (L0) — excess tool: Bash"* ]]
}

@test "parser: inline list continued on following lines is fully read" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Glob,\n  Grep, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
}

@test "parser: blank line inside a block list does not hide later tools" {
  printf -- '---\nname: x\npermission_level: L0\ntools:\n  - Read\n\n  - Bash\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
}

@test "parser: trailing comment on a map value does not hide a true tool" {
  printf -- '---\nname: x\npermission_level: L0\ntools:\n  read: true\n  bash: true # needed\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
}

@test "parser: comments in a conforming list are not read as tools" {
  printf -- '---\nname: x\npermission_level: L0\ntools:\n  # read-only set\n  - Read # files\n  - Grep\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Errors:  0"* ]]
}

@test "parser: commented-out tool in an inline list is ignored" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Grep] # Bash removed\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
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
