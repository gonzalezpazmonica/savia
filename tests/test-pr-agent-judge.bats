#!/usr/bin/env bats
# SE-376 wave1 — consolidacion pr-agent-judge
S=".claude/skills/pr-agent-judge/SKILL.md"
D=".claude/skills/pr-agent-judge/DOMAIN.md"
@test "[pr-agent-judge] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[pr-agent-judge] DOMAIN presente" { [ -f "$D" ]; }
@test "[pr-agent-judge] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
