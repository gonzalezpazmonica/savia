#!/usr/bin/env bats
# Ref: docs/rules/domain/agent-permission-levels.md
# Excess-tool detection for validate-agent-permissions.sh: the level is a
# MAXIMUM, so a tool above it must fail; the ratchet baseline can only shrink.
# Kept apart from the sealed tests/test-validate-agent-permissions.bats.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/validate-agent-permissions.sh"
  export BASELINE="${AGENT_PERMS_TEST_BASELINE:-$REPO_ROOT/docs/agent-permissions-excess-baseline.txt}"
  TMPDIR_AP=$(mktemp -d)
  mkdir -p "$TMPDIR_AP/agents"
  # expiry in the future and the day after it (the override only moves forward)
  EXP=$(date -d '+30 days' +%F)
  EXP_NEXT=$(date -d "$EXP +1 day" +%F)
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
  printf 'x Bash operadora %s\n' "$EXP" > "$TMPDIR_AP/base.txt"
  AGENT_PERMS_TODAY=$EXP_NEXT run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash (baseline entry expired $EXP"* ]]
}

@test "transient: entry still valid on its expiry day" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora %s\n' "$EXP" > "$TMPDIR_AP/base.txt"
  AGENT_PERMS_TODAY=$EXP run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTE: AGENT_PERMS_TODAY override in effect: $EXP"* ]]
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

@test "real repo: baseline is a subset of the 25 pairs authorised on 2026-10-27" {
  # The ONLY pairs ever allowed. Swapping one for another, or adding one, fails
  # here even if the count stays the same; the list may only shrink.
  allowed=" context-dome-manager:Bash excel-digest:Bash legal-compliance:Bash memory-agent:Bash
    pdf-digest:Bash pptx-digest:Bash recommendation-tribunal-orchestrator:Bash sdd-spec-writer:Bash
    tech-writer:Bash truth-tribunal-orchestrator:Bash visual-digest:Bash word-digest:Bash
    diagram-architect:Write model-upgrade-auditor:Write diagram-architect:Edit
    context-dome-manager:Task excel-digest:Task meeting-digest:Task model-upgrade-auditor:Task
    pdf-digest:Task pptx-digest:Task recommendation-tribunal-orchestrator:Task
    truth-tribunal-orchestrator:Task word-digest:Task context-dome-manager:Skill "
  allowed=$(echo $allowed)
  n=0
  while read -r agent tool owner expires _; do
    [[ -z "$agent" || "$agent" == \#* ]] && continue
    n=$((n + 1))
    [[ " $allowed " == *" $agent:$tool "* ]] || { echo "not authorised: $agent $tool"; return 1; }
    # expiry can never be pushed past the authorised date
    [[ ! "$expires" > "2026-11-10" ]] || { echo "expiry extended: $agent $tool $expires"; return 1; }
  done < "$BASELINE"
  [ "$n" -le 25 ]
}

@test "ratchet: swapping a baseline pair for an unauthorised one is caught by the subset check" {
  sed 's/^tech-writer Bash /code-reviewer Bash /' "$BASELINE" > "$TMPDIR_AP/swapped.txt"
  AGENT_PERMS_TEST_BASELINE="$TMPDIR_AP/swapped.txt" run bats -f "baseline is a subset" "$BATS_TEST_FILENAME"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not authorised: code-reviewer Bash"* ]]
}

@test "ratchet: duplicate baseline entry is an error" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2099-01-01\nx Bash operadora 2099-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate baseline entry 'x Bash'"* ]]
}

@test "ratchet: last baseline line without newline is still read" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora 2099-01-01' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale baseline entry 'x Bash'"* ]]
}

@test "usage: --baseline without a file is a usage error" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline
  [ "$status" -eq 2 ]
  [[ "$output" == *"--baseline needs a file"* ]]
}

@test "date override: invalid or past AGENT_PERMS_TODAY cannot extend an expiry" {
  printf -- '---\nname: x\npermission_level: L0\ntools: [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf 'x Bash operadora %s\n' "$EXP" > "$TMPDIR_AP/base.txt"
  for d in 0000-00-00 2001-01-01 tomorrow 2026-02-30; do
    AGENT_PERMS_TODAY=$d run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AGENT_PERMS_TODAY"* ]]
  done
}

@test "parser: unindented block list is read (valid YAML)" {
  printf -- '---\nname: x\npermission_level: L0\ntools:\n- Read\n- Bash\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
}

@test "parser: quoted key and !!bool map value are read" {
  printf -- '---\nname: x\npermission_level: L0\n"tools": [Read, Bash]\n---\n' > "$TMPDIR_AP/agents/x.md"
  printf -- '---\nname: y\npermission_level: L0\ntools:\n  read: true\n  bash: !!bool true\n  task: yes\n---\n' > "$TMPDIR_AP/agents/y.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"y (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"y (L0) — excess tool: Task"* ]]
}

@test "parser: CRLF frontmatter is parsed, not skipped" {
  printf -- '---\r\nname: x\r\npermission_level: L0\r\ntools: [Read, Bash]\r\n---\r\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
}

@test "negative: flow-map tools within the level pass" {
  printf -- '---\nname: x\npermission_level: L0\ntools: {read: true, glob: true, grep: true, bash: false}\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Errors:  0"* ]]
}

@test "fail-closed: non-boolean map value, missing tools and bad YAML are errors" {
  printf -- '---\nname: a\npermission_level: L1\ntools:\n  read: true\n  bash: allow\n---\n' > "$TMPDIR_AP/agents/a.md"
  printf -- '---\nname: b\npermission_level: L1\n---\n' > "$TMPDIR_AP/agents/b.md"
  printf -- '---\nname: c\npermission_level: L1\ndescription: bad: colon\ntools: [Read]\n---\n' > "$TMPDIR_AP/agents/c.md"
  printf -- '---\nname: d\npermission_level: L1\ntools: [Read]\ntools: [Read, Task]\n---\n' > "$TMPDIR_AP/agents/d.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a — unparseable frontmatter: tools map value for 'bash' is not true/false"* ]]
  [[ "$output" == *"b (L1) — no tools: list, the agent inherits every tool"* ]]
  [[ "$output" == *"c — unparseable frontmatter"* ]]
  [[ "$output" == *"d — unparseable frontmatter"*"duplicate key"* ]]
  [[ "$output" == *"Errors:  4"* ]]
}

@test "fail-closed: agent without permission_level is held to L0" {
  printf -- '---\nname: x\ntools: [Read, Bash, Write, Task]\n---\n' > "$TMPDIR_AP/agents/x.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L0) — excess tool: Bash"* ]]
  [[ "$output" == *"x (L0) — excess tool: Task"* ]]
}

@test "fail-closed: nonexistent agents directory is an error" {
  run bash "$SCRIPT" "$TMPDIR_AP/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agents directory not found"* ]]
}

@test "parser: wildcard tool names are not glob-expanded" {
  touch "$TMPDIR_AP/agents/Bashfoo"
  printf -- '---\nname: x\npermission_level: L1\ntools: [Read, "Bash*"]\n---\n' > "$TMPDIR_AP/agents/x.md"
  cd "$TMPDIR_AP/agents"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x (L1) — excess tool: Bash*"* ]]
  [[ "$output" != *"Bashfoo"* ]]
}

@test "ci: the PR workflow runs the agent permission gate and both suites" {
  ci="$REPO_ROOT/.github/workflows/ci.yml"
  grep -q 'bash scripts/validate-agent-permissions.sh .claude/agents' "$ci"
  grep -q 'tests/test-validate-agent-permissions.bats tests/test-validate-agent-permissions-excess.bats' "$ci"
}
