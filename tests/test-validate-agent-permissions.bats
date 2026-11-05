#!/usr/bin/env bats
# Ref: docs/rules/domain/agent-policies.md
# Tests for validate-agent-permissions.sh

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/validate-agent-permissions.sh"
  TMPDIR_AP=$(mktemp -d)
}

teardown() {
  rm -rf "$TMPDIR_AP"
}

@test "runs on real agents directory" {
  run bash "$SCRIPT" "$REPO_ROOT/.claude/agents"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Agent Permission Validation"* ]]
  [[ "$output" == *"Checked:"* ]]
}

@test "reports checked count > 0" {
  run bash "$SCRIPT" "$REPO_ROOT/.claude/agents"
  checked=$(echo "$output" | grep "Checked:" | grep -oE '[0-9]+')
  [[ "$checked" -gt 0 ]]
}

@test "handles empty directory" {
  mkdir -p "$TMPDIR_AP/empty"
  run bash "$SCRIPT" "$TMPDIR_AP/empty"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Checked: 0"* ]]
}

@test "handles agent without permission_level" {
  mkdir -p "$TMPDIR_AP/agents"
  cat > "$TMPDIR_AP/agents/test-agent.md" << 'EOF'
---
name: test-agent
tools:
  - Read
---
Test agent without permission level.
EOF
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --verbose
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"WARN"* ]]
}

@test "validates L0 agent correctly" {
  mkdir -p "$TMPDIR_AP/agents"
  cat > "$TMPDIR_AP/agents/observer.md" << 'EOF'
---
name: observer
permission_level: L0
tools:
  - Read
  - Glob
  - Grep
---
Observer agent.
EOF
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Errors:  0"* ]]
}

@test "detects unknown permission level" {
  mkdir -p "$TMPDIR_AP/agents"
  cat > "$TMPDIR_AP/agents/bad.md" << 'EOF'
---
name: bad-agent
permission_level: L9
tools:
  - Read
---
Bad level agent.
EOF
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"unknown level"* ]]
}

@test "script has safety flags" {
  head -5 "$SCRIPT" | grep -qE "set -[eu]o pipefail"
}

@test "edge: nonexistent directory returns zero checked" {
  run bash "$SCRIPT" "/nonexistent/path/xyz"
  [[ "$output" == *"Checked: 0"* ]] || [[ "$status" -ne 0 ]]
}

@test "edge: agent with special chars in name handled" {
  mkdir -p "$TMPDIR_AP/agents"
  echo -e "---\nname: bad\ntools: [Read]\n---\nTest." > "$TMPDIR_AP/agents/sp ecial.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [[ "$status" -le 1 ]]
}

@test "negative: L3 agent missing Write tool warns" {
  mkdir -p "$TMPDIR_AP/agents"
  cat > "$TMPDIR_AP/agents/dev.md" << 'EOF'
---
name: dev
permission_level: L3
tools:
  - Read
  - Glob
---
Dev with insufficient tools for L3.
EOF
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --verbose
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"missing"* ]]
}

@test "negative: multiple agents with errors counted" {
  mkdir -p "$TMPDIR_AP/agents"
  echo -e "---\nname: a\npermission_level: L99\ntools: [Read]\n---\nBad." > "$TMPDIR_AP/agents/a.md"
  echo -e "---\nname: b\npermission_level: L99\ntools: [Read]\n---\nBad." > "$TMPDIR_AP/agents/b.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Errors:  2"* ]]
}

@test "coverage: LEVEL_TOOLS array defined" {
  grep -q "LEVEL_TOOLS" "$SCRIPT"
}

# ── S03n: comportamiento discriminante ──────────────────────────────────────

# mk_agent <fichero-relativo> <frontmatter con \n>
mk_agent() {
  mkdir -p "$(dirname "$TMPDIR_AP/agents/$1")"
  printf -- '---\n%b\n---\nCuerpo.\n' "$2" > "$TMPDIR_AP/agents/$1"
}

@test "S03n: herramienta por encima del nivel es ERROR excess y exit 1" {
  mk_agent "reader.md" 'name: reader\npermission_level: L1\ntools: [Read, Bash, Write]'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: reader (L1) — excess tool: Write (above level)"* ]]
  [[ "$output" == *"Errors:  1"* ]]
}

@test "S03n: todas las herramientas del nivel exacto no dan error ni aviso" {
  mk_agent "full.md" 'name: full\npermission_level: L4\ntools: [Read, Write, Edit, Bash, Glob, Grep, Task]'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Errors:  0"* ]]
  [[ "$output" == *"Warnings: 0"* ]]
}

@test "S03n: Agent cuenta como Task (L3 no puede, L4 sí)" {
  mk_agent "a3.md" 'name: a3\npermission_level: L3\ntools: Read, Agent'
  mk_agent "b4.md" 'name: b4\npermission_level: L4\ntools: Read, Agent'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a3 (L3) — excess tool: Task"* ]]
  [[ "$output" != *"b4 (L4) — excess"* ]]
  [[ "$output" == *"Errors:  1"* ]]
}

@test "S03n: Bash(args) cuenta como Bash y la coma dentro del paréntesis no parte la lista" {
  mk_agent "ro.md" 'name: ro\npermission_level: L0\ntools: "Read, Bash(git log, git diff)"'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ro (L0) — excess tool: Bash (above level)"* ]]
  [[ "$output" != *"git_diff"* ]]
}

@test "S03n: memory: implica Write y Edit y cuentan contra el nivel" {
  mk_agent "mem.md" 'name: mem\npermission_level: L1\ntools: [Read, Bash]\nmemory: project'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mem (L1) — excess tool: Write (above level, implied by memory:)"* ]]
  [[ "$output" == *"mem (L1) — excess tool: Edit (above level, implied by memory:)"* ]]
}

