#!/usr/bin/env bats
# SE-376 wave1 — consolidacion tech-research-agent
S=".claude/skills/tech-research-agent/SKILL.md"
D=".claude/skills/tech-research-agent/DOMAIN.md"
@test "[tech-research-agent] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[tech-research-agent] DOMAIN presente" { [ -f "$D" ]; }
@test "[tech-research-agent] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
