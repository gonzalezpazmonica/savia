#!/usr/bin/env bats
# SE-376 wave1 — consolidacion agent-code-map
S=".claude/skills/agent-code-map/SKILL.md"
D=".claude/skills/agent-code-map/DOMAIN.md"
@test "[agent-code-map] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[agent-code-map] DOMAIN presente" { [ -f "$D" ]; }
@test "[agent-code-map] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