@test "S03n: memory: none no implica herramientas" {
  mk_agent "nomem.md" 'name: nomem\npermission_level: L1\ntools: [Read, Bash]\nmemory: none'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 0 ]
}

@test "S03n: sin clave tools el agente hereda todo y es ERROR (fail-closed)" {
  mk_agent "inherit.md" 'name: inherit\npermission_level: L4'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"inherit (L4) — no tools: list, the agent inherits every tool"* ]]
}

@test "S03n: lista de tools vacía es ERROR por ambigua" {
  mk_agent "empty.md" 'name: empty\npermission_level: L1\ntools: []'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty — unparseable frontmatter: empty tools list"* ]]
}

@test "S03n: mapa de tools con valor no booleano es ERROR y con false no cuenta" {
  mk_agent "m1.md" 'name: m1\npermission_level: L0\ntools:\n  Read: true\n  Write: false'
  mk_agent "m2.md" 'name: m2\npermission_level: L0\ntools:\n  Read: "si"'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"m2 — unparseable frontmatter: tools map value for 'Read' is not true/false"* ]]
  [[ "$output" != *"m1"* ]]
  [[ "$output" == *"Errors:  1"* ]]
}

@test "S03n: clave duplicada en el frontmatter es ERROR" {
  mk_agent "dup.md" 'name: dup\npermission_level: L0\ntools: [Read]\ntools: [Read, Write, Bash]'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dup — unparseable frontmatter: duplicate key 'tools'"* ]]
}

@test "S03n: fichero sin bloque de frontmatter inicial es ERROR" {
  mkdir -p "$TMPDIR_AP/agents"
  printf 'Sin frontmatter\n---\nname: x\n---\n' > "$TMPDIR_AP/agents/nofm.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nofm — unparseable frontmatter: no frontmatter block"* ]]
}

@test "S03n: sin permission_level se trata como L0 y el exceso no se esconde" {
  mk_agent "nolevel.md" 'name: nolevel\ntools: [Read, Bash]'
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nolevel (L0) — excess tool: Bash"* ]]
}

@test "S03n: avisos cuentan cada herramienta del nivel no declarada" {
  mk_agent "l3.md" 'name: l3\npermission_level: L3\ntools: [Read, Glob]'
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --verbose
  [ "$status" -eq 0 ]
  [[ "$output" == *"Warnings: 4"* ]]
  [[ "$output" == *"WARN: l3 (L3) — missing tool: Write"* ]]
  [[ "$output" == *"WARN: l3 (L3) — missing tool: Grep"* ]]
}

@test "S03n: agentes en subdirectorio se validan y los .md sin frontmatter se ignoran" {
  mk_agent "top.md" 'name: top\npermission_level: L0\ntools: [Read]'
  mk_agent "team/sub.md" 'name: sub\npermission_level: L0\ntools: [Read, Write]'
  printf '# Árbol de decisión\n' > "$TMPDIR_AP/agents/team/doc.md"
  run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Checked: 2 agents"* ]]
  [[ "$output" == *"sub (L0) — excess tool: Write"* ]]
}

@test "S03n: directorio inexistente es ERROR con exit 1" {
  run bash "$SCRIPT" "$TMPDIR_AP/no-hay"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: agents directory not found"* ]]
}

@test "S03n: baseline vigente absorbe el exceso; caducada y obsoleta fallan" {
  mk_agent "x.md" 'name: x\npermission_level: L0\ntools: [Read, Bash]'
  printf 'x Bash ops 2999-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Baselined excess: 1"* ]]
  printf 'x Bash ops 2000-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"baseline entry expired 2000-01-01"* ]]
  printf 'x Bash ops 2999-01-01\nx Write ops 2999-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale baseline entry 'x Write'"* ]]
}

@test "S03n: la caducidad es el último día válido (frontera con AGENT_PERMS_TODAY)" {
  mk_agent "x.md" 'name: x\npermission_level: L0\ntools: [Read, Bash]'
  printf 'x Bash ops 2999-06-15\n' > "$TMPDIR_AP/base.txt"
  AGENT_PERMS_TODAY=2999-06-15 run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 0 ]
  AGENT_PERMS_TODAY=2999-06-16 run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expired 2999-06-15"* ]]
}

@test "S03n: AGENT_PERMS_TODAY en el pasado o inválida es ERROR" {
  mk_agent "ok.md" 'name: ok\npermission_level: L0\ntools: [Read]'
  AGENT_PERMS_TODAY=2000-01-01 run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"it may only move the date forward"* ]]
  AGENT_PERMS_TODAY=2999-02-30 run bash "$SCRIPT" "$TMPDIR_AP/agents"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a valid YYYY-MM-DD date"* ]]
}

@test "S03n: baseline sin owner o con fecha imposible, o duplicada, es ERROR" {
  mk_agent "x.md" 'name: x\npermission_level: L0\ntools: [Read, Bash]'
  printf 'x Bash 2999-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed baseline entry 'x Bash'"* ]]
  printf 'x Bash ops 2999-01-01\nx Bash ops 2999-01-01\n' > "$TMPDIR_AP/base.txt"
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline "$TMPDIR_AP/base.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate baseline entry 'x Bash'"* ]]
}

@test "S03n: --baseline sin fichero es error de uso (exit 2)" {
  run bash "$SCRIPT" "$TMPDIR_AP/agents" --baseline
  [ "$status" -eq 2 ]
  [[ "$output" == *"--baseline needs a file"* ]]
}
